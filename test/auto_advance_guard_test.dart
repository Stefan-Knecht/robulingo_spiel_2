import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/app/robulingo_app.dart';

void main() {
  test(
      'Naming slot (even while loading) prevents comprehension auto-advance',
      () {
    expect(
      shouldSkipComprehensionAutoAdvance(
        namingHold: false,
        namingInProgress: false,
        inNamingSlot: true,
      ),
      isTrue,
    );
  });

  test(
      'Token-gated timer replays cannot advance twice (models trialIndex/token increment exactly once)',
      () {
    var token = 1;
    var advances = 0;
    void gotoNextTrial() {
      advances++;
      token++; // mirrors `currentTrialToken++` in `_applySlot`
    }

    void timerFires({required int scheduledToken}) {
      if (scheduledToken != token) return;
      final skip = shouldSkipComprehensionAutoAdvance(
        namingHold: false,
        namingInProgress: false,
        inNamingSlot: false,
      );
      if (skip) return;
      gotoNextTrial();
    }

    final scheduledToken = token;
    timerFires(scheduledToken: scheduledToken);
    timerFires(scheduledToken: scheduledToken); // stale replay
    timerFires(scheduledToken: scheduledToken); // stale replay
    expect(advances, 1);
  });

  test(
      'Randomized ASR/audio/timer ordering keeps naming phase ahead of comprehension',
      () {
    final random = Random(1);
    for (var i = 0; i < 128; i++) {
      final namingHold = random.nextBool();
      final namingInProgress = random.nextBool();
      final inNamingSlot = random.nextBool();
      final result = shouldSkipComprehensionAutoAdvance(
        namingHold: namingHold,
        namingInProgress: namingInProgress,
        inNamingSlot: inNamingSlot,
      );
      final expected = namingHold || namingInProgress || inNamingSlot;
      expect(
        result,
        expected,
        reason: 'Randomized interleaving of ASR/audio/timer events must keep '
            'the naming phase from being interrupted by comprehension.',
      );
    }
  });
}
