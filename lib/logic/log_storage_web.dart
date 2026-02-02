// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class LogStorage {
  static const String _key = 'robulingo_events_ndjson';

  Future<void> init() async {}

  Future<void> appendLine(String line) async {
    final cleaned = line.trimRight();
    if (cleaned.isEmpty) return;
    final existing = html.window.localStorage[_key];
    if (existing == null || existing.isEmpty) {
      html.window.localStorage[_key] = cleaned;
      return;
    }
    final next = '$existing\n$cleaned';
    try {
      html.window.localStorage[_key] = next;
    } catch (_) {
      final parts = existing.split('\n');
      if (parts.length <= 1) {
        html.window.localStorage[_key] = cleaned;
        return;
      }
      final start = (parts.length / 2).floor();
      final trimmed = parts.sublist(start).join('\n');
      final fallback = trimmed.isEmpty ? cleaned : '$trimmed\n$cleaned';
      html.window.localStorage[_key] = fallback;
    }
  }

  Future<List<String>> readLines() async {
    final raw = html.window.localStorage[_key];
    if (raw == null || raw.isEmpty) return <String>[];
    return raw
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
  }

  Future<bool> exists() async {
    final raw = html.window.localStorage[_key];
    return raw != null && raw.trim().isNotEmpty;
  }

  Future<void> clear() async {
    html.window.localStorage.remove(_key);
  }
}
