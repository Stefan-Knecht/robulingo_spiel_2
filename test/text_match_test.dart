import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/utils/text_match.dart';

void main() {
  test('matchTranscriptToTargets accepts synonyms (exact)', () {
    final match = matchTranscriptToTargets(
      'Warten Sie bitte',
      const ['Bitte warten', 'Warten Sie bitte', 'Einen Moment bitte'],
    );
    expect(match.accepted, true);
    expect(match.reason, 'exact');
    expect(match.matchedTarget, 'Warten Sie bitte');
  });

  test('matchTranscriptToTargets accepts synonyms (contains)', () {
    final match = matchTranscriptToTargets(
      'Bitte warten jetzt',
      const ['Bitte warten', 'Warten Sie bitte'],
    );
    expect(match.accepted, true);
    expect(match.reason, 'contains');
    expect(match.matchedTarget, 'Bitte warten');
  });

  test('matchTranscriptToTargets rejects if no targets match', () {
    final match = matchTranscriptToTargets(
      'Guten Morgen',
      const ['Bitte warten', 'Warten Sie bitte'],
    );
    expect(match.accepted, false);
    expect(match.reason, 'rejected');
  });

  test('matchTranscriptToTargets accepts repeated/extra words via token match', () {
    final match = matchTranscriptToTargets(
      'γκαλά γκαλα',
      const ['Γάλα'],
    );
    expect(match.accepted, true);
  });
}
