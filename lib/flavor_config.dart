class AppFlavorConfig {
  const AppFlavorConfig({
    required this.id,
    required this.brandLogoAsset,
    required this.dashboardLandingUrl,
    required this.consentInfoUrl,
    required this.registerInfoUrl,
    required this.allowedStartCurricula,
    required this.allowPickManifest,
    required this.defaultStartCurriculum,
    required this.userDataBucketVirtualHost,
    required this.userDataBucketPathBase,
  });

  final String id;
  final String brandLogoAsset;
  final String dashboardLandingUrl;
  final String consentInfoUrl;
  final String registerInfoUrl;
  final List<String> allowedStartCurricula;
  final bool allowPickManifest;
  final String defaultStartCurriculum;
  final String userDataBucketVirtualHost;
  final String userDataBucketPathBase;
}

const AppFlavorConfig _robuLingoFlavor = AppFlavorConfig(
  id: 'robulingo',
  brandLogoAsset: 'assets/icons/RL_logo.webp',
  dashboardLandingUrl: 'https://www.dailywords-project.org/',
  consentInfoUrl: 'https://www.dailywords-project.org/trial',
  registerInfoUrl: 'https://www.dailywords-project.org/register/',
  allowedStartCurricula: <String>[
    'start_curriculum_a.json',
    'start_curriculum_b.json',
    'start_curriculum_t.json',
    'start_curriculum_s.json',
    'start_curriculum_l.json',
  ],
  allowPickManifest: true,
  defaultStartCurriculum: 'start_curriculum_a.json',
  userDataBucketVirtualHost:
      'https://userdata.aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com',
  userDataBucketPathBase:
      'https://aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com/userdata',
);

const AppFlavorConfig _dailyWordsFlavor = AppFlavorConfig(
  id: 'dailywords',
  brandLogoAsset: 'assets/icons/DailyWords.webp',
  dashboardLandingUrl: 'https://www.dailywords-project.org/',
  consentInfoUrl: 'https://www.dailywords-project.org/trial',
  registerInfoUrl: 'https://www.dailywords-project.org/register/',
  allowedStartCurricula: <String>[
    'start_curriculum_a.json',
    'start_curriculum_b.json',
  ],
  allowPickManifest: false,
  defaultStartCurriculum: 'start_curriculum_a.json',
  userDataBucketVirtualHost:
      'https://dailywordsuserdata.aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com',
  userDataBucketPathBase:
      'https://aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com/dailywordsuserdata',
);

final String _rawAppFlavor =
    const String.fromEnvironment('APP_FLAVOR', defaultValue: 'robulingo')
        .trim()
        .toLowerCase();

final AppFlavorConfig activeFlavor =
    _rawAppFlavor == 'dailywords' ? _dailyWordsFlavor : _robuLingoFlavor;

Map<String, String> withFlavorHeader([Map<String, String>? headers]) {
  final out = <String, String>{};
  if (headers != null) {
    out.addAll(headers);
  }
  if (activeFlavor.id != _robuLingoFlavor.id) {
    out['x-app-flavor'] = activeFlavor.id;
  }
  return out;
}

bool isPickManifestKey(String key) {
  return key.trim().toLowerCase().startsWith('pick_');
}

String _baseStartCurriculumKey(String key) {
  final trimmed = key.trim().toLowerCase();
  if (!trimmed.endsWith('.json')) return trimmed;
  final stem = trimmed.substring(0, trimmed.length - 5);
  final underscore = stem.lastIndexOf('_');
  if (underscore <= 0 || underscore >= stem.length - 1) return trimmed;
  final suffix = stem.substring(underscore + 1);
  final isLikelyLangSuffix = RegExp(r'^[a-z]{2,3}$').hasMatch(suffix);
  if (!isLikelyLangSuffix) return trimmed;
  return '${stem.substring(0, underscore)}.json';
}

bool isAllowedStartCurriculum(String key) {
  if (isPickManifestKey(key)) return activeFlavor.allowPickManifest;
  final base = _baseStartCurriculumKey(key);
  final allowed = activeFlavor.allowedStartCurricula
      .map((e) => e.trim().toLowerCase())
      .toSet();
  return allowed.contains(base);
}

String sanitizeStartCurriculum(String? key) {
  final raw = key?.trim();
  if (raw == null || raw.isEmpty) {
    return activeFlavor.defaultStartCurriculum;
  }
  return isAllowedStartCurriculum(raw)
      ? raw
      : activeFlavor.defaultStartCurriculum;
}
