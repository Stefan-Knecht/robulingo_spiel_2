import 'onboarding_data.dart';

class OnboardingStore {
  Future<OnboardingData?> load() async {
    throw UnsupportedError('OnboardingStore is not supported on this platform.');
  }

  Future<void> save(OnboardingData data) async {
    throw UnsupportedError('OnboardingStore is not supported on this platform.');
  }

  Future<void> clear() async {
    throw UnsupportedError('OnboardingStore is not supported on this platform.');
  }
}
