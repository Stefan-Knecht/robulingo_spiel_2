// ------------------------------------------------------------
// Ziel (Laien): Text normalisieren und Ähnlichkeit (Levenshtein) berechnen.
// Strategie: Utility ausgelagert, damit main.dart schlanker bleibt.
// Schritte: normalizeText (lowercase + Sonderzeichen filtern), levenshtein (Edit-Distanz).
// Tücken: RegExp ist grob; bei neuen Alphabeten ggf. erweitern.
// ------------------------------------------------------------
import 'dart:math';

String normalizeText(String input) {
  final lowered = input.toLowerCase();
  final cleaned = lowered.replaceAll(RegExp(r'[^a-zà-ÿ\u0400-\u04ff0-9 ]'), ' ');
  return cleaned.replaceAll(RegExp(r'\\s+'), ' ').trim();
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
