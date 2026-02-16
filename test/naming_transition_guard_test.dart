import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/app/robulingo_app.dart';

void main() {
  test('naming transitions are disabled while temporary naming block is active',
      () {
    final disabled = shouldDisableNamingTransitions(
      namingDisabled: false,
      namingBlockRemaining: 19,
    );
    expect(disabled, isTrue);
  });

  test('naming transitions are disabled when naming is globally disabled', () {
    final disabled = shouldDisableNamingTransitions(
      namingDisabled: true,
      namingBlockRemaining: 0,
    );
    expect(disabled, isTrue);
  });

  test('naming transitions stay enabled when no guard condition applies', () {
    final disabled = shouldDisableNamingTransitions(
      namingDisabled: false,
      namingBlockRemaining: 0,
    );
    expect(disabled, isFalse);
  });
}
