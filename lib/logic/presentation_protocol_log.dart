import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:robulingo_flutter/util/download_text.dart';
import 'package:robulingo_flutter/util/write_text_file.dart';

class _TimelineEntry {
  _TimelineEntry.comprehension({
    required this.ts,
    required this.label,
    this.nativeLabel,
    required this.correct,
    this.phonetic,
  })  : kind = 'C',
        heard = null,
        note = null;

  _TimelineEntry.naming({
    required this.ts,
    required this.label,
    this.nativeLabel,
    required this.heard,
    required this.correct,
    this.phonetic,
  })  : kind = 'N',
        note = null;

  _TimelineEntry.note({
    required this.ts,
    required this.note,
  })  : kind = 'Note',
        label = '',
        nativeLabel = null,
        phonetic = null,
        correct = null,
        heard = null;

  final DateTime ts;
  final String kind; // C | N | Note
  final String label;
  final String? nativeLabel;
  final String? phonetic;
  final bool? correct;
  final String? heard;
  final String? note;
}

/// Human-readable protocol to track item presentation policy outcomes.
///
/// Format (example):
/// Datum: 28.01.2026; Uhrzeit: 14:46:45
///
/// Timeline:
/// - 14:47:03 C Water: r
/// - 14:48:21 Note: ASR locale (naming): ...
/// - 14:48:26 N Water: "" - Water: f
class PresentationProtocolLog {
  DateTime? _sessionStartLocal;
  String _userId = 'unknown';
  String _nativeLang = '';

  final List<_TimelineEntry> _timeline = <_TimelineEntry>[];
  bool _dirty = false;
  String? _cursorLine;

  Future<void> startSession(
    DateTime sessionStartUtc, {
    String? userId,
    String? nativeLang,
  }) async {
    _sessionStartLocal = sessionStartUtc.toLocal();
    _userId = _sanitizeUserId(userId ?? _userId);
    _nativeLang = _sanitizeLang(nativeLang ?? _nativeLang);
    _timeline.clear();
    _dirty = true;
  }

  Future<void> setUserId(String? userId) async {
    final next = _sanitizeUserId(userId ?? 'unknown');
    if (next == _userId) return;
    _userId = next;
    _dirty = true;
  }

  void setSessionContext({String? nativeLang}) {
    final nextNative = _sanitizeLang(nativeLang ?? _nativeLang);
    if (nextNative == _nativeLang) return;
    _nativeLang = nextNative;
    _dirty = true;
  }

  void addComprehension({
    required String label,
    String? nativeLabel,
    String? phonetic,
    required bool correct,
  }) {
    _timeline.add(_TimelineEntry.comprehension(
      ts: DateTime.now(),
      label: label,
      nativeLabel: nativeLabel,
      phonetic: phonetic,
      correct: correct,
    ));
    _dirty = true;
  }

  void addNaming({
    required String label,
    String? nativeLabel,
    String? phonetic,
    required String heard,
    required bool correct,
  }) {
    _timeline.add(_TimelineEntry.naming(
      ts: DateTime.now(),
      label: label,
      nativeLabel: nativeLabel,
      phonetic: phonetic,
      heard: heard,
      correct: correct,
    ));
    _dirty = true;
  }

  void addNote(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    if (cleaned.startsWith('Cursor:')) {
      _cursorLine = cleaned;
      _dirty = true;
      return;
    }
    _timeline.add(_TimelineEntry.note(ts: DateTime.now(), note: cleaned));
    _dirty = true;
  }

  String _sanitizeUserId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'unknown';
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _sanitizeLang(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _fmt2(int v) => v < 10 ? '0$v' : '$v';

  String _formatDateLine(DateTime ts) {
    final d = '${_fmt2(ts.day)}.${_fmt2(ts.month)}.${ts.year}';
    final t = '${_fmt2(ts.hour)}:${_fmt2(ts.minute)}:${_fmt2(ts.second)}';
    return 'Datum: $d; Uhrzeit: $t';
  }

  String _formatTime(DateTime ts) {
    final local = ts.toLocal();
    return '${_fmt2(local.hour)}:${_fmt2(local.minute)}:${_fmt2(local.second)}';
  }

  bool _containsNonLatinScript(String s) {
    for (final rune in s.runes) {
      // Allow common ASCII control/punctuation/digits/spaces.
      if (rune <= 0x0040) continue;

      // Treat Latin letters (including common diacritics) as "Latin".
      if (rune >= 0x0041 && rune <= 0x024F) continue; // Latin + Extended
      if (rune >= 0x1E00 && rune <= 0x1EFF) continue; // Latin Extended Additional
      if (rune >= 0x0300 && rune <= 0x036F) continue; // Combining Diacritics

      // General punctuation etc. shouldn't trigger "non-latin script" labeling.
      if (rune >= 0x2000 && rune <= 0x206F) continue;

      // Non-Latin scripts we explicitly want to treat as such.
      final bool isNonLatinBlock =
          (rune >= 0x0370 && rune <= 0x03FF) || // Greek
              (rune >= 0x0400 && rune <= 0x052F) || // Cyrillic
              (rune >= 0x0590 && rune <= 0x05FF) || // Hebrew
              (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
              (rune >= 0x0750 && rune <= 0x077F) || // Arabic Supplement
              (rune >= 0x08A0 && rune <= 0x08FF) || // Arabic Extended-A
              (rune >= 0x0900 && rune <= 0x097F) || // Devanagari
              (rune >= 0x3040 && rune <= 0x30FF) || // Hiragana + Katakana
              (rune >= 0x31F0 && rune <= 0x31FF) || // Katakana Phonetic Extensions
              (rune >= 0x3400 && rune <= 0x4DBF) || // CJK Extension A
              (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK Unified Ideographs
              (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul Syllables
              (rune >= 0x0E00 && rune <= 0x0E7F); // Thai
      if (isNonLatinBlock) return true;

      // Fallback: if it's outside the Latin blocks above, assume "non-latin".
      return true;
    }
    return false;
  }

  String _formatLabel(String label, String? phonetic, String? nativeLabel) {
    final cleaned = label.trim().isNotEmpty ? label.trim() : '—';
    final p = phonetic?.trim();
    final hasNative = nativeLabel != null && nativeLabel.trim().isNotEmpty;
    final base = (p == null || p.isEmpty)
        ? cleaned
        : (_containsNonLatinScript(cleaned) ? '$cleaned ($p)' : cleaned);
    if (hasNative) {
      final native = nativeLabel!.trim();
      return '$native / $base';
    }
    return base;
  }

  String buildText() {
    final start = _sessionStartLocal ?? DateTime.now();
    final buf = StringBuffer();
    buf.writeln('User ID: $_userId');
    buf.writeln(_formatDateLine(start));
    if (_cursorLine != null && _cursorLine!.isNotEmpty) {
      buf.writeln(_cursorLine);
    }
    buf.writeln();
    buf.writeln('Timeline:');
    for (final e in _timeline) {
      final time = _formatTime(e.ts);
      if (e.kind == 'C') {
        final label = _formatLabel(e.label, e.phonetic, e.nativeLabel);
        buf.writeln('- $time C $label: ${(e.correct ?? false) ? 'r' : 'f'}');
      } else if (e.kind == 'N') {
        final label = _formatLabel(e.label, e.phonetic, e.nativeLabel);
        final heard = (e.heard ?? '').replaceAll('\n', ' ').trim();
        buf.writeln(
            '- $time N $label: \"$heard\" - $label: ${(e.correct ?? false) ? 'r' : 'f'}');
      } else {
        buf.writeln('- $time Note: ${e.note}');
      }
    }
    return buf.toString();
  }

  Future<String> export() async {
    if (!_dirty && _timeline.isEmpty) {
      return 'Protokoll ist leer.';
    }
    final content = buildText();
    final start = _sessionStartLocal ?? DateTime.now();
    final dateStamp =
        '${start.year}${_fmt2(start.month)}${_fmt2(start.day)}_${_fmt2(start.hour)}${_fmt2(start.minute)}${_fmt2(start.second)}';
    final fileName = 'RobuLingo_${dateStamp}.txt';

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
