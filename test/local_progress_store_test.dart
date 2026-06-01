import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/logic/local_progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saves and loads a local next-cursor progress snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalProgressStore();
    final updatedAt = DateTime.utc(2026, 1, 1, 12);

    await store.save(
      LocalProgressSnapshot(
        userId: 'learner-1',
        startKey: 'dailywords.json',
        cursor: 7,
        uuid: 'item-8',
        updatedAt: updatedAt,
        source: 'comprehension_answer',
      ),
    );

    final loaded = await store.load(
      userId: 'learner-1',
      startKey: 'dailywords.json',
    );

    expect(loaded, isNotNull);
    expect(loaded!.cursor, 7);
    expect(loaded.uuid, 'item-8');
    expect(loaded.updatedAt, updatedAt);
    expect(loaded.source, 'comprehension_answer');
  });
}
