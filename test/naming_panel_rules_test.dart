import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/logic/naming_controller.dart';

void main() {
  test('naming run ends after first listen when correct', () {
    final out = simulateNamingRunOutcome(
      firstCorrect: true,
      repeatCorrect: true,
      allowRepeat: true,
    );
    expect(out.attempts, 1);
    expect(out.correctCount, 1);
    expect(out.correct, isTrue);
    expect(out.moves, 2);
    expect(out.usedHint, isFalse);
  });

  test('naming run allows exactly one hint+repeat listen when first is incorrect', () {
    final out = simulateNamingRunOutcome(
      firstCorrect: false,
      repeatCorrect: true,
      allowRepeat: true,
    );
    expect(out.attempts, 1);
    expect(out.correctCount, 1);
    expect(out.correct, isTrue);
    expect(out.moves, 1);
    expect(out.usedHint, isTrue);
  });

  test('naming run ends after first listen when repeats are disabled', () {
    final out = simulateNamingRunOutcome(
      firstCorrect: false,
      repeatCorrect: true,
      allowRepeat: false,
    );
    expect(out.attempts, 1);
    expect(out.correctCount, 0);
    expect(out.correct, isFalse);
    expect(out.moves, 0);
    expect(out.usedHint, isFalse);
  });
}
