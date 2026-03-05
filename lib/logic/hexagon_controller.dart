// ------------------------------------------------------------
// Mountain duel controller used by the HexaMatch slot in RoboLingo.
// Keeps the existing public API and rival pacing model from HexagonController,
// but movement now follows two winding mountain tracks (index-based steps).
// ------------------------------------------------------------
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ladder_controller.dart' show MoveEvent, MoveKind;
import 'mountain_tracks.dart';

class HexTrailPoint {
  const HexTrailPoint({required this.index});
  final int index;
}

enum RivalMood { slacking, steady, hot }

class HexagonState {
  int youIndex = 0;
  int rivalIndex = 0;
  int youProgress = 0;
  int rivalProgress = 0;
  int youLastDir = 0; // -1 = back, 0 = neutral, 1 = forward
  int rivalLastDir = 0;
  bool youFlagVisible = false;
  bool rivalFlagVisible = false;
  double youFlagAngle = 0.0;
  double rivalFlagAngle = 0.0;
  int youFlagIndex = 0;
  int rivalFlagIndex = 0;
  int youFlagShowIndex = 0;
  int rivalFlagShowIndex = 0;
  int winsYou = 0;
  int winsRival = 0;
  bool hasFlagAppeared = false;
  List<HexTrailPoint> youTrail = const [HexTrailPoint(index: 0)];
  List<HexTrailPoint> rivalTrail = const [HexTrailPoint(index: 0)];
}

/// Encapsulates mountain-track movement, rival pacing, and win animations.
class HexagonController {
  HexagonController({
    required this.onChanged,
    required this.onYouWin,
    required this.onRivalWin,
    required this.accuracyProvider,
    this.startIndex = 0,
    this.onMove,
    this.rivalSigma = 7.2,
    this.rivalCoupledProb = 0.9,
    this.rivalMaxProbBase = 0.4,
    this.rivalMaxProbSlope = 0.6,
    this.rivalMoodOffsets = const [-0.06, 0.0, 0.08],
    this.rivalMoodStayProb = 0.85,
    this.rivalMoodMinMoves = 3,
    this.rivalIdleGraceDays = 2,
    this.rivalIdleBoostPerDay = 0.02,
    this.rivalIdleBoostMax = 0.10,
    this.rivalMinProbRatio = 0.8,
    Random? random,
  })  : _rand = random ?? Random(),
        _tracks = buildDefaultMountainTracks() {
    final int clampedStart =
        startIndex.clamp(0, _finishIndex > 0 ? _finishIndex - 1 : 0);
    _startOffset = clampedStart;
    assert(rivalMoodOffsets.length == 3);
    state
      ..youIndex = _startOffset
      ..rivalIndex = _startOffset
      ..youTrail = [HexTrailPoint(index: _startOffset)]
      ..rivalTrail = [HexTrailPoint(index: _startOffset)];
  }

  final VoidCallback onChanged;
  final VoidCallback onYouWin;
  final VoidCallback onRivalWin;
  final void Function(MoveEvent event)? onMove;
  final List<bool> Function() accuracyProvider;
  final int startIndex;
  final double rivalSigma;
  final double rivalCoupledProb;
  final double rivalMaxProbBase;
  final double rivalMaxProbSlope;
  final List<double> rivalMoodOffsets;
  final double rivalMoodStayProb;
  final int rivalMoodMinMoves;
  final int rivalIdleGraceDays;
  final double rivalIdleBoostPerDay;
  final double rivalIdleBoostMax;
  final double rivalMinProbRatio;
  final Random _rand;
  final MountainTracks _tracks;
  final HexagonState state = HexagonState();

  static const int _maxTrailPoints = 300;
  late final int _startOffset;

  int get _finishIndex => _tracks.left.length - 1;

  bool? _lastRivalCorrect;
  RivalMood _rivalMood = RivalMood.steady;
  int _rivalMoodMoves = 0;
  int _rivalIdleDays = 0;

  Timer? _youFlagTimer;
  Timer? _rivalFlagTimer;
  int _rivalMoveToken = 0;
  int _pendingRivalMoves = 0;
  bool _rivalMoveScheduled = false;
  bool? _lastPlayerCorrect;

  void setRivalIdleDays(int days) {
    _rivalIdleDays = min(max(days, 0), 365);
  }

  void reset({bool clearWins = true}) {
    _rivalMoveToken++;
    _youFlagTimer?.cancel();
    _rivalFlagTimer?.cancel();
    _pendingRivalMoves = 0;
    _rivalMoveScheduled = false;
    state
      ..youIndex = _startOffset
      ..rivalIndex = _startOffset
      ..youProgress = 0
      ..rivalProgress = 0
      ..youLastDir = 0
      ..rivalLastDir = 0
      ..youFlagVisible = false
      ..rivalFlagVisible = false
      ..youFlagAngle = 0.0
      ..rivalFlagAngle = 0.0
      ..youFlagShowIndex = 0
      ..rivalFlagShowIndex = 0
      ..youTrail = [HexTrailPoint(index: _startOffset)]
      ..rivalTrail = [HexTrailPoint(index: _startOffset)]
      ..hasFlagAppeared = false;
    _rivalMood = RivalMood.steady;
    _rivalMoodMoves = 0;
    _lastPlayerCorrect = null;
    _lastRivalCorrect = null;
    if (clearWins) {
      state
        ..winsYou = 0
        ..winsRival = 0;
    }
    onChanged();
  }

  void dispose() {
    _rivalMoveToken++;
    _youFlagTimer?.cancel();
    _rivalFlagTimer?.cancel();
    _pendingRivalMoves = 0;
    _rivalMoveScheduled = false;
  }

  void setWins({required int you, required int rival}) {
    state
      ..winsYou = you
      ..winsRival = rival;
    onChanged();
  }

  void applyPlayerStep(bool correct) {
    final kind = _applyMove(correct, isYou: true);
    _lastPlayerCorrect = correct;
    onMove?.call(MoveEvent(isYou: true, kind: kind, isCorrect: correct));
    onChanged();
    _scheduleRivalMove();
  }

  void applyPlayerSteps(int moves) {
    for (int i = 0; i < moves; i++) {
      applyPlayerStep(true);
    }
  }

  bool tryRivalStep({double probability = 0.5}) {
    final p = probability.clamp(0.0, 1.0);
    if (_rand.nextDouble() >= p) return false;
    final kind = _applyRivalStep();
    onMove?.call(
      MoveEvent(isYou: false, kind: kind, isCorrect: _lastRivalCorrect),
    );
    onChanged();
    return true;
  }

  /// Advances both player and rival forward by the same number of steps,
  /// without using the probabilistic rival scheduler.
  void applyCoupledForwardSteps(
    int steps, {
    bool emitPlayerMoveEvents = true,
    bool emitRivalMoveEvents = false,
  }) {
    if (steps <= 0) return;
    _rivalMoveToken++;
    _pendingRivalMoves = 0;
    _rivalMoveScheduled = false;

    for (int i = 0; i < steps; i++) {
      final kindYou = _applyMove(true, isYou: true);
      if (emitPlayerMoveEvents) {
        onMove?.call(MoveEvent(isYou: true, kind: kindYou, isCorrect: true));
      }
      final kindRival = _applyMove(true, isYou: false);
      if (emitRivalMoveEvents) {
        onMove?.call(MoveEvent(isYou: false, kind: kindRival, isCorrect: true));
      }
    }
    onChanged();
  }

  MoveKind _applyMove(bool isCorrect, {required bool isYou}) {
    final current = isYou ? state.youIndex : state.rivalIndex;
    int next = current;
    MoveKind kind = MoveKind.side;

    if (isCorrect) {
      if (current < _finishIndex) {
        next = current + 1;
        kind = MoveKind.forward;
      }
    } else {
      if (current > 0) {
        next = current - 1;
        kind = MoveKind.back;
      }
    }

    final dir = next > current
        ? 1
        : next < current
            ? -1
            : 0;

    if (isYou) {
      state
        ..youProgress = next
        ..youIndex = next
        ..youLastDir = dir;
      _recordTrail(isYou: true, index: next);
      if (next >= _finishIndex) {
        _handleWinYou();
      }
    } else {
      state
        ..rivalProgress = next
        ..rivalIndex = next
        ..rivalLastDir = dir;
      _recordTrail(isYou: false, index: next);
      if (next >= _finishIndex) {
        _handleWinRival();
      }
    }

    return kind;
  }

  void _recordTrail({required bool isYou, required int index}) {
    final list = isYou ? state.youTrail : state.rivalTrail;
    final newList = List<HexTrailPoint>.from(list)
      ..add(HexTrailPoint(index: index));
    if (newList.length > _maxTrailPoints) {
      newList.removeAt(0);
    }
    if (isYou) {
      state.youTrail = newList;
    } else {
      state.rivalTrail = newList;
    }
  }

  double _idleBoost() {
    final extraDays = max(0, _rivalIdleDays - rivalIdleGraceDays);
    return min(rivalIdleBoostMax, extraDays * rivalIdleBoostPerDay);
  }

  void _advanceRivalMood() {
    _rivalMoodMoves++;
    if (_rivalMoodMoves < rivalMoodMinMoves) return;
    if (_rand.nextDouble() < rivalMoodStayProb) return;
    _rivalMoodMoves = 0;

    final upBias = (0.5 + _idleBoost()).clamp(0.05, 0.95);
    switch (_rivalMood) {
      case RivalMood.slacking:
        _rivalMood = RivalMood.steady;
        break;
      case RivalMood.steady:
        _rivalMood =
            _rand.nextDouble() < upBias ? RivalMood.hot : RivalMood.slacking;
        break;
      case RivalMood.hot:
        _rivalMood = RivalMood.steady;
        break;
    }
  }

  MoveKind _applyRivalStep() {
    _advanceRivalMood();
    final diff = state.rivalProgress - state.youProgress;
    final diffClamped = diff.clamp(-20, 20).toDouble();
    final history = accuracyProvider();
    final catchup = 1 / (1 + exp(diffClamped / rivalSigma));
    final moodOffset = rivalMoodOffsets[_rivalMood.index];
    final idleBoost = _idleBoost();
    final minProbRatio = rivalMinProbRatio.clamp(0.0, 1.0);

    double pCorrect;
    if (history.length < 10 && _lastPlayerCorrect != null) {
      final base =
          _lastPlayerCorrect! ? rivalCoupledProb : (1 - rivalCoupledProb);
      final boostedBase = (base + moodOffset + idleBoost).clamp(0.0, 1.0);
      final minProb = (boostedBase * minProbRatio).clamp(0.0, boostedBase);
      pCorrect = minProb + (boostedBase - minProb) * catchup;
    } else {
      final correctCount = history.where((e) => e).length;
      final acc = history.isEmpty ? 0.0 : correctCount / history.length;
      final baseMax =
          (rivalMaxProbBase + rivalMaxProbSlope * acc).clamp(0.0, 1.0);
      final maxProb = (baseMax + moodOffset + idleBoost).clamp(0.0, 1.0);
      final minProb = (maxProb * minProbRatio).clamp(0.0, maxProb);
      pCorrect = minProb + (maxProb - minProb) * catchup;
    }

    final rivalCorrect = _rand.nextDouble() < pCorrect;
    _lastRivalCorrect = rivalCorrect;
    return _applyMove(rivalCorrect, isYou: false);
  }

  void _scheduleRivalMove() {
    _pendingRivalMoves++;
    if (_rivalMoveScheduled) return;
    _scheduleNextRivalMove();
  }

  void _scheduleNextRivalMove() {
    if (_pendingRivalMoves <= 0) {
      _rivalMoveScheduled = false;
      return;
    }
    _rivalMoveScheduled = true;
    final token = ++_rivalMoveToken;
    final delayMs = 300 + _rand.nextInt(900);
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (token != _rivalMoveToken) return;
      final kind = _applyRivalStep();
      if (token != _rivalMoveToken) return;
      _pendingRivalMoves = max(0, _pendingRivalMoves - 1);
      onMove?.call(
        MoveEvent(isYou: false, kind: kind, isCorrect: _lastRivalCorrect),
      );
      onChanged();
      _scheduleNextRivalMove();
    });
  }

  void _handleWinYou() {
    state.winsYou++;
    state.hasFlagAppeared = true;
    state.youFlagShowIndex = state.youFlagIndex;
    state.youFlagIndex = (state.youFlagIndex + 1) % 7;
    state
      ..youFlagVisible = true
      ..rivalFlagVisible = false;

    _rivalMoveToken++;
    _pendingRivalMoves = 0;
    _rivalMoveScheduled = false;

    _youFlagTimer?.cancel();
    _youFlagTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      state.youFlagAngle = state.youFlagAngle == 0.0 ? 0.18 : -0.18;
      onChanged();
    });
    onYouWin();

    Future.delayed(const Duration(milliseconds: 1200), () {
      _youFlagTimer?.cancel();
      state
        ..youFlagAngle = 0.0
        ..youFlagVisible = false
        ..rivalFlagVisible = false
        ..youIndex = _startOffset
        ..rivalIndex = _startOffset
        ..youProgress = _startOffset
        ..rivalProgress = _startOffset
        ..youLastDir = 0
        ..rivalLastDir = 0
        ..youTrail = [HexTrailPoint(index: _startOffset)]
        ..rivalTrail = [HexTrailPoint(index: _startOffset)];
      onChanged();
    });
  }

  void _handleWinRival() {
    state.winsRival++;
    state.hasFlagAppeared = true;
    state.rivalFlagShowIndex = state.rivalFlagIndex;
    state.rivalFlagIndex = (state.rivalFlagIndex + 1) % 7;
    state
      ..rivalFlagVisible = true
      ..youFlagVisible = false;

    _rivalMoveToken++;
    _pendingRivalMoves = 0;
    _rivalMoveScheduled = false;

    _rivalFlagTimer?.cancel();
    _rivalFlagTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      state.rivalFlagAngle = state.rivalFlagAngle == 0.0 ? 0.18 : -0.18;
      onChanged();
    });
    onRivalWin();

    Future.delayed(const Duration(milliseconds: 1200), () {
      _rivalFlagTimer?.cancel();
      state
        ..rivalFlagAngle = 0.0
        ..youFlagVisible = false
        ..rivalFlagVisible = false
        ..youIndex = _startOffset
        ..rivalIndex = _startOffset
        ..youProgress = _startOffset
        ..rivalProgress = _startOffset
        ..youLastDir = 0
        ..rivalLastDir = 0
        ..youTrail = [HexTrailPoint(index: _startOffset)]
        ..rivalTrail = [HexTrailPoint(index: _startOffset)];
      onChanged();
    });
  }
}
