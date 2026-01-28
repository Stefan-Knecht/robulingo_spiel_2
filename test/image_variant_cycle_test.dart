import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/data/models.dart';
import 'package:robulingo_flutter/logic/trial_buffer.dart';

void main() {
  test('TrialBuffer cycles imageVariants deterministically (0,1,2,0...)', () {
    final item = ItemData(
      uuid: 'u1',
      index: '0',
      text: 'x',
      nativeText: null,
      phonetic: null,
      hintRefsByLang: const {},
      imageBytes: Uint8List.fromList([0]),
      imageVariants: [
        Uint8List.fromList([0]),
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ],
      audioUri: Uri.parse('https://example.com/a.mp3'),
      audioVariants: const [],
      imageSignature: 'sig',
    );

    final other = ItemData(
      uuid: 'u2',
      index: '1',
      text: 'y',
      nativeText: null,
      phonetic: null,
      hintRefsByLang: const {},
      imageBytes: Uint8List.fromList([9]),
      imageVariants: [Uint8List.fromList([9])],
      audioUri: Uri.parse('https://example.com/b.mp3'),
      audioVariants: const [],
      imageSignature: 'sig2',
    );

    final buf = TrialBuffer();
    buf.addNewItems([item, other]);

    // Each time the item is used as a target or distractor, the next variant is picked.
    // With 2 items, it will build one trial per added item.
    // With 2 items, u1 is picked once as target and once as distractor per rebuild,
    // so the cursor advances by 2 each time. The important property is: it's
    // deterministic and cycles through the variants.
    final first = buf.trials.firstWhere((t) => t.target.uuid == 'u1');
    expect(first.targetImageBytes[0], 0);

    buf.rebuildTrials();
    final second = buf.trials.firstWhere((t) => t.target.uuid == 'u1');
    expect(second.targetImageBytes[0], 2);

    buf.rebuildTrials();
    final third = buf.trials.firstWhere((t) => t.target.uuid == 'u1');
    expect(third.targetImageBytes[0], 1);

    buf.rebuildTrials();
    final fourth = buf.trials.firstWhere((t) => t.target.uuid == 'u1');
    expect(fourth.targetImageBytes[0], 0);
  });
}
