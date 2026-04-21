import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/ui/start_curriculum_selector.dart';

Finder _buttonForAsset(String assetName) {
  final imageFinder = find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == assetName,
  );
  return find.ancestor(of: imageFinder, matching: find.byType(ElevatedButton));
}

void main() {
  testWidgets('auto-selects the cross module after four seconds of inactivity',
      (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: StartCurriculumSelector(
          onSelect: (fileName) => selected = fileName,
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 3));
    expect(selected, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(selected, 'start_curriculum_a.json');
  });

  testWidgets('manual module selection cancels the cross auto-select timer',
      (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: StartCurriculumSelector(
          onSelect: (fileName) => selected = fileName,
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.tap(_buttonForAsset('assets/icons/toddler.webp'));
    await tester.pump();

    expect(selected, 'start_curriculum_b.json');

    await tester.pump(const Duration(seconds: 3));
    expect(selected, 'start_curriculum_b.json');
  });
}
