class OnboardingData {
  final String lang;
  final String startKey;
  final String? nativeLang;
  final int winsYou;
  final int winsRival;
  final bool tapPrimerSeen;

  OnboardingData({
    required this.lang,
    required this.startKey,
    this.nativeLang,
    this.winsYou = 0,
    this.winsRival = 0,
    this.tapPrimerSeen = false,
  });

  Map<String, dynamic> toJson() => {
        'lang': lang,
        'startKey': startKey,
        if (nativeLang != null) 'nativeLang': nativeLang,
        'winsYou': winsYou,
        'winsRival': winsRival,
        'tapPrimerSeen': tapPrimerSeen,
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
      tapPrimerSeen: json['tapPrimerSeen'] as bool? ?? false,
    );
  }
}
