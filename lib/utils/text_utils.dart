// ------------------------------------------------------------
// Ziel (Laien): Text normalisieren und Ähnlichkeit (Levenshtein) berechnen.
// Strategie: Utility ausgelagert, damit main.dart schlanker bleibt.
// Schritte: normalizeText (lowercase + Sonderzeichen filtern), levenshtein (Edit-Distanz).
// Tücken: RegExp ist grob; bei neuen Alphabeten ggf. erweitern.
// ------------------------------------------------------------
import 'dart:math';

String _stripCommonDiacritics(String input) {
  const Map<int, String> map = {
    // Greek (tonos/dialytika) + final sigma
    0x03AC: 'α', // ά
    0x03AD: 'ε', // έ
    0x03AE: 'η', // ή
    0x03AF: 'ι', // ί
    0x03CC: 'ο', // ό
    0x03CD: 'υ', // ύ
    0x03CE: 'ω', // ώ
    0x03CA: 'ι', // ï (ϊ)
    0x0390: 'ι', // ΐ (will be lowercased but keep)
    0x03CB: 'υ', // ϋ
    0x03B0: 'υ', // ΰ
    0x03C2: 'σ', // ς -> σ

    // Latin (common accented letters) -> base
    0x00E0: 'a', // à
    0x00E1: 'a', // á
    0x00E2: 'a', // â
    0x00E3: 'a', // ã
    0x00E4: 'a', // ä
    0x00E5: 'a', // å
    0x0101: 'a', // ā
    0x0103: 'a', // ă
    0x0105: 'a', // ą
    0x00E6: 'ae', // æ
    0x00E7: 'c', // ç

    0x00E8: 'e', // è
    0x00E9: 'e', // é
    0x00EA: 'e', // ê
    0x00EB: 'e', // ë
    0x0113: 'e', // ē
    0x0115: 'e', // ĕ
    0x0117: 'e', // ė
    0x0119: 'e', // ę
    0x011B: 'e', // ě

    0x00EC: 'i', // ì
    0x00ED: 'i', // í
    0x00EE: 'i', // î
    0x00EF: 'i', // ï
    0x012B: 'i', // ī
    0x012D: 'i', // ĭ
    0x012F: 'i', // į
    0x0131: 'i', // ı

    0x00F1: 'n', // ñ

    0x00F2: 'o', // ò
    0x00F3: 'o', // ó
    0x00F4: 'o', // ô
    0x00F5: 'o', // õ
    0x00F6: 'o', // ö
    0x00F8: 'o', // ø
    0x014D: 'o', // ō
    0x014F: 'o', // ŏ
    0x0151: 'o', // ő
    0x0153: 'oe', // œ

    0x00F9: 'u', // ù
    0x00FA: 'u', // ú
    0x00FB: 'u', // û
    0x00FC: 'u', // ü
    0x016B: 'u', // ū
    0x016D: 'u', // ŭ
    0x016F: 'u', // ů
    0x0171: 'u', // ű
    0x0173: 'u', // ų

    0x00FD: 'y', // ý
    0x00FF: 'y', // ÿ
    0x00DF: 'ss', // ß
  };

  final buf = StringBuffer();
  for (final rune in input.runes) {
    final repl = map[rune];
    if (repl != null) {
      buf.write(repl);
    } else {
      buf.writeCharCode(rune);
    }
  }
  return buf.toString();
}

String normalizeText(String input) {
  final lowered = input.toLowerCase();
  final deaccented = _stripCommonDiacritics(lowered);
  // Remove common Arabic diacritics (harakat) + tatweel, so ASR output that
  // omits them can still match stored target text.
  final withoutArabicDiacritics = deaccented.replaceAll(
    RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'),
    '',
  );

  // Keep letters and digits across scripts (Arabic, Japanese, CJK, Cyrillic, …),
  // plus spaces. Replace everything else with space, then collapse whitespace.
  final cleaned = withoutArabicDiacritics.replaceAll(
    RegExp(r'[^\p{L}\p{N} ]', unicode: true),
    ' ',
  );
  return cleaned.replaceAll(RegExp(r'\s+', unicode: true), ' ').trim();
}

int levenshtein(String s, String t) {
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;
  final v0 = List<int>.generate(t.length + 1, (i) => i);
  final v1 = List<int>.filled(t.length + 1, 0);
  for (var i = 0; i < s.length; i++) {
    v1[0] = i + 1;
    for (var j = 0; j < t.length; j++) {
      final cost = s[i] == t[j] ? 0 : 1;
      v1[j + 1] = min(min(v1[j] + 1, v0[j + 1] + 1), v0[j] + cost);
    }
    for (var j = 0; j < v0.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v1[t.length];
}
