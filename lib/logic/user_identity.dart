// ------------------------------------------------------------
// Ziel (Laien): Pseudonyme User-ID pro Gerät erzeugen und persistieren.
// Verbindung: robulingo_app.dart nutzt sie für Logs/Curriculum-Delta; EventLogger hängt sie an.
// Tücken: Nur lokal gespeichert; bei App-Neuinstallation entsteht eine neue ID.
// ------------------------------------------------------------
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../util/web_cookies_stub.dart'
    if (dart.library.html) '../util/web_cookies.dart';

/// Erzeugt/liest eine stabile pseudonyme User-ID, die auf dem Gerät persistiert.
class UserIdentity {
  static const _fileName = 'user_id.txt';
  static const _cookieName = 'robulingo_user_id';

  Future<String> loadOrCreate() async {
    if (kIsWeb) {
      final existing = (getCookieValue(_cookieName) ?? '').trim();
      if (existing.isNotEmpty) return existing;
      final id = _generateId();
      setCookieValue(_cookieName, id, maxAgeDays: 3650);
      return id;
    }
    final file = await _file();
    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) return existing;
    }
    final id = _generateId();
    await file.writeAsString(id);
    return id;
  }

  Future<void> save(String id) async {
    final cleaned = id.trim();
    if (cleaned.isEmpty) return;
    if (kIsWeb) {
      setCookieValue(_cookieName, cleaned, maxAgeDays: 3650);
      return;
    }
    final file = await _file();
    await file.writeAsString(cleaned);
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
