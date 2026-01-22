// ------------------------------------------------------------
// Ziel (Laien): Datenmodelle fuer Hint-Packs (L1 -> L2).
// Verbindung: HintsService laedt Packs; Session-UI zeigt HintContent pro Item.
// Tuecken: Ein Pack kann viele Items enthalten; leer == keine Hints.
// ------------------------------------------------------------
class HintContent {
  const HintContent({
    required this.id,
    this.title,
    this.body,
    this.examples = const [],
  });

  final String id;
  final String? title;
  final String? body;
  final List<String> examples;

  bool get isEmpty {
    return (title == null || title!.isEmpty) &&
        (body == null || body!.isEmpty) &&
        examples.isEmpty;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title != null && title!.isNotEmpty) 'title': title,
        if (body != null && body!.isNotEmpty) 'body': body,
        if (examples.isNotEmpty) 'examples': examples,
      };

  factory HintContent.fromJson(Map<String, dynamic> json) {
    final rawExamples = json['examples'];
    final examples = rawExamples is List
        ? rawExamples.whereType<String>().toList()
        : const <String>[];
    return HintContent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString(),
      body: json['body']?.toString(),
      examples: examples,
    );
  }
}

class HintPack {
  HintPack({
    required this.l1,
    required this.l2,
    required this.hints,
    required this.fetchedAtMs,
    this.packVersion,
    this.etag,
  });

  final String l1;
  final String l2;
  final Map<String, HintContent> hints;
  final int fetchedAtMs;
  final String? packVersion;
  final String? etag;

  List<HintContent> hintsForIds(List<String> ids) {
    final out = <HintContent>[];
    for (final id in ids) {
      final hint = hints[id];
      if (hint != null && !hint.isEmpty) {
        out.add(hint);
      }
    }
    return out;
  }

  HintPack copyWith({int? fetchedAtMs, String? etag}) {
    return HintPack(
      l1: l1,
      l2: l2,
      hints: hints,
      fetchedAtMs: fetchedAtMs ?? this.fetchedAtMs,
      packVersion: packVersion,
      etag: etag ?? this.etag,
    );
  }
}
