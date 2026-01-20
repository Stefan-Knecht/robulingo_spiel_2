// ------------------------------------------------------------
// Ziel (Laien): Leiter-Rennen steuern (Züge Spieler/Rivale, Flaggen, Siege).
// Verbindung: robulingo_app.dart ruft applyPlayerStep/Win-Callbacks; UI rendert via `LadderTrack`.
// Tücken: Rival-Pacing hängt von Accuracy-Historie ab; Rückwärts-/Seitwärtszüge verhindern Doppelfehler-Schleifen.
// ------------------------------------------------------------
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../constants.dart';

class TrailPoint {
  const TrailPoint({required this.x, required this.lane});
  final int x;
  final int lane; // 0 = oben, 1 = unten
}

/// Tracks ladder positions, flags, and win counters for the HexaMatch mini-game.
class LadderState {
  int youX = 0;
  int youLane = 0; // 0 = oben, 1 = unten
  int rivalX = 0;
  int rivalLane = 1;
  int youProgress = 0;
  int rivalProgress = 0;
  int youLastDir = 0; // -1 = links, 0 = vertikal, 1 = rechts
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
  List<TrailPoint> youTrail = [const TrailPoint(x: 0, lane: 0)];
  List<TrailPoint> rivalTrail = [const TrailPoint(x: 0, lane: 1)];
}

enum MoveKind { forward, side, back }

class MoveEvent {
  MoveEvent({required this.isYou, required this.kind, this.isCorrect});
  final bool isYou;
  final MoveKind kind;
  final bool? isCorrect; // optional for callers that know correctness
}

/// Encapsulates ladder movement, rival pacing, and win animations.
class LadderController {
  LadderController({
    required this.onChanged,
    required this.onYouWin,
    required this.onRivalWin,
    required this.accuracyProvider,
    this.onMove,
    this.rivalSigma = 7.2,
    this.rivalCoupledProb = 0.9,
    this.rivalMaxProbBase = 0.4,
    this.rivalMaxProbSlope = 0.6,
    Random? random,
  }) : _rand = random ?? Random();

  final VoidCallback onChanged;
  final VoidCallback onYouWin;
  final VoidCallback onRivalWin;
  final void Function(MoveEvent event)? onMove;
  final List<bool> Function() accuracyProvider;
  final double rivalSigma;
  final double rivalCoupledProb;
  final double rivalMaxProbBase;
  final double rivalMaxProbSlope;
  final Random _rand;
  final LadderState state = LadderState();
  static const int _maxTrailPoints = 200;

  Timer? _youFlagTimer;
  Timer? _rivalFlagTimer;
  int _rivalMoveToken = 0;
  int _pendingRivalMoves = 0;
  bool _rivalMoveScheduled = false;
  bool? _lastPlayerCorrect; // letzter Spielerzug (für frühe Kopplung des Rivalen)
  bool? _lastRivalCorrect;

  void reset({bool clearWins = true}) {
    _rivalMoveToken++;
    _youFlagTimer?.cancel();
    _rivalFlagTimer?.cancel();
    _pendingRivalMoves = 0;
    _rivalMoveScheduled = false;
    state
      ..youX = 0
      ..youLane = 0
      ..rivalX = 0
      ..rivalLane = 1
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
      ..youTrail = [const TrailPoint(x: 0, lane: 0)]
      ..rivalTrail = [const TrailPoint(x: 0, lane: 1)]
      ..hasFlagAppeared = false;
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
    final prevYouPos = state.youX;
    final kind = _applyMove(correct, isYou: true);
    if (correct &&
        prevYouPos != trackLength - 1 &&
        state.youX == trackLength - 1) {
      _handleWinYou();
    }
    _lastPlayerCorrect = correct;
    if (onMove != null) {
      onMove!(MoveEvent(isYou: true, kind: kind, isCorrect: correct));
    }
    onChanged();
    _scheduleRivalMove();
  }

  void applyPlayerSteps(int moves) {
    for (int i = 0; i < moves; i++) {
      applyPlayerStep(true);
    }
  }

  MoveKind _applyMove(bool isCorrect, {required bool isYou}) {
    int x = isYou ? state.youX : state.rivalX;
    int lane = isYou ? state.youLane : state.rivalLane;
    int lastDir = isYou ? state.youLastDir : state.rivalLastDir;
    MoveKind kind;

    final desiredDir = isCorrect ? 1 : -1; // rechts bei richtig, links bei falsch
    final wouldBeBackstep = (lastDir == -desiredDir && lastDir != 0);

    if (wouldBeBackstep) {
      // Rückschritt verboten: vertikal ausweichen.
      lane = lane == 0 ? 1 : 0;
      lastDir = 0;
      kind = MoveKind.side;
    } else if (isCorrect) {
      if (isYou) {
        state.youProgress = (state.youProgress + 1).clamp(0, 1 << 30);
        x = state.youProgress % trackLength;
      } else {
        state.rivalProgress = (state.rivalProgress + 1).clamp(0, 1 << 30);
        x = state.rivalProgress % trackLength;
      }
      lastDir = 1;
      kind = MoveKind.forward;
    } else {
      if (isYou) {
        state.youProgress = (state.youProgress - 1).clamp(0, 1 << 30);
        x = state.youProgress % trackLength;
      } else {
        state.rivalProgress = (state.rivalProgress - 1).clamp(0, 1 << 30);
        x = state.rivalProgress % trackLength;
      }
      lastDir = -1;
      kind = MoveKind.back;
    }

    if (isYou) {
      state.youX = x;
      state.youLane = lane;
      state.youLastDir = lastDir;
      _recordTrail(isYou: true, x: x, lane: lane);
    } else {
      state.rivalX = x;
      state.rivalLane = lane;
      state.rivalLastDir = lastDir;
      _recordTrail(isYou: false, x: x, lane: lane);
    }
    return kind;
  }

  void _recordTrail({required bool isYou, required int x, required int lane}) {
    final list = isYou ? state.youTrail : state.rivalTrail;
    final newList = List<TrailPoint>.from(list)
      ..add(TrailPoint(x: x, lane: lane));
    if (newList.length > _maxTrailPoints) {
      newList.removeAt(0);
    }
    if (isYou) {
      state.youTrail = newList;
    } else {
      state.rivalTrail = newList;
    }
  }

  MoveKind _applyRivalStep() {
    final diff = state.rivalProgress - state.youProgress;
    final diffClamped = diff.clamp(-10, 10);
    final history = accuracyProvider();

    // In den ersten 10 Rivalen-Zügen koppeln wir an das Spieler-Ergebnis, danach greift
    // wieder die gauss-gewichtete Formel basierend auf Accuracy-Historie und Abstand.
    double pCorrect;
    if (history.length < 10 && _lastPlayerCorrect != null) {
      pCorrect = _lastPlayerCorrect!
          ? rivalCoupledProb
          : (1 - rivalCoupledProb);
    } else {
      final correctCount = history.where((e) => e).length;
      final acc = correctCount / history.length;
      final maxProb = rivalMaxProbBase + rivalMaxProbSlope * acc;
      pCorrect = maxProb *
          (exp(-(diffClamped * diffClamped) / (2 * rivalSigma * rivalSigma)));
    }
    if (pCorrect < 0) pCorrect = 0;
    if (pCorrect > 1) pCorrect = 1;

    final rivalCorrect = _rand.nextDouble() < pCorrect;
    _lastRivalCorrect = rivalCorrect;

    MoveKind kind;
    final desiredDir = rivalCorrect ? 1 : -1;
    final lastDir = state.rivalLastDir;
    final wouldBeBackstep = (lastDir == -desiredDir && lastDir != 0);
    if (rivalCorrect) {
      if (wouldBeBackstep) {
        state.rivalLane = state.rivalLane == 0 ? 1 : 0;
        state.rivalLastDir = 0;
        kind = MoveKind.side;
      } else {
        state.rivalProgress = (state.rivalProgress + 1).clamp(0, 1 << 30);
        state.rivalX = state.rivalProgress % trackLength;
        state.rivalLastDir = 1;
        if (state.rivalX == trackLength - 1) {
          _handleWinRival();
        }
        kind = MoveKind.forward;
      }
    } else {
      if (wouldBeBackstep) {
        state.rivalLane = state.rivalLane == 0 ? 1 : 0;
        state.rivalLastDir = 0;
        kind = MoveKind.side;
      } else {
        state.rivalProgress = (state.rivalProgress - 1).clamp(0, 1 << 30);
        state.rivalX = state.rivalProgress % trackLength;
        state.rivalLastDir = -1;
        kind = MoveKind.back;
      }
    }
    _recordTrail(isYou: false, x: state.rivalX, lane: state.rivalLane);
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
    final delayMs = 300 + _rand.nextInt(900); // 300..1200 ms
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (token != _rivalMoveToken) return;
      final kind = _applyRivalStep();
      if (token != _rivalMoveToken) return;
      _pendingRivalMoves = max(0, _pendingRivalMoves - 1);
      if (onMove != null) {
        onMove!(MoveEvent(isYou: false, kind: kind, isCorrect: _lastRivalCorrect));
      }
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
    state.youProgress = 0; // sofort zurücksetzen, damit Folgezüge korrekt starten
    onYouWin();
    Future.delayed(const Duration(milliseconds: 1200), () {
      _youFlagTimer?.cancel();
      state.youFlagAngle = 0.0;
      state
        ..youX = 0
        ..youProgress = 0
        ..youLane = 0
        ..youLastDir = 0
        ..youTrail = [const TrailPoint(x: 0, lane: 0)];
      onChanged();
    });
  }

  void _handleWinRival() {
    state.winsRival++;
    state.hasFlagAppeared = true;
    state.rivalFlagShowIndex = state.rivalFlagIndex;
    state.rivalFlagIndex = (state.rivalFlagIndex + 1) % 7;
    state.rivalFlagVisible = true;
    _rivalMoveToken++; // stop pending rival moves
    _pendingRivalMoves = 0;
    _rivalMoveScheduled = false;

    _rivalFlagTimer?.cancel();
    _rivalFlagTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      state.rivalFlagAngle = state.rivalFlagAngle == 0.0 ? 0.18 : -0.18;
      onChanged();
    });
    state.rivalProgress = 0;
    onRivalWin();
    Future.delayed(const Duration(milliseconds: 1200), () {
      _rivalFlagTimer?.cancel();
      state.rivalFlagAngle = 0.0;
      state
        ..rivalX = 0
        ..rivalProgress = 0
        ..rivalLane = 1
        ..rivalLastDir = 0
        ..rivalTrail = [const TrailPoint(x: 0, lane: 1)];
      onChanged();
    });
  }
}
