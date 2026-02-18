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
      final fromStorage = (getWebStorageValue(_cookieName) ?? '').trim();
      if (fromStorage.isNotEmpty) {
        setCookieValue(_cookieName, fromStorage, maxAgeDays: 3650);
        return fromStorage;
      }
      final id = _generateId();
      setCookieValue(_cookieName, id, maxAgeDays: 3650);
      setWebStorageValue(_cookieName, id);
      return id;
    }
    try {
      final file = await _file();
      if (await file.exists()) {
        final existing = (await file.readAsString()).trim();
        if (existing.isNotEmpty) return existing;
      }
      final id = _generateId();
      await file.writeAsString(id);
      return id;
    } catch (e) {
      debugPrint('[user-identity][loadOrCreate][fallback] $e');
      return _generateId();
    }
  }

  Future<void> save(String id) async {
    final cleaned = id.trim();
    if (cleaned.isEmpty) return;
    if (kIsWeb) {
      setCookieValue(_cookieName, cleaned, maxAgeDays: 3650);
      setWebStorageValue(_cookieName, cleaned);
      return;
    }
    try {
      final file = await _file();
      await file.writeAsString(cleaned);
    } catch (e) {
      debugPrint('[user-identity][save][fallback] $e');
    }
  }

  Future<void> clear() async {
    if (kIsWeb) {
      setCookieValue(_cookieName, '', maxAgeDays: 0);
      clearWebStorageValue(_cookieName);
      return;
    }
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[user-identity][clear][fallback] $e');
    }
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
