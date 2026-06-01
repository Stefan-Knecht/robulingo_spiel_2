import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/data/resume_state_service.dart';
import 'package:robulingo_flutter/logic/resume_state_controller.dart';

void main() {
  test('cursor lookup is scoped to module, not language pair', () {
    final controller = ResumeStateController(
      service: ResumeStateService(workerHost: 'example.com', apiPrefix: '/api'),
    );
    controller.setState(
      ResumeState(
        userId: 'learner-1',
        entries: [
          ResumeStateEntry(
            startKey: 'dailywords.json',
            lang: 'en',
            nativeLang: 'de',
            cursor: 42,
            date: DateTime.utc(2026, 1, 1),
          ),
        ],
      ),
    );

    expect(
      controller.cursorForStartKey(
        startKey: 'dailywords.json',
        lang: 'fr',
        nativeLang: 'it',
      ),
      42,
    );
  });
}
