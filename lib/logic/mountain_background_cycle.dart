import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:shared_preferences/shared_preferences.dart';

const List<String> kMountainThemeOrder = <String>[
  'default',
  'summer',
  'snow',
  'night',
];

String mountainDayKey(DateTime date) {
  final d = date.toLocal();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

class MountainThemeCycleSnapshot {
  const MountainThemeCycleSnapshot({
    required this.dayKey,
    required this.themeIndex,
  });

  final String dayKey;
  final int themeIndex;
}

class MountainThemeCycleStore {
  static const String _dayStorageKey = 'robulingo_mountain_theme_day';
  static const String _indexStorageKey = 'robulingo_mountain_theme_index';
  static String? _fallbackDayKey;
  static int _fallbackThemeIndex = 0;

  Future<SharedPreferences?> _tryGetPrefs() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('[mountain-theme][prefs-unavailable] $error');
      debugPrint('[mountain-theme][stack] $stackTrace');
      return null;
    } catch (error, stackTrace) {
      debugPrint('[mountain-theme][prefs-error] $error');
      debugPrint('[mountain-theme][stack] $stackTrace');
      return null;
    }
  }

  Future<MountainThemeCycleSnapshot> loadForToday({DateTime? now}) async {
    final todayKey = mountainDayKey(now ?? DateTime.now());
    final prefs = await _tryGetPrefs();
    if (prefs == null) {
      if (_fallbackDayKey != todayKey) {
        _fallbackDayKey = todayKey;
        _fallbackThemeIndex = 0;
      }
      _fallbackThemeIndex = _normalizeThemeIndex(_fallbackThemeIndex);
      return MountainThemeCycleSnapshot(
        dayKey: todayKey,
        themeIndex: _fallbackThemeIndex,
      );
    }
    final storedDay = prefs.getString(_dayStorageKey);
    if (storedDay != todayKey) {
      await prefs.setString(_dayStorageKey, todayKey);
      await prefs.setInt(_indexStorageKey, 0);
      return MountainThemeCycleSnapshot(dayKey: todayKey, themeIndex: 0);
    }
    final raw = prefs.getInt(_indexStorageKey) ?? 0;
    final normalized = _normalizeThemeIndex(raw);
    if (raw != normalized) {
      await prefs.setInt(_indexStorageKey, normalized);
    }
    return MountainThemeCycleSnapshot(
      dayKey: todayKey,
      themeIndex: normalized,
    );
  }

  Future<void> saveForToday({
    required String dayKey,
    required int themeIndex,
  }) async {
    final normalized = _normalizeThemeIndex(themeIndex);
    final prefs = await _tryGetPrefs();
    if (prefs == null) {
      _fallbackDayKey = dayKey;
      _fallbackThemeIndex = normalized;
      return;
    }
    await prefs.setString(_dayStorageKey, dayKey);
    await prefs.setInt(_indexStorageKey, normalized);
  }

  int _normalizeThemeIndex(int index) {
    if (kMountainThemeOrder.isEmpty) return 0;
    final mod = index % kMountainThemeOrder.length;
    return mod < 0 ? mod + kMountainThemeOrder.length : mod;
  }
}
