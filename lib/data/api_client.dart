// ------------------------------------------------------------
// Ziel (Laien): Worker ansprechen, Curriculum laden und Assets prüfen.
// Strategie: HEAD/Range-Checks nutzen, Bildvarianten sammeln, Audio pro Sprache verifizieren.
// Schritte: loadCurriculum -> loadItem (JSON/Bild/Audio) -> hasAudioForAllLangs für Seeds.
// Tücken: Einige Worker liefern auf HEAD 404, deshalb Range-GET; Zeitouts beachten.
// ------------------------------------------------------------
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../constants.dart';
import 'models.dart';

/// API-Client: holt Curriculum, Items und prüft/verarbeitet Assets.
class ApiClient {
  ApiClient({required this.workerHost, required this.apiPrefix});

  final String workerHost;
  final String apiPrefix;
  final http.Client _http = http.Client();
  static const Duration _getTimeout = Duration(seconds: 12);
  static const Duration _headTimeout = Duration(seconds: 8);
  static const List<String> _imageSuffixes = [
    '_01',
    '_02',
    '_03',
    '_04',
    '_05',
    '_06',
    '_07',
    '_08',
    '_09',
    '_10',
    '_1',
    '_2'
  ]; // Fallback: nummerierte Varianten
  static const List<String> _audioVariantSuffixes = ['_1', '_2'];
  // Prefer WebP (smaller/faster), fall back to legacy formats if missing.
  static const List<String> _imageExts = ['webp', 'png', 'gif', 'jpg', 'jpeg'];
  static const int _maxImageVariantsToFetch =
      11; // Basis + bis zu 10 Varianten (start_curriculum_l has more)
  static const int _missingAudioLength = 11015;
  static const int _missingAudioSampleSize = 256;
  static const int _missingAudioSampleHash = 1993370479;
  static const Set<String> _knownVideoOnlyUuids = {
    '2lt5i7g3',
    '5t8m2x9q',
    '7n2k5x8m',
  };

  // Hilfsfunktion: baut eine HTTPS-URL zum Worker inkl. Query-Parametern
  Uri _path(String path, [Map<String, String>? query]) {
    return Uri.https(workerHost, '$apiPrefix$path', query);
  }

  Future<http.Response> _get(Uri uri) {
    return _http.get(uri).timeout(_getTimeout);
  }

  Future<http.Response> _head(Uri uri) {
    return _http.head(uri).timeout(_headTimeout);
  }

  int? _parsePosition(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  List<CurriculumEntry> _sortEntriesByPosition(List<CurriculumEntry> entries) {
    if (entries.length < 2) return entries;
    final indexed = entries.asMap().entries.toList();
    indexed.sort((a, b) {
      final posA = a.value.position ?? a.key;
      final posB = b.value.position ?? b.key;
      final cmp = posA.compareTo(posB);
      if (cmp != 0) return cmp;
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  Future<List<CurriculumEntry>> loadCurriculum(String lang) async {
    final uri = _path('/curriculum', {'lang': lang});
    try {
      final res = await _get(uri);
      if (res.statusCode != 200) {
        debugPrint(
            '[api] curriculum $lang failed status=${res.statusCode} uri=$uri');
        return [];
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final items = (data['items'] as List?) ?? [];
      final entries = items
          .map((e) => CurriculumEntry(
                uuid: e['uuid'] as String,
                index: (e['index'] ?? '') as String,
                position: _parsePosition(e['position']),
              ))
          .toList();
      return _sortEntriesByPosition(entries);
    } catch (e) {
      debugPrint('[api][error] curriculum $lang $e');
      return [];
    }
  }

  List<Uri> _startCurriculumCandidates(
      String fileName, bool allowDefaultFallback) {
    final List<Uri> candidates = [
      ..._bucketUris(fileName),
      _path('/file', {'key': fileName}),
    ];
    if (allowDefaultFallback && fileName != defaultStartCurriculum) {
      candidates.addAll(_bucketUris(defaultStartCurriculum));
      candidates.add(_path('/file', {'key': defaultStartCurriculum}));
    }
    return candidates;
  }

  bool _shouldSkipCompleteCheckForLStart(String fileName) {
    final normalized = fileName.toLowerCase();
    return normalized.startsWith('start_curriculum_l_');
  }

  Future<List<CurriculumEntry>> loadStartCurriculum(String fileName,
      {bool allowDefaultFallback = false,
      String? requireCompleteForLang}) async {
    // Reihenfolge: R2-Bucket (beide URL-Varianten, gewünschte Datei),
    // dann Worker (gewünschte Datei). Optional (allowDefaultFallback):
    // erst, wenn explizit erlaubt, probieren wir das Default-Curriculum.
    // So verhindert: Start-Button "Travel" fällt stillschweigend auf A zurück.
    final data = await _fetchCurriculumJson(
        _startCurriculumCandidates(fileName, allowDefaultFallback));
    if (data == null) {
      throw Exception('Start-Curriculum fehlgeschlagen ($fileName)');
    }
    List items = (data['items'] as List?) ?? [];
    if (items.isEmpty && data['item_order'] is List) {
      items = data['item_order'] as List;
    }
    var entries = items
        .map((e) => CurriculumEntry(
              uuid: e['uuid'] as String,
              index: (e['index'] ?? '') as String,
              position: _parsePosition(e['position']),
            ))
        .where((e) => !_knownVideoOnlyUuids.contains(e.uuid))
        .toList();
    entries = _sortEntriesByPosition(entries);
    final shouldValidateForLang = requireCompleteForLang != null &&
        requireCompleteForLang.isNotEmpty &&
        !_shouldSkipCompleteCheckForLStart(fileName);
    if (shouldValidateForLang) {
      const limit =
          startCurriculumWindowSize > 0 ? startCurriculumWindowSize : null;
      entries = await _pickCompleteEntries(entries, requireCompleteForLang!,
          limit: limit);
    }
    if (startCurriculumWindowSize > 0 &&
        entries.length > startCurriculumWindowSize) {
      entries = entries.take(startCurriculumWindowSize).toList();
    }
    return entries;
  }

  Future<Map<String, dynamic>?> loadStartCurriculumJson(String fileName,
      {bool allowDefaultFallback = false}) async {
    return _fetchCurriculumJson(
        _startCurriculumCandidates(fileName, allowDefaultFallback));
  }

  Future<Map<String, dynamic>?> _fetchCurriculumJson(
      List<Uri> candidates) async {
    for (final uri in candidates) {
      try {
        final res = await _get(uri);
        if (res.statusCode == 200) {
          return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        }
      } catch (_) {
        // nächste Quelle probieren
      }
    }
    return null;
  }

  List<Uri> _bucketUris(String fileName) {
    return [
      Uri.parse('$curriculumBucketVirtualHost/$fileName'),
      Uri.parse('$curriculumBucketPathBase/$fileName'),
    ];
  }

  Future<(bool ok, int status)> _urlOk(Uri url) async {
    try {
      final r = await _head(url);
      if (r.statusCode == 200) return (true, r.statusCode);
      if (kIsWeb) return (false, r.statusCode);
    } catch (_) {
      if (kIsWeb) return (false, -1);
      // ignore and fall back to GET
    }
    try {
      // Einige Worker liefern auf HEAD 404. Range-GET testet Audio minimal.
      final req = http.Request('GET', url)..headers['range'] = 'bytes=0-0';
      final res = await _http.send(req).timeout(_headTimeout);
      await res.stream.drain();
      final status = res.statusCode;
      return (status == 200 || status == 206, status);
    } catch (_) {
      return (false, -1);
    }
  }

  Future<bool> urlOk(Uri url) async {
    final (ok, _) = await _urlOk(url);
    return ok;
  }

  bool _looksLikeMp3(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return true; // "ID3"
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return true; // frame sync
    }
    return false;
  }

  int _byteSampleHash(List<int> bytes, int maxBytes) {
    final sampleLen = bytes.length < maxBytes ? bytes.length : maxBytes;
    int hash = 0;
    for (int i = 0; i < sampleLen; i++) {
      hash = (hash * 31 + bytes[i]) & 0x7fffffff;
    }
    return hash;
  }

  int? _parseTotalLength(Map<String, String> headers) {
    final contentRange = headers['content-range'];
    if (contentRange != null) {
      final parts = contentRange.split('/');
      if (parts.length == 2) {
        final total = int.tryParse(parts[1].trim());
        if (total != null) return total;
      }
    }
    final contentLength = headers['content-length'];
    if (contentLength != null) {
      return int.tryParse(contentLength);
    }
    return null;
  }

  bool _isMissingAudioPlaceholder(List<int> bytes, int? totalLength) {
    if (bytes.length < _missingAudioSampleSize) return false;
    if (totalLength != null && totalLength != _missingAudioLength) return false;
    final hash = _byteSampleHash(bytes, _missingAudioSampleSize);
    return hash == _missingAudioSampleHash;
  }

  Future<List<int>> _readPrefix(Stream<List<int>> stream, int maxBytes) async {
    final buffer = <int>[];
    await for (final chunk in stream) {
      buffer.addAll(chunk);
      if (buffer.length >= maxBytes) break;
    }
    if (buffer.length > maxBytes) {
      buffer.removeRange(maxBytes, buffer.length);
    }
    return buffer;
  }

  Future<(bool ok, int status)> _audioUrlOk(Uri url) async {
    if (kIsWeb) {
      try {
        final res = await _head(url);
        return (res.statusCode == 200, res.statusCode);
      } catch (_) {
        return (false, -1);
      }
    }
    try {
      final req = http.Request('GET', url)
        ..headers['range'] = 'bytes=0-${_missingAudioSampleSize - 1}';
      final res = await _http.send(req).timeout(_headTimeout);
      final status = res.statusCode;
      if (status != 200 && status != 206) {
        await res.stream.drain();
        return (false, status);
      }
      final bytes = await _readPrefix(res.stream, _missingAudioSampleSize);
      final totalLength = _parseTotalLength(res.headers);
      final ok = _looksLikeMp3(bytes) &&
          !_isMissingAudioPlaceholder(bytes, totalLength);
      return (ok, status);
    } catch (_) {
      return (false, -1);
    }
  }

  Future<bool> audioUrlOk(Uri url) async {
    final (ok, _) = await _audioUrlOk(url);
    return ok;
  }

  Future<bool> _jsonExists(String uuid) async {
    final (ok, _) = await _urlOk(_path('/file', {'key': '$uuid.json'}));
    return ok;
  }

  Future<bool> _imageExists(String uuid) async {
    for (final ext in _imageExts) {
      final baseUri = _path('/file', {'key': '$uuid.$ext'});
      final (ok, _) = await _urlOk(baseUri);
      if (ok) return true;
      for (final suffix in _imageSuffixes) {
        final uri = _path('/file', {'key': '$uuid$suffix.$ext'});
        final (ok, _) = await _urlOk(uri);
        if (ok) return true;
      }
    }
    return false;
  }

  Future<bool> _isCompleteStartItem(String uuid, String lang) async {
    if (!await _jsonExists(uuid)) return false;
    if (!await hasAudioForLang(uuid, lang)) return false;
    return _imageExists(uuid);
  }

  Future<List<CurriculumEntry>> _pickCompleteEntries(
    List<CurriculumEntry> entries,
    String lang, {
    int? limit,
  }) async {
    final List<CurriculumEntry> picked = [];
    for (final entry in entries) {
      if (!await _isCompleteStartItem(entry.uuid, lang)) continue;
      picked.add(entry);
      if (limit != null && picked.length >= limit) break;
    }
    return picked;
  }

  Future<ItemData> loadItem(CurriculumEntry entry, String lang,
      {String? nativeLang}) async {
    // JSON
    final metaUri = _path('/file', {'key': '${entry.uuid}.json'});
    final metaRes = await _get(metaUri);
    if (metaRes.statusCode != 200) {
      throw Exception(
          'Meta missing ${entry.uuid} url=$metaUri status=${metaRes.statusCode}');
    }
    final meta =
        jsonDecode(utf8.decode(metaRes.bodyBytes)) as Map<String, dynamic>;
    final text =
        (meta['display_$lang'] ?? meta['text_$lang'] ?? meta['text'] ?? '')
            .toString();
    final String? phonetic = meta['phonetic_$lang']?.toString();
    String? nativeText;
    if (nativeLang != null && nativeLang != lang) {
      nativeText =
          (meta['display_$nativeLang'] ?? meta['text_$nativeLang'])?.toString();
    }
    int? position = entry.position;
    position ??= _parsePosition(meta['position']);

    // Bildvarianten (PNG/GIF) laden; falls mehrere vorhanden, später zufällig wählen
    final variants = await _loadImageVariants(entry.uuid);

    // MP3 (muss existieren)
    final audioVariants = await _loadAudioVariants(entry.uuid, lang);
    final audioUri = audioVariants.first;

    return ItemData(
      uuid: entry.uuid,
      index: entry.index,
      position: position,
      text: text.isEmpty ? jsonEncode(meta) : text,
      nativeText: nativeText,
      phonetic: phonetic,
      imageBytes: variants.first,
      imageVariants: variants,
      audioUri: audioUri,
      audioVariants: audioVariants,
      imageSignature: _imageSignature(variants.first),
    );
  }

  // einfache, schnelle Signatur aus Länge und ersten Bytes
  String _imageSignature(Uint8List bytes) {
    final len = bytes.length;
    final sample = bytes.length >= 12 ? bytes.sublist(0, 12) : bytes;
    int hash = 0;
    for (final b in sample) {
      hash = (hash * 31 + b) & 0x7fffffff;
    }
    return '$len-$hash';
  }

  Future<List<Uint8List>> _loadImageVariants(String uuid) async {
    final Random rand = Random();
    final List<Uint8List> found = [];
    // zuerst Basis ohne Suffix, dann durchnummerierte Varianten
    for (final ext in _imageExts) {
      final uriBase = _path('/file', {'key': '$uuid.$ext'});
      try {
        final res = await _get(uriBase);
        if (res.statusCode == 200) {
          found.add(res.bodyBytes);
        }
      } catch (_) {}

      for (final suffix in _imageSuffixes) {
        if (found.length >= _maxImageVariantsToFetch) break;
        final uri = _path('/file', {'key': '$uuid$suffix.$ext'});
        http.Response? res;
        try {
          res = await _get(uri);
        } catch (_) {
          continue;
        }
        if (res.statusCode == 200) {
          found.add(res.bodyBytes);
        }
      }
      if (found.isNotEmpty || found.length >= _maxImageVariantsToFetch) break;
    }
    if (found.isEmpty) {
      throw Exception(
          'Image missing $uuid (checked webp/png/gif/jpg variants)');
    }
    // Zufällig durchmischen, damit first schon variiert
    found.shuffle(rand);
    return found;
  }

  Future<List<Uri>> _loadAudioVariants(String uuid, String lang) async {
    final baseUri = _path('/file', {'key': '${uuid}_$lang.mp3'});
    final (ok, status) = await _audioUrlOk(baseUri);
    if (!ok) {
      throw Exception(
          'Audio missing $uuid lang=$lang url=$baseUri status=$status');
    }
    final List<Uri> variants = [baseUri];
    for (final suffix in _audioVariantSuffixes) {
      final uri = _path('/file', {'key': '${uuid}_$lang$suffix.mp3'});
      final (okVariant, _) = await _audioUrlOk(uri);
      if (!okVariant) break;
      variants.add(uri);
    }
    return variants;
  }

  Future<bool> hasAudioForLang(String uuid, String lang) async {
    final audioUri = _path('/file', {'key': '${uuid}_$lang.mp3'});
    final (ok, _) = await _audioUrlOk(audioUri);
    return ok;
  }
}
