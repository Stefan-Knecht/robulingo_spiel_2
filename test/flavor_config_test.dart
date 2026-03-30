import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/flavor_config.dart';

void main() {
  test('dialog start curriculum is allowed for the RobuLingo flavor', () {
    expect(isAllowedStartCurriculum('start_curriculum_dialog.json'), isTrue);
    expect(
      sanitizeStartCurriculum('start_curriculum_dialog.json'),
      'start_curriculum_dialog.json',
    );
  });
}
