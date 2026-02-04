import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/data/models.dart';
import 'package:robulingo_flutter/logic/item_presentation_policy.dart';
import 'package:robulingo_flutter/logic/item_stats.dart';
import 'package:robulingo_flutter/logic/session_reset.dart';
import 'package:robulingo_flutter/logic/trial_buffer.dart';

void main() {
  test('resetSessionState clears item cache and session buffers', () {
    final item1 = ItemData(
      uuid: 'u1',
      index: '0',
      text: 'L2-1',
      nativeText: 'L1-1',
      phonetic: null,
      hintRefsByLang: const {},
      imageBytes: Uint8List.fromList([1]),
      imageVariants: [Uint8List.fromList([1])],
      audioUri: Uri.parse('https://example.com/u1.mp3'),
      audioVariants: const [],
      imageSignature: 'sig1',
    );
    final item2 = ItemData(
      uuid: 'u2',
      index: '1',
      text: 'L2-2',
      nativeText: 'L1-2',
      phonetic: null,
      hintRefsByLang: const {},
      imageBytes: Uint8List.fromList([2]),
      imageVariants: [Uint8List.fromList([2])],
      audioUri: Uri.parse('https://example.com/u2.mp3'),
      audioVariants: const [],
      imageSignature: 'sig2',
    );

    final trialBuffer = TrialBuffer();
    trialBuffer.addNewItems([item1, item2]);

    final itemByUuid = <String, Object?>{
      item1.uuid: item1,
      item2.uuid: item2,
    };

    final deps = SessionResetDeps(
      trialBuffer: trialBuffer,
      itemByUuid: itemByUuid,
      presentationPolicy: ItemPresentationPolicy(),
      itemStats: ItemStatsTracker(),
      comprehensionHistory: [true, false],
      namingHistory: [false],
      comprehensionSeen: {'u1'},
      loadErrors: ['x'],
      correctCounts: {'u1': 1},
      audioPlayCounts: {'u1': 2},
      audioMaxSequenceIndex: {'u1': 3},
      audioMinSequenceIndex: {'u1': 0},
      audioUrlOkCache: {'u1': true},
      imageVariantCursorByUuid: {'u1': 1},
    );

    var nativeSelectTimerCancelled = false;
    var hintRevealedCleared = false;

    resetSessionState(
      deps: deps,
      cancelNativeSelectTimer: () => nativeSelectTimerCancelled = true,
      clearHintRevealed: () => hintRevealedCleared = true,
    );

    expect(trialBuffer.items, isEmpty);
    expect(trialBuffer.trials, isEmpty);
    expect(itemByUuid, isEmpty);
    expect(deps.comprehensionHistory, isEmpty);
    expect(deps.namingHistory, isEmpty);
    expect(deps.comprehensionSeen, isEmpty);
    expect(deps.loadErrors, isEmpty);
    expect(nativeSelectTimerCancelled, isTrue);
    expect(hintRevealedCleared, isTrue);
  });
}

