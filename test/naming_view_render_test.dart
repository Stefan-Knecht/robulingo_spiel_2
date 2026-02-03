import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/app/robulingo_app.dart';
import 'package:robulingo_flutter/logic/item_presentation_policy.dart';

void main() {
  test('naming slot renders naming view even if trial is still loading', () {
    final isNamingView = shouldRenderNamingView(
      slotMode: PresentationMode.naming,
      namingInProgress: false,
      hasNamingOutcome: false,
      policyNamingActive: true,
      namingTransition: false,
    );
    expect(isNamingView, isTrue);
  });

  test('comprehension slot renders comprehension view when no naming flags are active', () {
    final isNamingView = shouldRenderNamingView(
      slotMode: PresentationMode.comprehension,
      namingInProgress: false,
      hasNamingOutcome: false,
      policyNamingActive: false,
      namingTransition: false,
    );
    expect(isNamingView, isFalse);
  });
}

