import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/logic/hexagon_controller.dart';

void main() {
  test('rival can get an early bonus step into the lead', () {
    fakeAsync((async) {
      final history = <bool>[];
      final controller = HexagonController(
        onChanged: () {},
        onYouWin: () {},
        onRivalWin: () {},
        accuracyProvider: () => history,
        random: _ScriptedRandom(doubles: [0.0, 0.0], ints: [0]),
      );

      history.add(true);
      controller.applyPlayerStep(true);
      async.elapse(const Duration(milliseconds: 1300));

      expect(controller.state.youProgress, 1);
      expect(controller.state.rivalProgress, 2);
    });
  });

  test('early rival bonus fades out after the opening window', () {
    fakeAsync((async) {
      final history = List<bool>.filled(12, true);
      final controller = HexagonController(
        onChanged: () {},
        onYouWin: () {},
        onRivalWin: () {},
        accuracyProvider: () => history,
        random: _ScriptedRandom(doubles: [0.0, 0.0], ints: [0]),
      );

      controller.applyPlayerStep(true);
      async.elapse(const Duration(milliseconds: 1300));

      expect(controller.state.youProgress, 1);
      expect(controller.state.rivalProgress, 1);
    });
  });
}

class _ScriptedRandom implements Random {
  _ScriptedRandom({
    required List<double> doubles,
    required List<int> ints,
  })  : _doubles = List<double>.from(doubles),
        _ints = List<int>.from(ints);

  final List<double> _doubles;
  final List<int> _ints;

  @override
  bool nextBool() => nextDouble() < 0.5;

  @override
  double nextDouble() {
    if (_doubles.isEmpty) return 0.0;
    return _doubles.removeAt(0);
  }

  @override
  int nextInt(int max) {
    if (_ints.isEmpty) return 0;
    return _ints.removeAt(0).clamp(0, max - 1);
  }
}
