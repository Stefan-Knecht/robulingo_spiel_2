import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:shared_preferences/shared_preferences.dart';

class AppKeyValueStore {
  AppKeyValueStore(this._prefs);

  final SharedPreferences _prefs;

  String? getString(String key) => _prefs.getString(key);

  int? getInt(String key) => _prefs.getInt(key);

  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}

Future<AppKeyValueStore?> openAppKeyValueStore(
  String owner,
  String operation,
) async {
  try {
    return AppKeyValueStore(await SharedPreferences.getInstance());
  } on MissingPluginException catch (error, stackTrace) {
    debugPrint('[$owner][$operation][prefs-unavailable] $error');
    debugPrint('[$owner][$operation][stack] $stackTrace');
    return null;
  } catch (error, stackTrace) {
    debugPrint('[$owner][$operation][prefs-error] $error');
    debugPrint('[$owner][$operation][stack] $stackTrace');
    return null;
  }
}
