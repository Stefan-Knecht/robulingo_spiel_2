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

  test('ensureNamingBlock respects minQualifiedItemsToStart (no single-item naming repeats)', () {
    const config = ItemPresentationConfig(
      comprehensionBlockSize: 3,
      comprehensionCoreSize: 1,
      compWindowSize: 2,
      compWindowCorrectNeeded: 2,
      namingBlockSize: 2,
      minQualifiedItemsToStart: 3,
    );
    final policy = ItemPresentationPolicy(config: config);

    policy.initializeComprehensionBlock(
      curriculumUuids: const ['A', 'B', 'C', 'D'],
      startIndex: 0,
    );

    // Qualify only one item: readyToName.length == 1.
    policy.onComprehensionAnswered(
      uuid: 'A',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    policy.onComprehensionAnswered(
      uuid: 'A',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    expect(policy.readyToName.length, 1);

    // Must NOT start naming with fewer than minQualifiedItemsToStart.
    final startedTooEarly = policy.ensureNamingBlock(namingDisabled: false);
    expect(startedTooEarly, isFalse);
    expect(policy.currentSlot.mode, PresentationMode.comprehension);

    // Qualify two more items: readyToName.length == 3.
    policy.onComprehensionAnswered(
      uuid: 'B',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    policy.onComprehensionAnswered(
      uuid: 'B',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    policy.onComprehensionAnswered(
      uuid: 'C',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    policy.onComprehensionAnswered(
      uuid: 'C',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    expect(policy.readyToName.length, 3);

    final started = policy.ensureNamingBlock(namingDisabled: false);
    expect(started, isTrue);
    expect(policy.currentSlot.mode, PresentationMode.naming);
  });

  test('naming block is exhausted (items removed) before returning to comprehension', () {
    const config = ItemPresentationConfig(
      comprehensionBlockSize: 3,
      comprehensionCoreSize: 1,
      compWindowSize: 1,
      compWindowCorrectNeeded: 1,
      namingBlockSize: 2,
      minQualifiedItemsToStart: 2,
      namingMasteryCorrectThreshold: 99, // disable mastery removal for this test
      namingDownFromNamingMaxAttempts: 1, // remove once attempts > 1
    );
    final policy = ItemPresentationPolicy(config: config);

    policy.initializeComprehensionBlock(
      curriculumUuids: const ['A', 'B', 'C'],
      startIndex: 0,
    );

    // Qualify A and B into naming (but do not auto-start naming here).
    policy.onComprehensionAnswered(
      uuid: 'A',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    policy.onComprehensionAnswered(
      uuid: 'B',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );
    expect(policy.readyToName.contains('A'), isTrue);
    expect(policy.readyToName.contains('B'), isTrue);

    final started = policy.ensureNamingBlock(namingDisabled: false);
    expect(started, isTrue);
    expect(policy.currentSlot.mode, PresentationMode.naming);
    expect(policy.currentSlot.targetUuid, 'A');

    // Remove A mid-trial (as would happen via per-attempt updates) and ensure
    // we can still advance to B.
    final removedA = policy.onNamingStatsUpdated(
      uuid: 'A',
      namingAttempts: 2,
      namingCorrect: 0,
    );
    expect(removedA, isTrue);

    // Idempotent: don't enqueue A again.
    final removedAAgain = policy.onNamingStatsUpdated(
      uuid: 'A',
      namingAttempts: 3,
      namingCorrect: 0,
    );
    expect(removedAAgain, isFalse);
    expect(policy.refillerQueueSnapshot.where((u) => u == 'A').length, 1);

    final afterA = policy.onNamingAttemptFinished(
      currentUuid: 'A',
      namingDisabled: false,
      namingInProgress: false,
    );
    expect(afterA.nextSlot.mode, PresentationMode.naming);
    expect(afterA.nextSlot.targetUuid, 'B');

    final removedB = policy.onNamingStatsUpdated(
      uuid: 'B',
      namingAttempts: 2,
      namingCorrect: 0,
    );
    expect(removedB, isTrue);
    final afterB = policy.onNamingAttemptFinished(
      currentUuid: 'B',
      namingDisabled: false,
      namingInProgress: false,
    );

    // The naming block is now exhausted: it must return to comprehension.
    expect(afterB.nextSlot.mode, PresentationMode.comprehension);
    expect(policy.isNamingActive, isFalse);

    // And a new naming block must not restart with the removed items.
    final restarted = policy.ensureNamingBlock(namingDisabled: false);
    expect(restarted, isFalse);
  });

  test('curriculumExhausted flips explicitly after one full curriculum pass', () {
    const config = ItemPresentationConfig(
      comprehensionBlockSize: 3,
      comprehensionCoreSize: 2,
    );
    final policy = ItemPresentationPolicy(config: config);

    policy.initializeComprehensionBlock(
      curriculumUuids: const ['A', 'B', 'C'],
      startIndex: 0,
    );

    expect(policy.curriculumExhausted, isTrue);
  });

  test('after curriculum exhaustion, comprehension replacement uses refiller only', () {
    const config = ItemPresentationConfig(
      comprehensionBlockSize: 2,
      comprehensionCoreSize: 1,
      compWindowSize: 1,
      compWindowCorrectNeeded: 1,
      minQualifiedItemsToStart: 99, // keep naming off
    );
    final policy = ItemPresentationPolicy(config: config);

    policy.initializeComprehensionBlock(
      curriculumUuids: const ['A', 'B'],
      startIndex: 0,
    );
    expect(policy.curriculumExhausted, isTrue);

    // Seed a down-item replacement candidate.
    policy.setRefillerQueue(const ['R']);

    // A is in slot 0 (non-last). On qualification it is replaced;
    // with exhausted curriculum this must come from refiller, not curriculum.
    final _ = policy.onComprehensionAnswered(
      uuid: 'A',
      correct: true,
      namingDisabled: true,
      namingInProgress: false,
    );

    expect(policy.comprehensionBlockUuids.contains('R'), isTrue);
    expect(policy.comprehensionBlockUuids.where((u) => u == 'A').length, 0);
  });

  test('naming-up does not enqueue refiller, naming-down does', () {
    const config = ItemPresentationConfig(
      namingMasteryCorrectThreshold: 1, // naming-up if correct > 1
      namingDownFromNamingMaxAttempts: 5, // naming-down if attempts > 5
    );
    final policy = ItemPresentationPolicy(config: config);

    policy.initializeComprehensionBlock(
      curriculumUuids: const ['A', 'B', 'C'],
      startIndex: 0,
    );

    final removedUp = policy.onNamingStatsUpdated(
      uuid: 'A',
      namingAttempts: 1,
      namingCorrect: 2,
    );
    expect(removedUp, isTrue);
    expect(policy.refillerQueueSnapshot.contains('A'), isFalse);

    final removedDown = policy.onNamingStatsUpdated(
      uuid: 'B',
      namingAttempts: 6,
      namingCorrect: 0,
    );
    expect(removedDown, isTrue);
    expect(policy.refillerQueueSnapshot.contains('B'), isTrue);
  });
}
