import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Picks the best ASR localeId for a target language.
///
/// Goals:
/// - Prefer explicit overrides (e.g. it -> it-IT, el -> el-GR).
/// - Prefer exact localeId match, then language+region match, then language-only.
/// - Be tolerant to dash/underscore variants and extra subtags.
class AsrLocaleResolver {
  const AsrLocaleResolver();

  static String _norm(String s) => s.trim().toLowerCase().replaceAll('_', '-');

  static String _base(String norm) =>
      norm.split('-').where((p) => p.isNotEmpty).firstOrNull ?? '';

  static String _region(String norm) {
    final parts = norm.split('-').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return '';
    return parts[1];
  }

  String? resolveFromLocales(
    List<stt.LocaleName> locales, {
    required String lang,
    String? overrideLocaleId,
  }) {
    final desired = _norm(overrideLocaleId?.isNotEmpty == true ? overrideLocaleId! : lang);
    final desiredBase = _base(desired);
    final desiredRegion = _region(desired);
    if (desiredBase.isEmpty) return null;

    int scoreFor(String localeId) {
      final id = _norm(localeId);
      if (id.isEmpty) return -1;
      if (id == desired) return 100;
      if (id.startsWith('$desired-')) return 95; // desired + extra subtags
      final idBase = _base(id);
      if (idBase != desiredBase) return -1;
      if (desiredRegion.isNotEmpty) {
        final idRegion = _region(id);
        if (idRegion == desiredRegion) return 90;
      }
      return 80; // language-only match
    }

    stt.LocaleName? best;
    var bestScore = -1;
    for (final l in locales) {
      final s = scoreFor(l.localeId);
      if (s > bestScore) {
        bestScore = s;
        best = l;
      }
    }

    if (bestScore >= 0) return best!.localeId;
    return null;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

