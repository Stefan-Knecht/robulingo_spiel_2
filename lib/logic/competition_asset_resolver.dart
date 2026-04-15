import 'dart:math';

class RivalAssetResolver {
  static const Map<String, int> _emotionCounts = {
    'talking': 15,
    'content': 14,
    'bloating': 12,
    'expecting': 23,
    'dissatisfied': 11,
    'angry': 14,
  };
  static const List<String> _emotionScale = [
    'angry',
    'dissatisfied',
    'expecting',
    'talking',
    'content',
    'bloating',
  ];

  static String pathFor({
    required int wins,
    required int rivalWins,
    required int viewCount,
    int emotionBoostSteps = 0,
  }) {
    final diff = rivalWins - wins;
    final baseEmotion = _emotionForDiff(diff);
    final emotion = _boostEmotion(baseEmotion, emotionBoostSteps);
    final count = _emotionCounts[emotion] ?? 1;
    final variantIndex = viewCount % count;
    final numStr = (variantIndex + 1).toString().padLeft(2, '0');
    return 'assets/icons/rival_${emotion}_$numStr.webp';
  }

  static String _emotionForDiff(int diff) {
    if (diff >= 15) return 'bloating';
    if (diff >= 9) return 'content';
    if (diff >= 3) return 'talking';
    if (diff <= -15) return 'angry';
    if (diff <= -9) return 'dissatisfied';
    if (diff <= -3) return 'expecting';
    return 'content';
  }

  static String _boostEmotion(String base, int steps) {
    if (steps <= 0) return base;
    final idx = _emotionScale.indexOf(base);
    if (idx == -1) return base;
    final boosted = min(_emotionScale.length - 1, idx + steps);
    return _emotionScale[boosted];
  }
}

class TherapistAssetResolver {
  static String pathFor({required int wins, required int rivalWins}) {
    final diff = wins - rivalWins;
    if (diff > 4) return 'assets/icons/therapist_hilarious.webp';
    if (diff >= 2) return 'assets/icons/therapist_content.webp';
    if (diff >= -1) return 'assets/icons/therapist_neutral.webp';
    if (diff >= -4) return 'assets/icons/therapist_concerned.webp';
    return 'assets/icons/therapist_worried.webp';
  }
}
