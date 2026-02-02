import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'onboarding_data.dart';

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
