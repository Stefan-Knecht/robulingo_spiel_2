// ------------------------------------------------------------
// Ziel (Laien): Pseudonyme User-ID pro Gerät erzeugen und persistieren.
// Verbindung: robulingo_app.dart nutzt sie für Logs/Curriculum-Delta; EventLogger hängt sie an.
// Tücken: Nur lokal gespeichert; bei App-Neuinstallation entsteht eine neue ID.
// ------------------------------------------------------------
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// Erzeugt/liest eine stabile pseudonyme User-ID, die auf dem Gerät persistiert.
class UserIdentity {
  static const _fileName = 'user_id.txt';

  Future<String> loadOrCreate() async {
    final file = await _file();
    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) return existing;
    }
    final id = _generateId();
    await file.writeAsString(id);
    return id;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');
    await file.parent.create(recursive: true);
    return file;
  }

  String _generateId() {
    Random rand;
    try {
      rand = Random.secure();
    } catch (_) {
      rand = Random();
    }
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final StringBuffer sb = StringBuffer('u');
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
