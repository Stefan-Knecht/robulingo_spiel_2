// lib/data/api_client.dart
//
// Basierend auf der älteren ApiClient-Version (alte Schnittstellen bleiben erhalten)
// + ergänzt um die "neue" Funktionalität (start-curriculum/text/file), sodass die
// bisherigen Aufrufer (robulingo_app.dart, pick_manifest_service.dart) wieder kompilieren.

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiClient {
  static const int _missingMp3PlaceholderLength = 11015;
  static const int _maxImageVariantsPerItem = 5; // base + 01..04
  static const List<int> _missingMp3PlaceholderHead16 = <int>[
    0x49,
    0x44,
    0x33,
    0x04,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x22,
    0x54,
    0x53,
    0x53,
    0x45,
    0x00,
    0x00,
  ];

  final String workerHost; // z.B. robulingo-api.knechtipad-aec.workers.dev
  final String apiPrefix; // z.B. /api
  final http.Client _http;

  ApiClient({
    required this.workerHost,
    this.apiPrefix = '/api',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) {
    // apiPrefix kann "/api" oder "api" sein
    final pfx = apiPrefix.startsWith('/') ? apiPrefix : '/$apiPrefix';
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.https(workerHost, '$pfx$p', query);
  }

  /// (alte Schnittstelle) beliebige Textdatei laden
  Future<String> loadTextFile(String key) async {
    final res = await _http.get(_uri('/file', {'key': key}));
    if (res.statusCode != 200) {
      throw ApiException('loadTextFile failed',
          statusCode: res.statusCode, body: res.body);
    }
    return res.body;
  }

  /// (alte Schnittstelle) JSON laden
  Future<dynamic> loadJsonFile(String key) async {
    final raw = await loadTextFile(key);
    return jsonDecode(raw);
  }

  /// (alte Schnittstelle) Start-Curriculum laden (Liste von CurriculumEntry)
  ///
  /// allowDefaultFallback bleibt absichtlich als Named-Param erhalten, weil
  /// robulingo_app.dart / pick_manifest_service.dart das so aufrufen.
  Future<List<CurriculumEntry>> loadStartCurriculum(
    String fileName, {
    bool allowDefaultFallback = true,
    String? requireCompleteForLang, // kept for backward compatibility
  }) async {
    final data = await loadStartCurriculumJson(
      fileName,
      allowDefaultFallback: allowDefaultFallback,
    );

    final entriesDyn = _resolveEntryList(data);

    if (entriesDyn is List) {
      return _parseCurriculumEntries(entriesDyn);
    }

    // Fallback: leere Liste statt hard-crash (aber nur wenn allowDefaultFallback)
    if (allowDefaultFallback) return <CurriculumEntry>[];
    throw ApiException(
        'Unexpected start curriculum format: ${entriesDyn.runtimeType}');
  }

  /// (neu/alt kompatibel) Start-Curriculum-JSON (roh) laden
  Future<Map<String, dynamic>> loadStartCurriculumJson(
    String key, {
    bool allowDefaultFallback = true,
  }) async {
    try {
      final dyn = await loadJsonFile(key);
      if (dyn is Map<String, dynamic>) return dyn;
      // wenn es direkt eine Liste ist, packen wir sie in {entries: ...} damit obiger Code sauber läuft
      if (dyn is List) return <String, dynamic>{'entries': dyn};
      if (allowDefaultFallback) return <String, dynamic>{'entries': []};
      throw ApiException('Unexpected JSON type: ${dyn.runtimeType}');
    } catch (e) {
      if (allowDefaultFallback) return <String, dynamic>{'entries': []};
      rethrow;
    }
  }

  /// (alte Schnittstelle) Curriculum nach "lang" laden.
  ///
  /// In deinem Log gibt es ein /start-curriculum Endpoint, der offensichtlich
  /// "pick_*.json" materialisiert. Diese Methode nutzt das und bleibt kompatibel
  /// zu den Aufrufern, die `loadCurriculum(lang)` erwarten.
  Future<List<CurriculumEntry>> loadCurriculum(
    String lang, {
    bool requireCompleteForLang = false,
  }) async {
    final key = lang.endsWith('.json') ? lang : 'pick_${lang}.json';

    final res = await _http.get(_uri('/start-curriculum', {'key': key}));
    if (res.statusCode != 200) {
      throw ApiException('loadCurriculum failed',
          statusCode: res.statusCode, body: res.body);
    }

    final dyn = jsonDecode(res.body);
    final listDyn =
        (dyn is Map && dyn['entries'] != null) ? dyn['entries'] : dyn;

    if (listDyn is! List) {
      throw ApiException(
          'Unexpected curriculum format: ${listDyn.runtimeType}');
    }

    final out = _parseCurriculumEntries(listDyn);

    if (requireCompleteForLang) {
      return out;
    }

    return out;
  }

  /// Download binary file (image/audio).
  Future<Uint8List> loadBinaryFile(String key) async {
    final res = await _http.get(_uri('/file', {'key': key}));
    if (res.statusCode != 200) {
      throw ApiException('loadBinaryFile failed', statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }

  Future<Map<String, dynamic>> _fetchItemMeta(String uuid) async {
    final dyn = await loadJsonFile('$uuid.json');
    if (dyn is! Map<String, dynamic>) {
      throw ApiException('Unexpected item JSON');
    }
    return dyn;
  }

  Future<ItemData> loadItem(
    CurriculumEntry entry,
    String lang, {
    String? nativeLang,
  }) async {
    final meta = await _fetchItemMeta(entry.uuid);
    final manifest = _buildManifest(entry.uuid, meta);

    // Prefer canonical base image (UUID.webp) when present, so variants can be
    // cycled deterministically: UUID.webp, UUID_01.webp, UUID_02.webp, ...
    final canonicalBase = '${manifest.uuid}.webp';
    final imageKey = manifest.images.contains(canonicalBase)
        ? canonicalBase
        : _pickImageKeyForLang(manifest, lang, nativeLang: nativeLang);
    if (imageKey == null) {
      throw ApiException('Image key missing for ${entry.uuid}');
    }
    final orderedImageKeys = _orderedImageKeysForBase(manifest, imageKey);
    final imageBytes = await loadBinaryFile(orderedImageKeys.first);
    final imageVariants = <Uint8List>[imageBytes];
    for (final k in orderedImageKeys.skip(1)) {
      try {
        imageVariants.add(await loadBinaryFile(k));
      } catch (_) {
        // Optional variant missing/broken -> ignore.
      }
    }

    final audioKeys = _audioKeysForLang(manifest, lang);
    if (audioKeys.isEmpty) {
      throw ApiException('Audio missing ${entry.uuid} lang=$lang');
    }
    final audioVariants =
        audioKeys.map((k) => _uri('/file', {'key': k})).toList(growable: false);
    final audioUri = audioVariants.first;

    final String? phonetic = _phoneticForLang(meta, lang);
    final String text = _textForLang(meta, lang);
    String? nativeText;
    if (nativeLang != null && nativeLang != lang) {
      nativeText = _textForLang(meta, nativeLang);
    }

    int? position = entry.position;
    position ??= _parsePosition(meta['position']);

    final Map<String, List<String>> hintRefsByLang = {};
    final rawHintRefs = meta['hint_refs_by_lang'];
    if (rawHintRefs is Map) {
      rawHintRefs.forEach((key, value) {
        if (value is List) {
          final cleaned = value
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (cleaned.isNotEmpty) {
            hintRefsByLang[key.toString().toLowerCase()] = cleaned;
          }
        }
      });
    }

    return ItemData(
      uuid: entry.uuid,
      index: entry.index,
      position: position,
      text: text.isEmpty ? jsonEncode(meta) : text,
      nativeText: nativeText,
      phonetic: phonetic,
      hintRefsByLang: hintRefsByLang,
      imageBytes: imageBytes,
      imageVariants: imageVariants,
      audioUri: audioUri,
      audioVariants: audioVariants,
      imageSignature: _imageSignature(imageBytes),
    );
  }

  Future<ItemTexts> loadItemTexts(
    String uuid,
    String lang, {
    String? nativeLang,
  }) async {
    final meta = await _fetchItemMeta(uuid);
    final text = _textForLang(meta, lang);
    final native = nativeLang != null ? _textForLang(meta, nativeLang) : null;
    final phonetic = _phoneticForLang(meta, lang);
    final nativePhonetic =
        (nativeLang != null) ? _phoneticForLang(meta, nativeLang) : null;
    return ItemTexts(
      text: text,
      nativeText: native,
      phonetic: phonetic,
      nativePhonetic: nativePhonetic,
    );
  }

  Future<bool> hasAudioForLang(String uuid, String lang) async {
    final dyn = await _fetchItemMeta(uuid);
    final filenames = dyn['filenames'];
    if (filenames is! Map<String, dynamic>) return false;
    final manifest = _buildManifest(uuid, dyn);
    final keys = _audioKeysForLang(manifest, lang);
    if (keys.isEmpty) return false;
    for (final key in keys) {
      if (await audioUrlOk(_uri('/file', {'key': key}))) return true;
    }
    return false;
  }

  Future<bool> audioUrlOk(Uri uri) async {
    final key = uri.queryParameters['key'] ?? '';
    if (key.toLowerCase().endsWith('.mp3')) {
      try {
        final res = await _http.get(uri, headers: {'Range': 'bytes=0-1023'});
        if (res.statusCode != 200 && res.statusCode != 206) return false;
        if (_looksLikeMissingMp3Placeholder(res)) return false;
        return res.bodyBytes.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
    try {
      final res = await _http.head(uri);
      if (res.statusCode == 405) {
        final res2 = await _http.get(uri, headers: {'Range': 'bytes=0-0'});
        return res2.statusCode == 200 || res2.statusCode == 206;
      }
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  List<CurriculumEntry> _parseCurriculumEntries(List listDyn) {
    final out = <CurriculumEntry>[];

    for (var i = 0; i < listDyn.length; i++) {
      final it = listDyn[i];

      if (it is String) {
        // Modelle verlangen index -> i nehmen (deterministisch)
        out.add(CurriculumEntry(uuid: it, index: i.toString()));
        continue;
      }

      if (it is Map) {
        // bevorzugt: uuid / index / position
        final map = Map<String, dynamic>.from(it as Map);
        out.add(CurriculumEntry.fromJson(map, fallbackIndex: i));
        continue;
      }

      // Unbekanntes Element: ignorieren statt Crash
    }

    return out;
  }

  dynamic _resolveEntryList(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      if (data['entries'] is List) return data['entries'];
      if (data['item_order'] is List) return data['item_order'];
      if (data['items'] is List) return data['items'];
      if (data['manifest'] is Map && data['manifest']['items'] is List) {
        return data['manifest']['items'];
      }
      if (data['curriculum'] is Map && data['curriculum']['items'] is List) {
        return data['curriculum']['items'];
      }
    }
    return data;
  }

  int? _parsePosition(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _textForLang(Map<String, dynamic> meta, String lang) {
    final lower = lang.trim().toLowerCase();
    if (lower.isNotEmpty) {
      final display = meta['display_$lower'] ?? meta['text_$lower'];
      if (display is String && display.isNotEmpty) return display;
      final base = lower.split(RegExp(r'[-_]')).first;
      if (base.isNotEmpty && base != lower) {
        final displayBase = meta['display_$base'] ?? meta['text_$base'];
        if (displayBase is String && displayBase.isNotEmpty) return displayBase;
      }
    }
    final fallback = meta['text'];
    if (fallback is String && fallback.isNotEmpty) return fallback;
    return '';
  }

  String? _phoneticForLang(Map<String, dynamic> meta, String lang) {
    final lower = lang.trim().toLowerCase();
    if (lower.isEmpty) return null;
    for (final keyLang in <String>{
      lower,
      lower.split(RegExp(r'[-_]')).first,
    }) {
      if (keyLang.isEmpty) continue;
      final value = meta['phonetic_$keyLang'];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  _ItemManifest _buildManifest(String uuid, Map<String, dynamic> meta) {
    final filenames = meta['filenames'];
    final images = <String>{};
    String? defaultImageKey;
    final audio = <String, String>{};

    if (filenames is Map) {
      if (filenames['images'] is List) {
        for (final entry in filenames['images']) {
          if (entry is String && entry.isNotEmpty) {
            images.add(entry);
          }
        }
      }
      if (filenames['image'] is String) {
        defaultImageKey = filenames['image'] as String?;
      }
      final audioRaw = filenames['audio'];
      if (audioRaw is Map) {
        audioRaw.forEach((key, value) {
          if (value is String && value.isNotEmpty) {
            audio[key.toString().trim().toLowerCase()] = value;
          }
        });
      } else if (audioRaw is List) {
        for (final entry in audioRaw) {
          if (entry is! String) continue;
          final name = entry.trim();
          if (name.isEmpty) continue;
          final langKey = _audioLangKeyFromFilename(name);
          if (langKey != null) {
            audio[langKey] = name;
          }
          audio.putIfAbsent('default', () => name);
        }
      } else if (audioRaw is String && audioRaw.isNotEmpty) {
        audio['default'] = audioRaw;
      }
    }
    if (images.isEmpty && defaultImageKey != null) {
      images.add(defaultImageKey);
    }
    return _ItemManifest(
      uuid: uuid,
      images: images.toList(),
      defaultImageKey: defaultImageKey,
      audio: audio,
    );
  }

  String? _pickImageKeyForLang(
    _ItemManifest mf,
    String lang, {
    String? nativeLang,
  }) {
    final targetLang = nativeLang ?? lang;
    final normalized = targetLang.trim().toLowerCase();
    final caption = '${mf.uuid}_$normalized.webp';
    if (mf.images.contains(caption)) return caption;
    for (final image in mf.images) {
      if (image.toLowerCase().endsWith('_$normalized.webp')) return image;
    }
    return mf.defaultImageKey ??
        (mf.images.isNotEmpty ? mf.images.first : null);
  }

  List<String> _orderedImageKeysForBase(_ItemManifest mf, String baseKey) {
    final keys = <String>[];
    final seen = <String>{};
    void add(String k) {
      final trimmed = k.trim();
      if (trimmed.isEmpty) return;
      if (seen.add(trimmed)) keys.add(trimmed);
    }

    add(baseKey);

    final baseStem = baseKey.toLowerCase().endsWith('.webp')
        ? baseKey.substring(0, baseKey.length - 5)
        : baseKey;

    final variants = <MapEntry<int, String>>[];
    for (final img in mf.images) {
      if (!img.toLowerCase().endsWith('.webp')) continue;
      if (!img.startsWith('${baseStem}_')) continue;
      final suffix = img.substring(baseStem.length + 1, img.length - 5);
      final n = int.tryParse(suffix);
      if (n == null) continue;
      variants.add(MapEntry(n, img));
    }
    variants.sort((a, b) => a.key.compareTo(b.key));

    for (final v in variants) {
      add(v.value);
      if (keys.length >= _maxImageVariantsPerItem) break;
    }

    return keys;
  }

  List<String> _audioKeysForLang(_ItemManifest mf, String lang) {
    final normalized = lang.trim().toLowerCase();
    final candidates = <String>[];

    if (normalized.isNotEmpty) {
      final exact = mf.audio[normalized];
      if (exact?.isNotEmpty == true) candidates.add(exact!);

      final variants = mf.audio.entries
          .where(
              (e) => e.key.startsWith('${normalized}_') && e.value.isNotEmpty)
          .map((e) => MapEntry(e.key, e.value))
          .toList()
        ..sort((a, b) {
          final aMatch = RegExp(r'_(\d+)$').firstMatch(a.key);
          final bMatch = RegExp(r'_(\d+)$').firstMatch(b.key);
          final aNum =
              aMatch != null ? int.tryParse(aMatch.group(1) ?? '') : null;
          final bNum =
              bMatch != null ? int.tryParse(bMatch.group(1) ?? '') : null;
          if (aNum != null && bNum != null) return aNum.compareTo(bNum);
          return a.key.compareTo(b.key);
        });
      candidates.addAll(variants.map((e) => e.value));

      candidates.add('${mf.uuid}_$normalized.mp3');
    }

    final defaultKey = mf.audio['default'];
    if (defaultKey?.isNotEmpty == true) candidates.add(defaultKey!);

    candidates.add('${mf.uuid}.mp3');

    final seen = <String>{};
    return candidates
        .where((k) => k.isNotEmpty && seen.add(k))
        .toList(growable: false);
  }

  bool _looksLikeMissingMp3Placeholder(http.Response res) {
    int? expectedLength;
    final contentRange = res.headers['content-range'];
    if (contentRange != null) {
      final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
      if (match != null) expectedLength = int.tryParse(match.group(1) ?? '');
    }
    expectedLength ??= int.tryParse(res.headers['content-length'] ?? '');
    expectedLength ??= res.bodyBytes.length;
    if (expectedLength != _missingMp3PlaceholderLength) return false;

    final bytes = res.bodyBytes;
    if (bytes.length < _missingMp3PlaceholderHead16.length) return false;
    for (int i = 0; i < _missingMp3PlaceholderHead16.length; i++) {
      if (bytes[i] != _missingMp3PlaceholderHead16[i]) return false;
    }

    if (bytes.length >= 16 && bytes.length == expectedLength) {
      for (int i = bytes.length - 16; i < bytes.length; i++) {
        if (bytes[i] != 0xAA) return false;
      }
    }
    return true;
  }

  String? _audioLangKeyFromFilename(String filename) {
    final match =
        RegExp(r'_([a-z]{2,3})(?:_(\d+))?\.mp3$', caseSensitive: false)
            .firstMatch(filename.trim());
    if (match == null) return null;
    final lang = match.group(1);
    if (lang == null || lang.isEmpty) return null;
    final variant = match.group(2);
    if (variant == null || variant.isEmpty) return lang.toLowerCase();
    return '${lang.toLowerCase()}_$variant';
  }

  String _imageSignature(Uint8List bytes) {
    final len = bytes.length;
    final sample = bytes.length >= 12 ? bytes.sublist(0, 12) : bytes;
    int hash = 0;
    for (final b in sample) {
      hash = (hash * 31 + b) & 0x7fffffff;
    }
    return '$len-$hash';
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  ApiException(this.message, {this.statusCode, this.body});

  @override
  String toString() => 'ApiException($message, status=$statusCode)';
}

class _ItemManifest {
  final String uuid;
  final List<String> images;
  final String? defaultImageKey;
  final Map<String, String> audio;

  const _ItemManifest({
    required this.uuid,
    required this.images,
    required this.defaultImageKey,
    required this.audio,
  });
}
