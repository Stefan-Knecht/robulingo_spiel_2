// ------------------------------------------------------------
// Ziel (Laien): Kleines Cache-Fenster der aktuellen Session speichern (Items + Index).
// Verbindung: robulingo_app.dart legt/liest `session_cache.json`, um eine Sitzung schnell fortzusetzen.
// Tücken: Speichert nur einen Ausschnitt (cachedItemCount); Audio-URIs müssen weiterhin erreichbar sein.
// ------------------------------------------------------------
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

const int _sessionCacheVersion = 1;

class CachedItem {
  final String uuid;
  final String index;
  final int? position;
  final String text;
  final String? nativeText;
  final String? phonetic;
  final String imageSignature;
  final String audioUri;
  final List<String> audioVariants;
  final Uint8List imageBytes;
  final List<Uint8List> imageVariants;

  CachedItem({
    required this.uuid,
    required this.index,
    this.position,
    required this.text,
    this.nativeText,
    this.phonetic,
    required this.imageSignature,
    required this.audioUri,
    required this.audioVariants,
    required this.imageBytes,
    required this.imageVariants,
  });

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'index': index,
        if (position != null) 'position': position,
        'text': text,
        if (nativeText != null) 'nativeText': nativeText,
        if (phonetic != null) 'phonetic': phonetic,
        'imageSignature': imageSignature,
        'audioUri': audioUri,
        'audioVariants': audioVariants,
        'image': base64Encode(imageBytes),
        'variants': imageVariants.map(base64Encode).toList(),
      };

  factory CachedItem.fromJson(Map<String, dynamic> json) {
    final baseAudioUri = json['audioUri'] as String;
    final rawVariants = (json['audioVariants'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList();
    final normalizedVariants =
        rawVariants.isNotEmpty ? rawVariants : [baseAudioUri];
    final rawPosition = json['position'];
    int? position;
    if (rawPosition is int) {
      position = rawPosition;
    } else if (rawPosition is num) {
      position = rawPosition.toInt();
    } else if (rawPosition is String) {
      position = int.tryParse(rawPosition);
    }
    return CachedItem(
      uuid: json['uuid'] as String,
      index: json['index'] as String,
      position: position,
      text: json['text'] as String,
      nativeText: json['nativeText'] as String?,
      phonetic: json['phonetic'] as String?,
      imageSignature: json['imageSignature'] as String,
      audioUri: baseAudioUri,
      audioVariants: normalizedVariants,
      imageBytes: base64Decode(json['image'] as String),
      imageVariants: (json['variants'] as List<dynamic>? ?? [])
          .map((e) => base64Decode(e as String))
          .toList(),
    );
  }
}

class SessionCache {
  final int version;
  final String lang;
  final String startKey;
  final String? nativeLang;
  final int lastIndex;
  final List<CachedItem> items;
  SessionCache({
    this.version = _sessionCacheVersion,
    required this.lang,
    required this.startKey,
    required this.nativeLang,
    required this.lastIndex,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'lang': lang,
        'startKey': startKey,
        if (nativeLang != null) 'nativeLang': nativeLang,
        'lastIndex': lastIndex,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory SessionCache.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['version'];
    int version;
    if (rawVersion is int) {
      version = rawVersion;
    } else if (rawVersion is num) {
      version = rawVersion.toInt();
    } else if (rawVersion is String) {
      version = int.tryParse(rawVersion) ?? 0;
    } else {
      version = 0;
    }
    return SessionCache(
      version: version,
      lang: json['lang'] as String,
      startKey: json['startKey'] as String,
      nativeLang: json['nativeLang'] as String?,
      lastIndex: json['lastIndex'] as int,
      items: (json['items'] as List<dynamic>)
          .map((e) => CachedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SessionCacheStore {
  static const _fileName = 'session_cache.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$_fileName');
    await f.parent.create(recursive: true);
    return f;
  }

  Future<void> save(SessionCache cache) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(cache.toJson()));
    } catch (_) {
      // ignore
    }
  }

  Future<SessionCache?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final txt = await f.readAsString();
      final data = jsonDecode(txt) as Map<String, dynamic>;
      final rawVersion = data['version'];
      final int version = rawVersion is int
          ? rawVersion
          : (rawVersion is num
              ? rawVersion.toInt()
              : int.tryParse(rawVersion?.toString() ?? '') ?? 0);
      if (version != _sessionCacheVersion) {
        await clear();
        return null;
      }
      return SessionCache.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // ignore
    }
  }
}
