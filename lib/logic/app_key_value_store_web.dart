// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

final Map<String, String> _fallbackValues = <String, String>{};

class AppKeyValueStore {
  String? getString(String key) {
    try {
      return html.window.localStorage[key] ?? _fallbackValues[key];
    } catch (_) {
      return _fallbackValues[key];
    }
  }

  int? getInt(String key) => int.tryParse(getString(key) ?? '');

  Future<void> setString(String key, String value) async {
    _fallbackValues[key] = value;
    try {
      html.window.localStorage[key] = value;
    } catch (_) {}
  }

  Future<void> setInt(String key, int value) async {
    await setString(key, value.toString());
  }

  Future<void> remove(String key) async {
    _fallbackValues.remove(key);
    try {
      html.window.localStorage.remove(key);
    } catch (_) {}
  }
}

Future<AppKeyValueStore?> openAppKeyValueStore(
  String owner,
  String operation,
) async =>
    AppKeyValueStore();
