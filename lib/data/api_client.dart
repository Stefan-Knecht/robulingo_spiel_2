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

    final imageKey =
        _pickImageKeyForLang(manifest, lang, nativeLang: nativeLang);
    if (imageKey == null) {
      throw ApiException('Image key missing for ${entry.uuid}');
    }
    final imageBytes = await loadBinaryFile(imageKey);

    final imageVariants = <Uint8List>[imageBytes];

    final audioKey = _requiredL2AudioKey(manifest, lang);
    if (audioKey == null || audioKey.isEmpty) {
      throw ApiException('Audio missing ${entry.uuid} lang=$lang');
    }
    final audioUri = _uri('/file', {'key': audioKey});
    final audioVariants = <Uri>[audioUri];

    final String? phonetic = meta['phonetic_$lang']?.toString();
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
    return _audioKeyForLang(manifest, lang) != null;
  }

  Future<bool> audioUrlOk(Uri uri) async {
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
    final display = meta['display_$lower'] ?? meta['text_$lower'];
    if (display is String && display.isNotEmpty) return display;
    final fallback = meta['text'];
    if (fallback is String && fallback.isNotEmpty) return fallback;
    return '';
  }

  String? _phoneticForLang(Map<String, dynamic> meta, String lang) {
    final lower = lang.trim().toLowerCase();
    if (lower.isEmpty) return null;
    final value = meta['phonetic_$lower'];
    if (value is String && value.isNotEmpty) {
      return value;
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

  String? _requiredL2AudioKey(_ItemManifest mf, String lang) {
    return _audioKeyForLang(mf, lang);
  }

  String? _audioKeyForLang(_ItemManifest mf, String lang) {
    final normalized = lang.trim().toLowerCase();
    if (normalized.isNotEmpty) {
      final specific = mf.audio[normalized];
      if (specific?.isNotEmpty == true) {
        return specific;
      }
      return '${mf.uuid}_$normalized.mp3';
    }
    final defaultKey = mf.audio['default'];
    if (defaultKey?.isNotEmpty == true) {
      return defaultKey;
    }
    return null;
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
