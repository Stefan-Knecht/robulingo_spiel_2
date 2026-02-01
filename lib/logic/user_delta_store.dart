// ------------------------------------------------------------
// Ziel (Laien): Lokale Sicherung des Curriculum-Deltas je User, falls Cloud-Push/Pull scheitert.
// Verbindung: robulingo_app.dart liest zuerst Cloud (`UserCurriculumService`), fällt auf diesen Store zurück.
// Tücken: Datei pro User-ID; ohne Persist verliert man den Cursor nach App-Löschung.
// ------------------------------------------------------------
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/user_curriculum_delta.dart';

/// Lokale Kopie des User-Curriculum-Deltas, falls kein Cloud-Zugriff möglich ist.
class UserDeltaStore {
  Future<File> _file(String userId) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/user_delta_$userId.json');
    await file.parent.create(recursive: true);
    return file;
  }

  Future<UserCurriculumDelta?> load(String userId) async {
    try {
      final f = await _file(userId);
      if (!await f.exists()) return null;
      final txt = await f.readAsString();
      return tryParseDelta(jsonDecode(txt) as Map<String, dynamic>?);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String userId, UserCurriculumDelta delta) async {
    try {
      final f = await _file(userId);
      await f.writeAsString(jsonEncode(delta.toJson()));
    } catch (_) {
      // ignore
    }
  }

  Future<void> delete(String userId) async {
    try {
      final f = await _file(userId);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // ignore
    }
  }
}
