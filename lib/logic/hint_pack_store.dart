// ------------------------------------------------------------
// Ziel (Laien): Hint-Packs lokal cachen, damit die App offline weiterlaeuft.
// Verbindung: HintsService liest/schreibt Cache-Dateien pro Sprachpaar.
// Tuecken: Versions-Tag pruefen, sonst Cache loeschen.
// ------------------------------------------------------------
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/hint_models.dart';

const int _hintCacheVersion = 2;

class HintPackStore {
  Future<File> _file(String l1, String l2) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeL1 = l1.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final safeL2 = l2.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final fileName = 'hint_pack_${safeL1}_${safeL2}.json';
    final f = File('${dir.path}/$fileName');
    await f.parent.create(recursive: true);
    return f;
  }

  Future<HintPack?> load(String l1, String l2) async {
    try {
      final f = await _file(l1, l2);
      if (!await f.exists()) return null;
      final txt = await f.readAsString();
      final data = jsonDecode(txt) as Map<String, dynamic>;
      final rawVersion = data['version'];
      final int version = rawVersion is int
          ? rawVersion
          : (rawVersion is num
              ? rawVersion.toInt()
              : int.tryParse(rawVersion?.toString() ?? '') ?? 0);
      if (version != _hintCacheVersion) {
        await clear(l1, l2);
        return null;
      }
      final hintsRaw = data['hints'] as Map<String, dynamic>? ?? {};
      final Map<String, HintContent> hints = {};
      hintsRaw.forEach((key, value) {
        if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          map['id'] ??= key;
          final hint = HintContent.fromJson(map);
          if (!hint.isEmpty) hints[key] = hint;
        }
      });
      final fetchedAtMs = data['fetchedAtMs'] as int? ?? 0;
      return HintPack(
        l1: data['l1']?.toString() ?? l1,
        l2: data['l2']?.toString() ?? l2,
        hints: hints,
        fetchedAtMs: fetchedAtMs,
        packVersion: data['packVersion']?.toString(),
        etag: data['etag']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(HintPack pack) async {
    try {
      final f = await _file(pack.l1, pack.l2);
      final data = <String, dynamic>{
        'version': _hintCacheVersion,
        'l1': pack.l1,
        'l2': pack.l2,
        if (pack.packVersion != null) 'packVersion': pack.packVersion,
        if (pack.etag != null) 'etag': pack.etag,
        'fetchedAtMs': pack.fetchedAtMs,
        'hints': pack.hints.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };
      await f.writeAsString(jsonEncode(data));
    } catch (_) {
      // ignore
    }
  }

  Future<void> clear(String l1, String l2) async {
    try {
      final f = await _file(l1, l2);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // ignore
    }
  }
}
