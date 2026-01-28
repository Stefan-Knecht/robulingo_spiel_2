import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/logic/item_presentation_policy.dart';

void main() {
  test(
      'removing from naming blocks re-qualification into naming within session',
      () {
    const config = ItemPresentationConfig(
      comprehensionBlockSize: 2,
      comprehensionCoreSize: 1,
      compWindowSize: 2,
      compWindowCorrectNeeded: 2,
      namingBlockSize: 1,
      minQualifiedItemsToStart: 1,
      namingMasteryCorrectThreshold: 2,
    );
    final policy = ItemPresentationPolicy(config: config);

    policy.initializeComprehensionBlock(
      curriculumUuids: const ['A', 'B'],
      startIndex: 0,
    );

    policy.onComprehensionAnswered(
      uuid: 'A',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    expect(policy.readyToName.contains('A'), isFalse);

    policy.onComprehensionAnswered(
      uuid: 'A',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    expect(policy.readyToName.contains('A'), isTrue);

    final removed = policy.onNamingStatsUpdated(
      uuid: 'A',
      namingAttempts: 3,
      namingCorrect: 3,
    );
    expect(removed, isTrue);
    expect(policy.readyToName.contains('A'), isFalse);

    // Even with a fresh full window again, it must NOT re-qualify into naming in the same session.
    policy.onComprehensionAnswered(
      uuid: 'A',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    expect(policy.readyToName.contains('A'), isFalse);

    policy.onComprehensionAnswered(
      uuid: 'A',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    expect(policy.readyToName.contains('A'), isFalse);
  });
}
