// ------------------------------------------------------------
// Ziel (Laien): Klare Daten-Container für Curriculum-Items und Trials.
// Strategie: Nur Struktur, keine Logik; so bleibt main.dart lesbarer.
// Schritte: CurriculumEntry (IDs), ItemData (JSON/Bild/Audio), Trial (2AFC-Paar).
// Tücken: imageVariants/signature dienen zum Duplikate vermeiden – nicht entfernen.
// ------------------------------------------------------------
import 'dart:typed_data';

class CurriculumEntry {
  final String uuid;
  final String index;
  final int? position;
  CurriculumEntry({required this.uuid, required this.index, this.position});
}

class ItemData {
  final String uuid;
  final String index;
  final int? position;
  final String text;
  final String? nativeText;
  final String? phonetic; // Lautschrift für die aktuelle Sprache (z.B. phonetic_de)
  final Map<String, List<String>> hintRefsByLang;
  final Uint8List imageBytes; // primary for convenience
  final List<Uint8List> imageVariants;
  final Uri audioUri;
  final List<Uri> audioVariants;
  final String imageSignature; // einfache Signatur zur Erkennung gleicher Bilder
  ItemData({
    required this.uuid,
    required this.index,
    this.position,
    required this.text,
    this.nativeText,
    this.phonetic,
    required this.hintRefsByLang,
    required this.imageBytes,
    required this.imageVariants,
    required this.audioUri,
    required this.audioVariants,
    required this.imageSignature,
  });
}

class Trial {
  final ItemData target;
  final ItemData distractor;
  final bool targetOnLeft;
  final Uint8List targetImageBytes;
  final Uint8List distractorImageBytes;
  final bool isReview;
  Trial({
    required this.target,
    required this.distractor,
    required this.targetOnLeft,
    required this.targetImageBytes,
    required this.distractorImageBytes,
    this.isReview = false,
  });
}
