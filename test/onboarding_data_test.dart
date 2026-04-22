import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/logic/onboarding_data.dart';

void main() {
  test('serializes tap primer seen flag', () {
    final data = OnboardingData(
      lang: 'en',
      startKey: 'start_curriculum_a.json',
      nativeLang: 'de',
      winsYou: 2,
      winsRival: 1,
      tapPrimerSeen: true,
    );

    final decoded = OnboardingData.fromJson(data.toJson());

    expect(decoded.tapPrimerSeen, isTrue);
  });

  test('defaults tap primer seen flag for legacy onboarding data', () {
    final decoded = OnboardingData.fromJson({
      'lang': 'en',
      'startKey': 'start_curriculum_a.json',
      'nativeLang': 'de',
      'winsYou': 2,
      'winsRival': 1,
    });

    expect(decoded.tapPrimerSeen, isFalse);
  });
}
