import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:robulingo_flutter/util/download_text.dart';
import 'package:robulingo_flutter/util/write_text_file.dart';

class _CompEntry {
  _CompEntry({required this.label, required this.correct});
  final String label;
  final bool correct;
}

class _NamingEntry {
  _NamingEntry({required this.label, required this.heard, required this.correct});
  final String label;
  final String heard;
  final bool correct;
}

/// Human-readable protocol to track item presentation policy outcomes.
///
/// Format (example):
/// Datum: 27.01.2026; Uhrzeit: 10:15:30
///
/// Comprehension targets:
/// - Wasser: r
/// - Brot: f
///
/// Naming targets:
/// - Wasser: "vaser" - Wasser: r
///
/// Notes:
/// - Labels are written in the currently selected L2 (we pass `trial.target.text`).
/// - On web, "overwrite" uses the File System Access API when available.
class PresentationProtocolLog {
  DateTime? _sessionStartLocal;
  String _userId = 'unknown';

  final List<_CompEntry> _comprehension = <_CompEntry>[];
  final List<_NamingEntry> _naming = <_NamingEntry>[];
  bool _dirty = false;

  Future<void> startSession(DateTime sessionStartUtc, {String? userId}) async {
    _sessionStartLocal = sessionStartUtc.toLocal();
    _userId = _sanitizeUserId(userId ?? _userId);
    _comprehension.clear();
    _naming.clear();
    _dirty = true;
  }

  Future<void> setUserId(String? userId) async {
    final next = _sanitizeUserId(userId ?? 'unknown');
    if (next == _userId) return;
    _userId = next;
    _dirty = true;
  }

  void addComprehension({required String label, required bool correct}) {
    _comprehension.add(_CompEntry(label: label, correct: correct));
    _dirty = true;
  }

  void addNaming({
    required String label,
    required String heard,
    required bool correct,
  }) {
    _naming.add(_NamingEntry(label: label, heard: heard, correct: correct));
    _dirty = true;
  }

  String _sanitizeUserId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'unknown';
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _fmt2(int v) => v < 10 ? '0$v' : '$v';

  String _formatHeader(DateTime ts) {
    final d = '${_fmt2(ts.day)}.${_fmt2(ts.month)}.${ts.year}';
    final t = '${_fmt2(ts.hour)}:${_fmt2(ts.minute)}:${_fmt2(ts.second)}';
    return 'Datum: $d; Uhrzeit: $t';
  }

  String buildText() {
    final start = _sessionStartLocal ?? DateTime.now();
    final buf = StringBuffer();
    buf.writeln(_formatHeader(start));
    buf.writeln();
    buf.writeln('Comprehension targets:');
    for (final e in _comprehension) {
      final label = e.label.trim().isNotEmpty ? e.label.trim() : '—';
      buf.writeln('- $label: ${e.correct ? 'r' : 'f'}');
    }
    buf.writeln();
    buf.writeln('Naming targets:');
    for (final e in _naming) {
      final label = e.label.trim().isNotEmpty ? e.label.trim() : '—';
      final heard = e.heard.replaceAll('\n', ' ').trim();
      buf.writeln('- $label: "$heard" - $label: ${e.correct ? 'r' : 'f'}');
    }
    return buf.toString();
  }

  Future<String> export() async {
    if (!_dirty && _comprehension.isEmpty && _naming.isEmpty) {
      return 'Protokoll ist leer.';
    }
    final content = buildText();
    final fileName = 'audio_target_matches_json_by_user__$_userId.txt';

    if (kIsWeb) {
      await downloadTextFile(filename: fileName, contents: content);
      _dirty = false;
      return 'Download gestartet: $fileName';
    }

    // Desktop/mobile: best-effort downloads dir, fallback to app docs.
    try {
      final dl = await getDownloadsDirectory();
      if (dl != null) {
        await writeTextFile('${dl.path}/$fileName', content);
        _dirty = false;
        return 'Gespeichert: ${dl.path}/$fileName';
      }
    } catch (_) {
      // ignore
    }

    final dir = await getApplicationDocumentsDirectory();
    await writeTextFile('${dir.path}/$fileName', content);
    _dirty = false;
    return 'Gespeichert: ${dir.path}/$fileName';
  }
}

