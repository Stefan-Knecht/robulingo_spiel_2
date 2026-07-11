import 'package:robulingo_flutter/logic/app_key_value_store.dart';

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

  Future<MountainThemeCycleSnapshot> loadForToday({DateTime? now}) async {
    final todayKey = mountainDayKey(now ?? DateTime.now());
    final store = await openAppKeyValueStore('mountain-theme', 'load');
    if (store == null) {
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
    final storedDay = store.getString(_dayStorageKey);
    if (storedDay != todayKey) {
      await store.setString(_dayStorageKey, todayKey);
      await store.setInt(_indexStorageKey, 0);
      return MountainThemeCycleSnapshot(dayKey: todayKey, themeIndex: 0);
    }
    final raw = store.getInt(_indexStorageKey) ?? 0;
    final normalized = _normalizeThemeIndex(raw);
    if (raw != normalized) {
      await store.setInt(_indexStorageKey, normalized);
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
    final store = await openAppKeyValueStore('mountain-theme', 'save');
    if (store == null) {
      _fallbackDayKey = dayKey;
      _fallbackThemeIndex = normalized;
      return;
    }
    await store.setString(_dayStorageKey, dayKey);
    await store.setInt(_indexStorageKey, normalized);
  }

  int _normalizeThemeIndex(int index) {
    if (kMountainThemeOrder.isEmpty) return 0;
    final mod = index % kMountainThemeOrder.length;
    return mod < 0 ? mod + kMountainThemeOrder.length : mod;
  }
}
