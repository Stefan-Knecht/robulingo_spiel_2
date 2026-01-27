import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/logic/presentation_protocol_log.dart';

void main() {
  test('protocol appends phonetic for non-latin labels', () async {
    final log = PresentationProtocolLog();
    await log.startSession(DateTime.utc(2026, 1, 27, 12, 0, 0), userId: 'u1');

    log.addComprehension(label: '水', phonetic: 'mizu', correct: true);
    log.addComprehension(label: 'Wasser', phonetic: 'vaser', correct: false);

    log.addNaming(label: '水', phonetic: 'mizu', heard: 'mizu', correct: false);

    final text = log.buildText();

    expect(text, contains('- 水 (mizu): r'));
    expect(text, contains('- Wasser: f'));
    expect(text, isNot(contains('- Wasser (vaser): f')));
    expect(text, contains('- 水 (mizu): "mizu" - 水 (mizu): f'));
  });
}

