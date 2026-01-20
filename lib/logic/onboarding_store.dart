// ------------------------------------------------------------
// Ziel (Laien): Onboarding-Wahl (Sprache, Start-Curriculum, Muttersprache, Wins) lokal sichern.
// Verbindung: robulingo_app.dart speichert/lädt hier; ergänzt UserIdentity/Curriculum-Delta.
// Tücken: Einfache JSON-Datei pro Gerät; keine Cloud-Sync, daher bei Neuinstallation weg.
// ------------------------------------------------------------
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class OnboardingData {
  final String lang;
  final String startKey;
  final String? nativeLang;
  final int winsYou;
  final int winsRival;

  OnboardingData({
    required this.lang,
    required this.startKey,
    this.nativeLang,
    this.winsYou = 0,
    this.winsRival = 0,
  });

  Map<String, dynamic> toJson() => {
        'lang': lang,
        'startKey': startKey,
        if (nativeLang != null) 'nativeLang': nativeLang,
        'winsYou': winsYou,
        'winsRival': winsRival,
      };

  factory OnboardingData.fromJson(Map<String, dynamic> json) {
    final lang = json['lang'] as String?;
    final startKey = json['startKey'] as String?;
    if (lang == null || startKey == null) {
      throw const FormatException('missing lang/startKey');
    }
    return OnboardingData(
      lang: lang,
      startKey: startKey,
      nativeLang: json['nativeLang'] as String?,
      winsYou: (json['winsYou'] as num?)?.toInt() ?? 0,
      winsRival: (json['winsRival'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Persist simple onboarding selections (lang + module).
class OnboardingStore {
  static const _fileName = 'onboarding.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');
    await file.parent.create(recursive: true);
    return file;
  }

  Future<OnboardingData?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final content = await f.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return OnboardingData.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(OnboardingData data) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(data.toJson()));
    } catch (_) {
      // ignore
    }
  }

  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // ignore
    }
  }
}
