import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'onboarding_data.dart';

/// Persist simple onboarding selections (lang + module) in localStorage.
class OnboardingStore {
  static const String _storageKey = 'robulingo_onboarding';

  Future<OnboardingData?> load() async {
    try {
      final raw = html.window.localStorage[_storageKey];
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return OnboardingData.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(OnboardingData data) async {
    try {
      html.window.localStorage[_storageKey] = jsonEncode(data.toJson());
    } catch (_) {
      // ignore
    }
  }

  Future<void> clear() async {
    html.window.localStorage.remove(_storageKey);
  }
}
