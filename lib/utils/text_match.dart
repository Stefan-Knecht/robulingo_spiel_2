import 'dart:math';

import 'text_utils.dart';

class TranscriptMatch {
  const TranscriptMatch({
    required this.accepted,
    required this.reason,
    required this.transcript,
    required this.transcriptNorm,
    required this.candidateCount,
    this.matchedTarget,
    this.matchedTargetNorm,
    this.levenshtein,
    this.ratio,
  });

  final bool accepted;
  final String reason; // exact | contains | levenshtein | ratio | rejected | empty
  final String transcript;
  final String transcriptNorm;
  final int candidateCount;
  final String? matchedTarget;
  final String? matchedTargetNorm;
  final int? levenshtein;
  final double? ratio;
}

TranscriptMatch matchTranscriptToTargets(
  String transcript,
  Iterable<String> targets, {
  int maxDist = 3,
  double minRatio = 0.6,
}) {
  final tNorm = normalizeText(transcript);
  final dedupedTargets = <String>[];
  final seenRaw = <String>{};
  for (final raw in targets) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    final key = s.toLowerCase();
    if (seenRaw.add(key)) dedupedTargets.add(s);
  }

  if (tNorm.isEmpty || dedupedTargets.isEmpty) {
    return TranscriptMatch(
      accepted: false,
      reason: 'empty',
      transcript: transcript,
      transcriptNorm: tNorm,
      candidateCount: dedupedTargets.length,
    );
  }

  String? bestContainsTarget;
  String? bestContainsNorm;

  final normTargets = <String, String>{};
  for (final target in dedupedTargets) {
    final gNorm = normalizeText(target);
    if (gNorm.isEmpty) continue;
    normTargets[target] = gNorm;
    if (tNorm == gNorm) {
      return TranscriptMatch(
        accepted: true,
        reason: 'exact',
        transcript: transcript,
        transcriptNorm: tNorm,
        candidateCount: dedupedTargets.length,
        matchedTarget: target,
        matchedTargetNorm: gNorm,
        levenshtein: 0,
        ratio: 1.0,
      );
    }
    if (tNorm.contains(gNorm) || gNorm.contains(tNorm)) {
      // Prefer the "more specific" (longer) match for logging.
      if (bestContainsNorm == null || gNorm.length > bestContainsNorm.length) {
        bestContainsTarget = target;
        bestContainsNorm = gNorm;
      }
    }
  }

  if (bestContainsTarget != null && bestContainsNorm != null) {
    return TranscriptMatch(
      accepted: true,
      reason: 'contains',
      transcript: transcript,
      transcriptNorm: tNorm,
      candidateCount: dedupedTargets.length,
      matchedTarget: bestContainsTarget,
      matchedTargetNorm: bestContainsNorm,
    );
  }

  // Fallback: try to match within the transcript by comparing per-word (or
  // phrase-length n-grams) against each target. This helps with duplicated
  // words (e.g. "milk milk") or slight insertions that break full-string
  // matching (e.g. "γκαλά γκαλα" vs "γάλα").
  final tWords = tNorm.split(' ').where((w) => w.isNotEmpty).toList();
  TranscriptMatch? bestSubmatch;
  for (final entry in normTargets.entries) {
    final target = entry.key;
    final gNorm = entry.value;
    final gWords = gNorm.split(' ').where((w) => w.isNotEmpty).toList();
    if (gWords.isEmpty || tWords.isEmpty) continue;
    final window = gWords.length;
    if (tWords.length < window) continue;
    for (var i = 0; i <= tWords.length - window; i++) {
      final chunk = tWords.sublist(i, i + window).join(' ');
      final exact = chunk == gNorm;
      final contains = chunk.contains(gNorm) || gNorm.contains(chunk);
      if (exact || contains) {
        final match = TranscriptMatch(
          accepted: true,
          reason: exact ? 'token_exact' : 'token_contains',
          transcript: transcript,
          transcriptNorm: tNorm,
          candidateCount: dedupedTargets.length,
          matchedTarget: target,
          matchedTargetNorm: gNorm,
        );
        // Prefer an exact token match immediately.
        if (exact) return match;
        bestSubmatch ??= match;
        continue;
      }
      final dist = levenshtein(chunk, gNorm);
      final maxLen = max(chunk.length, gNorm.length);
      final ratio = maxLen == 0 ? 1.0 : 1.0 - dist / maxLen;
      final accepted = dist <= maxDist || ratio >= minRatio;
      if (!accepted) continue;
      final reason = (dist <= maxDist) ? 'token_levenshtein' : 'token_ratio';
      final candidate = TranscriptMatch(
        accepted: true,
        reason: reason,
        transcript: transcript,
        transcriptNorm: tNorm,
        candidateCount: dedupedTargets.length,
        matchedTarget: target,
        matchedTargetNorm: gNorm,
        levenshtein: dist,
        ratio: ratio,
      );
      if (bestSubmatch == null) {
        bestSubmatch = candidate;
        continue;
      }
      // Keep the closer accepted submatch.
      final bestRatio = bestSubmatch!.ratio ?? -1;
      final bestDist = bestSubmatch!.levenshtein ?? (1 << 30);
      if (ratio > bestRatio || (ratio == bestRatio && dist < bestDist)) {
        bestSubmatch = candidate;
      }
    }
  }
  if (bestSubmatch != null) return bestSubmatch!;

  String? bestTarget;
  String? bestNorm;
  int? bestDist;
  double? bestRatio;
  bool bestAccepted = false;

  for (final entry in normTargets.entries) {
    final target = entry.key;
    final gNorm = entry.value;
    final dist = levenshtein(tNorm, gNorm);
    final maxLen = max(tNorm.length, gNorm.length);
    final ratio = maxLen == 0 ? 1.0 : 1.0 - dist / maxLen;
    final accepted = dist <= maxDist || ratio >= minRatio;

    if (bestTarget == null) {
      bestTarget = target;
      bestNorm = gNorm;
      bestDist = dist;
      bestRatio = ratio;
      bestAccepted = accepted;
      continue;
    }

    if (bestAccepted != accepted) {
      if (accepted) {
        bestTarget = target;
        bestNorm = gNorm;
        bestDist = dist;
        bestRatio = ratio;
        bestAccepted = true;
      }
      continue;
    }

    // Both accepted or both rejected: keep the closer one (higher ratio, then lower dist).
    final currentBetter =
        (ratio > (bestRatio ?? -1)) || (ratio == bestRatio && dist < (bestDist ?? 1 << 30));
    if (currentBetter) {
      bestTarget = target;
      bestNorm = gNorm;
      bestDist = dist;
      bestRatio = ratio;
      bestAccepted = accepted;
    }
  }

  final reason = bestAccepted
      ? ((bestDist != null && bestDist <= maxDist) ? 'levenshtein' : 'ratio')
      : 'rejected';

  return TranscriptMatch(
    accepted: bestAccepted,
    reason: reason,
    transcript: transcript,
    transcriptNorm: tNorm,
    candidateCount: dedupedTargets.length,
    matchedTarget: bestTarget,
    matchedTargetNorm: bestNorm,
    levenshtein: bestDist,
    ratio: bestRatio,
  );
}
