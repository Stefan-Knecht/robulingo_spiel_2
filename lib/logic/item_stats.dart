// ------------------------------------------------------------
// Ziel (Laien): Pro Item Treffer/Falsch für Comprehension und Naming zählen.
// Verbindung: Befüllt von robulingo_app.dart nach jeder Antwort; Dashboard liest die Maps aus.
// Tücken: Nur Session-scope (kein Persist); Keys sind Item-UUIDs.
// ------------------------------------------------------------
class ItemStats {
  int compAttempts;
  int compCorrect;
  int namingAttempts;
  int namingCorrect;

  ItemStats({
    this.compAttempts = 0,
    this.compCorrect = 0,
    this.namingAttempts = 0,
    this.namingCorrect = 0,
  });

  void addComprehension(bool correct) {
    compAttempts++;
    if (correct) compCorrect++;
  }

  void addNaming(bool correct) {
    namingAttempts++;
    if (correct) namingCorrect++;
  }
}

/// Tracks per-item comprehension/naming stats.
class ItemStatsTracker {
  final Map<String, ItemStats> _items = {};

  ItemStats statsFor(String uuid) =>
      _items.putIfAbsent(uuid, () => ItemStats());

  void reset() {
    _items.clear();
  }

  void addComprehension(String uuid, bool correct) {
    final stats = _items.putIfAbsent(uuid, () => ItemStats());
    stats.addComprehension(correct);
  }

  void addNaming(String uuid, bool correct) {
    final stats = _items.putIfAbsent(uuid, () => ItemStats());
    stats.addNaming(correct);
  }

  Map<String, int> comprehensionAttempts() =>
      _items.map((k, v) => MapEntry(k, v.compAttempts));
  Map<String, int> comprehensionCorrect() =>
      _items.map((k, v) => MapEntry(k, v.compCorrect));
  Map<String, int> namingAttempts() =>
      _items.map((k, v) => MapEntry(k, v.namingAttempts));
  Map<String, int> namingCorrect() =>
      _items.map((k, v) => MapEntry(k, v.namingCorrect));
}
