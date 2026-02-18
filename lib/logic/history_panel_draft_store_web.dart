// ignore_for_file: deprecated_member_use

import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'history_panel_draft_data.dart';

class HistoryPanelDraftStore {
  static const String _storageKey = 'robulingo_history_panel_draft';
  static const String _entriesKey = 'entriesByUser';
  static const String _defaultKey = '__default__';

  String _keyForUser(String? userId) {
    final cleaned = (userId ?? '').trim();
    return cleaned.isEmpty ? _defaultKey : cleaned;
  }

  HistoryPanelDraftData? _entryFromRaw(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return HistoryPanelDraftData.fromJson(raw);
    }
    if (raw is Map) {
      return HistoryPanelDraftData.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  HistoryPanelDraftData? _entryForKey(Map<dynamic, dynamic> entries, String key) {
    return _entryFromRaw(entries[key]);
  }

  bool _matchesUserOrLegacyDefault(HistoryPanelDraftData data, String key) {
    final ref = data.progressReference.trim();
    if (ref.isEmpty) return true;
    return ref == key;
  }

  HistoryPanelDraftData? _entryByProgressReference(
    Map<dynamic, dynamic> entries,
    String key,
  ) {
    if (key == _defaultKey) return null;
    for (final raw in entries.values) {
      final data = _entryFromRaw(raw);
      if (data == null) continue;
      if (data.progressReference.trim() == key) return data;
    }
    return null;
  }

  Future<Map<String, dynamic>> _readRawMap() async {
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Future<HistoryPanelDraftData?> load({String? userId}) async {
    try {
      final root = await _readRawMap();
      final key = _keyForUser(userId);
      final entries = root[_entriesKey];
      if (entries is Map<String, dynamic>) {
        final exact = _entryForKey(entries, key);
        if (exact != null) return exact;
        if (key != _defaultKey) {
          final fallback = _entryForKey(entries, _defaultKey);
          if (fallback != null && _matchesUserOrLegacyDefault(fallback, key)) {
            return fallback;
          }
          final byReference = _entryByProgressReference(entries, key);
          if (byReference != null) return byReference;
        }
      } else if (entries is Map) {
        final exact = _entryForKey(entries, key);
        if (exact != null) return exact;
        if (key != _defaultKey) {
          final fallback = _entryForKey(entries, _defaultKey);
          if (fallback != null && _matchesUserOrLegacyDefault(fallback, key)) {
            return fallback;
          }
          final byReference = _entryByProgressReference(entries, key);
          if (byReference != null) return byReference;
        }
      }

      // Backward compatibility: old single-entry payload.
      if (root.containsKey('supervisorEmail') || root.containsKey('progressReference')) {
        return HistoryPanelDraftData.fromJson(root);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(HistoryPanelDraftData data, {String? userId}) async {
    try {
      final key = _keyForUser(userId);
      final root = await _readRawMap();
      final entriesRaw = root[_entriesKey];
      final entries = entriesRaw is Map
          ? Map<String, dynamic>.from(entriesRaw)
          : <String, dynamic>{};
      entries[key] = data.toJson();
      root[_entriesKey] = entries;
      html.window.localStorage[_storageKey] = jsonEncode(root);
    } catch (_) {
      // ignore
    }
  }

  Future<void> clear({String? userId}) async {
    if ((userId ?? '').trim().isEmpty) {
      html.window.localStorage.remove(_storageKey);
      return;
    }
    try {
      final root = await _readRawMap();
      final entriesRaw = root[_entriesKey];
      if (entriesRaw is! Map) return;
      final entries = Map<String, dynamic>.from(entriesRaw);
      entries.remove(_keyForUser(userId));
      if (entries.isEmpty) {
        html.window.localStorage.remove(_storageKey);
        return;
      }
      root[_entriesKey] = entries;
      html.window.localStorage[_storageKey] = jsonEncode(root);
    } catch (_) {
      // ignore
    }
  }
}
