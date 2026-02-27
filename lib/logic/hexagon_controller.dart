// ------------------------------------------------------------
// Ziel (Laien): Hexagon-Rennen steuern – analog zu LadderController, aber auf einem 10x3 Hex-Gitter.
// Strategie: Gleiche API (applyPlayerStep, Wins, Flags, Trails) nutzen, aber Positionen als Hex-Pfad-Indizes verwalten.
// Tücken: Backsteps werden wie beim Ladder seitlich neutralisiert (kein Doppel-Back), Rival-Pacing kopiert das Ladder-Modell.
// Nutzung: Statt LadderController mit gleichen Callbacks instanziieren und den State an HexagonTrack (ui/hexagon_track.dart) binden.
// ------------------------------------------------------------
import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'hexagon_grid.dart';
import 'ladder_controller.dart' show MoveEvent, MoveKind;

class HexTrailPoint {
  const HexTrailPoint({required this.index});
  final int index;
}

enum RivalMood { slacking, steady, hot }

/// Tracks hex positions, flags, and win counters for the hex-grid race.
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

/// Encapsulates hex-grid movement, rival pacing, and win animations.
class HexagonController {
  HexagonController({
    required this.onChanged,
    required this.onYouWin,
    required this.onRivalWin,
    required this.accuracyProvider,
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
        _grid = buildHexGrid() {
    _youStartOffset = _grid.nodeIndexFor(0, 0, 4) ?? 0;
    _rivalStartOffset = _grid.nodeIndexFor(2, 0, 5) ?? 0;
    state
      ..youIndex = _youStartOffset
      ..rivalIndex = _rivalStartOffset
      ..youTrail = [HexTrailPoint(index: _youStartOffset)]
      ..rivalTrail = [HexTrailPoint(index: _rivalStartOffset)];
    assert(rivalMoodOffsets.length == 3);
  }

  final VoidCallback onChanged;
  final VoidCallback onYouWin;
  final VoidCallback onRivalWin;
  final void Function(MoveEvent event)? onMove;
  final List<bool> Function() accuracyProvider;
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
  final HexGridData _grid;
  final HexagonState state = HexagonState();
  late final int _youStartOffset;
  late final int _rivalStartOffset;
  Offset? _youLastDelta;
  Offset? _rivalLastDelta;
  bool? _lastRivalCorrect;
  RivalMood _rivalMood = RivalMood.steady;
  int _rivalMoodMoves = 0;
  int _rivalIdleDays = 0;
  static const int _maxTrailPoints = 200;

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
      ..youIndex = _youStartOffset
      ..rivalIndex = _rivalStartOffset
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
      ..youTrail = [HexTrailPoint(index: _youStartOffset)]
      ..rivalTrail = [HexTrailPoint(index: _rivalStartOffset)]
      ..hasFlagAppeared = false;
    _rivalMood = RivalMood.steady;
    _rivalMoodMoves = 0;
    if (clearWins) {
      state
        ..winsYou = 0
        ..winsRival = 0;
    }
    _youLastDelta = null;
    _rivalLastDelta = null;
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
        MoveEvent(isYou: false, kind: kind, isCorrect: _lastRivalCorrect));
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
    // Cancel any pending scheduled rival moves so we don't get extra drift.
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
    final int currentIndex = isYou ? state.youIndex : state.rivalIndex;
    final Offset currentPos = _grid.nodes[currentIndex];
    final Offset? lastDelta = isYou ? _youLastDelta : _rivalLastDelta;

    int progress = isYou ? state.youProgress : state.rivalProgress;
    int nextIndex = currentIndex;
    MoveKind kind = MoveKind.side;
    Offset delta = Offset.zero;

    if (isCorrect) {
      progress = _incrementProgress(progress);
      final _MoveChoice choice =
          _chooseForwardWithFallback(currentIndex, lastDelta);
      nextIndex = choice.index;
      delta = choice.delta;
      kind = choice.kind;
    } else {
      progress = _decrementProgress(progress);
      final _MoveChoice choice = _chooseVerticalOrLeft(currentIndex, lastDelta);
      nextIndex = choice.index;
      delta = choice.delta;
      kind = choice.kind;
    }

    if (nextIndex < 0 || nextIndex >= _grid.nodes.length) {
      nextIndex = currentIndex;
      kind = MoveKind.side;
    }

    delta = _grid.nodes[nextIndex] - currentPos;

    if (isYou) {
      state.youProgress = progress;
      state.youIndex = nextIndex;
      state.youLastDir = _dirFromDelta(delta);
      _youLastDelta = delta;
      _recordTrail(isYou: true, index: nextIndex);
      if (_grid.finishNodes.contains(nextIndex)) {
        _handleWinYou();
      }
    } else {
      state.rivalProgress = progress;
      state.rivalIndex = nextIndex;
      state.rivalLastDir = _dirFromDelta(delta);
      _rivalLastDelta = delta;
      _recordTrail(isYou: false, index: nextIndex);
      if (_grid.finishNodes.contains(nextIndex)) {
        _handleWinRival();
      }
    }
    return kind;
  }

  _MoveChoice _chooseForwardWithFallback(int currentIndex, Offset? lastDelta) {
    final neighbors = _grid.adjacency[currentIndex] ?? const <int>{};
    int? bestRight;
    double bestDx = double.negativeInfinity;
    for (final n in neighbors) {
      final delta = _grid.nodes[n] - _grid.nodes[currentIndex];
      if (_isInverse(lastDelta, delta)) continue;
      if (delta.dx > 1e-6 && delta.dx > bestDx) {
        bestDx = delta.dx;
        bestRight = n;
      }
    }
    if (bestRight != null) {
      final delta = _grid.nodes[bestRight] - _grid.nodes[currentIndex];
      return _MoveChoice(
          index: bestRight, kind: MoveKind.forward, delta: delta);
    }

    bool prefersVertical(Offset candidate, Offset current) {
      final candidateBack = candidate.dx < -1e-6;
      final currentBack = current.dx < -1e-6;
      if (candidateBack != currentBack) return !candidateBack;
      final candAbsDx = candidate.dx.abs();
      final currAbsDx = current.dx.abs();
      if ((candAbsDx - currAbsDx).abs() > 1e-6) {
        return candAbsDx < currAbsDx;
      }
      return candidate.dx > current.dx;
    }

    // Fallback: vertical, mit bevorzugter "gerader" Richtung.
    _MoveChoice? bestVertical;
    _MoveChoice? bestVerticalInverse;
    for (final n in neighbors) {
      final delta = _grid.nodes[n] - _grid.nodes[currentIndex];
      if (delta.dy.abs() <= 1e-6) continue;
      final choice = _MoveChoice(index: n, kind: MoveKind.side, delta: delta);
      if (_isInverse(lastDelta, delta)) {
        if (bestVerticalInverse == null ||
            prefersVertical(delta, bestVerticalInverse.delta)) {
          bestVerticalInverse = choice;
        }
      } else {
        if (bestVertical == null ||
            prefersVertical(delta, bestVertical.delta)) {
          bestVertical = choice;
        }
      }
    }
    if (bestVertical != null) return bestVertical;
    if (bestVerticalInverse != null) return bestVerticalInverse;

    // Fallback: beliebiger Nachbar (z.B. rückwärts), solange nicht inverse.
    for (final n in neighbors) {
      final delta = _grid.nodes[n] - _grid.nodes[currentIndex];
      if (_isInverse(lastDelta, delta)) continue;
      final kind = delta.dx < -1e-6 ? MoveKind.back : MoveKind.side;
      return _MoveChoice(index: n, kind: kind, delta: delta);
    }

    return _MoveChoice(
        index: currentIndex, kind: MoveKind.side, delta: Offset.zero);
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

  _MoveChoice _chooseVerticalOrLeft(int currentIndex, Offset? lastDelta) {
    final neighbors = _grid.adjacency[currentIndex] ?? const <int>{};
    _MoveChoice? bestVertical;
    for (final n in neighbors) {
      final delta = _grid.nodes[n] - _grid.nodes[currentIndex];
      if (delta.dy.abs() > 1e-6) {
        final bool lastWasVertical =
            lastDelta != null && lastDelta.dy.abs() > 1e-6;
        final bool wouldReverseVertical =
            lastWasVertical && (delta.dy.sign == -lastDelta.dy.sign);
        if (wouldReverseVertical) continue;
        // Nur "nahezu vertikale" Nachbarn zulassen (seitliche Abweichung klein).
        if (delta.dx.abs() > delta.dy.abs() * 0.3) continue;
        // prefer smallest |dx|, then larger |dy|
        if (bestVertical == null ||
            delta.dx.abs() < bestVertical.delta.dx.abs() ||
            (delta.dx.abs() == bestVertical.delta.dx.abs() &&
                delta.dy.abs() > bestVertical.delta.dy.abs())) {
          bestVertical =
              _MoveChoice(index: n, kind: MoveKind.side, delta: delta);
        }
      }
    }
    if (bestVertical != null) return bestVertical;

    int? leftIdx;
    Offset? leftDelta;
    double bestDx = 0.0;
    for (final n in neighbors) {
      final delta = _grid.nodes[n] - _grid.nodes[currentIndex];
      if (delta.dx < -1e-6 && delta.dx < bestDx) {
        bestDx = delta.dx;
        leftIdx = n;
        leftDelta = delta;
      }
    }
    if (leftIdx != null && leftDelta != null) {
      return _MoveChoice(index: leftIdx, kind: MoveKind.back, delta: leftDelta);
    }

    return _MoveChoice(
        index: currentIndex, kind: MoveKind.side, delta: Offset.zero);
  }

  bool _isInverse(Offset? last, Offset candidate) {
    if (last == null) return false;
    if (last.distance < 1e-9 || candidate.distance < 1e-9) return false;
    final dot = last.dx * candidate.dx + last.dy * candidate.dy;
    final cos = dot / (last.distance * candidate.distance);
    return cos < -0.8;
  }

  int _dirFromDelta(Offset delta) {
    if (delta.dx > 1e-6) return 1;
    if (delta.dx < -1e-6) return -1;
    return 0;
  }

  int _incrementProgress(int progress) => progress + 1;

  int _decrementProgress(int progress) => max(0, progress - 1);

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
    final kind = _applyMove(rivalCorrect, isYou: false);
    return kind;
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
          MoveEvent(isYou: false, kind: kind, isCorrect: _lastRivalCorrect));
      onChanged();
      _scheduleNextRivalMove();
    });
  }

  void _handleWinYou() {
    state.winsYou++;
    state.hasFlagAppeared = true;
    state.youFlagShowIndex = state.youFlagIndex;
    state.youFlagIndex = (state.youFlagIndex + 1) % 7;
    state.youFlagVisible = true;

    _youFlagTimer?.cancel();
    _youFlagTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      state.youFlagAngle = state.youFlagAngle == 0.0 ? 0.18 : -0.18;
      onChanged();
    });
    onYouWin();
    Future.delayed(const Duration(milliseconds: 1200), () {
      _youFlagTimer?.cancel();
      state.youFlagAngle = 0.0;
      state
        ..youIndex = _youStartOffset
        ..youLastDir = 0
        ..youTrail = [HexTrailPoint(index: _youStartOffset)];
      onChanged();
    });
  }

  void _handleWinRival() {
    state.winsRival++;
    state.hasFlagAppeared = true;
    state.rivalFlagShowIndex = state.rivalFlagIndex;
    state.rivalFlagIndex = (state.rivalFlagIndex + 1) % 7;
    state.rivalFlagVisible = true;
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
      state.rivalFlagAngle = 0.0;
      state
        ..rivalIndex = _rivalStartOffset
        ..rivalLastDir = 0
        ..rivalTrail = [HexTrailPoint(index: _rivalStartOffset)];
      onChanged();
    });
  }
}

class _MoveChoice {
  _MoveChoice({
    required this.index,
    required this.kind,
    required this.delta,
  });
  final int index;
  final MoveKind kind;
  final Offset delta;
}
