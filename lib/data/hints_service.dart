// ------------------------------------------------------------
// Ziel (Laien): Hint-Packs aus Worker/R2 laden, lokal cachen und normalisieren.
// Verbindung: robulingo_app.dart ruft loadPack() und zeigt Hinweise pro Item.
// Tuecken: L1/L2 normalisieren, Cache nicht zu alt werden lassen.
// ------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../logic/hint_pack_store.dart';
import 'hint_models.dart';

class HintsService {
  HintsService({
    required this.workerHost,
    required this.apiPrefix,
    http.Client? client,
    HintPackStore? store,
  })  : _http = client ?? http.Client(),
        _store = store ?? HintPackStore();

  final String workerHost;
  final String apiPrefix;
  final http.Client _http;
  final HintPackStore _store;

  static const Duration _timeout = Duration(seconds: 8);
  static const Duration _cacheMaxAge = Duration(hours: 6);
  static String normalizeLangCode(String? raw) {
    if (raw == null) return '';
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(RegExp(r'[-_]'));
    return parts.isNotEmpty ? parts.first : trimmed;
  }

  static String packKey(String l1, String l2) => 'hints_${l1}_$l2.json';

  static String hintLabelFor(String lang) {
    final code = normalizeLangCode(lang);
    return _hintLabels[code] ?? _hintLabels['en']!;
  }

  Future<HintPack?> loadPack({
    required String l1,
    required String l2,
    bool forceRefresh = false,
  }) async {
    final normL1 = normalizeLangCode(l1);
    final normL2 = normalizeLangCode(l2);
    if (normL1.isEmpty || normL2.isEmpty) return null;
    final cached = await _store.load(normL1, normL2);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final bool isStale = cached == null
        ? true
        : (nowMs - cached.fetchedAtMs) > _cacheMaxAge.inMilliseconds;
    if (!forceRefresh && cached != null && !isStale) return cached;
    final fetched = await _fetchPack(normL1, normL2, cached);
    if (fetched != null) {
      await _store.save(fetched);
      return fetched;
    }
    return cached;
  }

  Future<HintPack?> _fetchPack(String l1, String l2, HintPack? cached) async {
    final key = packKey(l1, l2);
    final candidates = _candidateUris(key, l1, l2);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    debugPrint(
        '[hints][fetch] l1=$l1 l2=$l2 key=$key cachedEtag=${cached?.etag ?? "-"}');
    for (final uri in candidates) {
      try {
        debugPrint('[hints][request] url=$uri');
        final headers = <String, String>{
          'accept': 'application/json',
        };
        if (cached?.etag != null) {
          headers['if-none-match'] = cached!.etag!;
        }
        final res = await _http.get(uri, headers: headers).timeout(_timeout);
        debugPrint(
            '[hints][response] status=${res.statusCode} url=$uri etag=${res.headers['etag'] ?? "-"} cf-cache-status=${res.headers['cf-cache-status'] ?? "-"}');
        if (res.statusCode == 304 && cached != null) {
          debugPrint('[hints][cache-hit] url=$uri');
          return cached.copyWith(fetchedAtMs: nowMs);
        }
        if (res.statusCode != 200) {
          debugPrint('[hints][status] ${res.statusCode} url=$uri');
          continue;
        }
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final parsed = _parsePack(
          data,
          l1: l1,
          l2: l2,
          fetchedAtMs: nowMs,
          etag: res.headers['etag'],
        );
        if (parsed != null) {
          return parsed;
        }
      } catch (e) {
        debugPrint('[hints][fetch-error] url=$uri err=$e');
      }
    }
    return null;
  }

  List<Uri> _candidateUris(String key, String l1, String l2) {
    final List<Uri> candidates = [
      Uri.https(workerHost, '$apiPrefix/hints', {'l1': l1, 'l2': l2}),
      Uri.parse('$hintsBucketVirtualHost/$key'),
      Uri.parse('$hintsBucketPathBase/$key'),
    ];
    return candidates;
  }

  HintPack? _parsePack(
    dynamic data, {
    required String l1,
    required String l2,
    required int fetchedAtMs,
    String? etag,
  }) {
    if (data is! Map) return null;
    final root = Map<String, dynamic>.from(data as Map);
    final rawHints = root['hints'];
    if (rawHints is! Map) return null;
    final Map<String, HintContent> hints = {};
    rawHints.forEach((key, value) {
      final hint = _parseHintContent(key.toString(), value);
      if (hint != null && !hint.isEmpty) {
        hints[key.toString()] = hint;
      }
    });
    if (hints.isEmpty) return null;
    final meta = root['meta'];
    final packVersion = meta is Map
        ? (meta['updated_at']?.toString() ?? root['version']?.toString())
        : root['version']?.toString();
    return HintPack(
      l1: l1,
      l2: l2,
      hints: hints,
      fetchedAtMs: fetchedAtMs,
      packVersion: packVersion,
      etag: etag,
    );
  }

  HintContent? _parseHintContent(String id, dynamic value) {
    if (value is String) {
      final body = value.trim();
      if (body.isEmpty) return null;
      return HintContent(id: id, body: body);
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final title = map['title']?.toString();
      final body = map['body']?.toString();
      final rawExamples = map['examples'];
      final examples = rawExamples is List
          ? rawExamples.whereType<String>().toList()
          : const <String>[];
      return HintContent(
        id: id,
        title: title?.trim().isNotEmpty == true ? title!.trim() : null,
        body: body?.trim().isNotEmpty == true ? body!.trim() : null,
        examples: examples,
      );
    }
    return null;
  }
}

const Map<String, String> _hintLabels = {
  'en': 'Hint',
  'de': 'Hinweis',
};
