import 'dart:math';

/// Mini-Monte-Carlo, um Gewinnwahrscheinlichkeiten für das Leiter-Rennen
/// über N Spielerzüge zu schätzen. Keine Flutter-Abhängigkeiten, nur Kernlogik.

const int trackLength = 12; // in Sync mit lib/constants.dart
const double rivalSigmaDefault = 14.0; // auf ~50/50 bei Spieler-Acc ~0.75 getrimmt
const double coupledProbDefault = 0.8; // frühe Kopplung (erste 10 Rivalen-Züge)

class SimState {
  int youX = 0;
  int youLane = 0;
  int rivalX = 0;
  int rivalLane = 1;
  int youProgress = 0;
  int rivalProgress = 0;
  bool youLastSide = false;
  bool youLastBack = false;
  bool rivalLastSide = false;
  bool? lastPlayerCorrect;
  final List<bool> history = [];
  int winsYou = 0;
  int winsRival = 0;
}

bool _chance(Random rand, double p) => rand.nextDouble() < p;

void _applyPlayerMove(SimState s, {required bool correct}) {
  final prevX = s.youX;
  int x = s.youX;
  int lane = s.youLane;
  bool lastSide = s.youLastSide;
  bool lastBack = s.youLastBack;

  if (correct) {
    s.youProgress = (s.youProgress + 1).clamp(0, 1 << 30);
    x = s.youProgress % trackLength;
    lastSide = false;
    lastBack = false;
  } else {
    if (lastBack) {
      lane = lane == 0 ? 1 : 0;
      lastSide = true;
      lastBack = false;
    } else if (lastSide) {
      s.youProgress = (s.youProgress - 1).clamp(0, 1 << 30);
      x = s.youProgress % trackLength;
      lastSide = false;
      lastBack = true;
    } else {
      lane = lane == 0 ? 1 : 0;
      lastSide = true;
      lastBack = false;
    }
  }

  s.youX = x;
  s.youLane = lane;
  s.youLastSide = lastSide;
  s.youLastBack = lastBack;

  if (correct && prevX != trackLength - 1 && s.youX == trackLength - 1) {
    // handle win (Flags/Animation entfallen)
    s.winsYou++;
    s.youProgress = 0;
    s.youX = 0;
    s.youLane = 0;
    s.youLastSide = false;
    s.youLastBack = false;
  }
}

void _applyRivalMove(SimState s, Random rand, {required double rivalSigma, required double coupledProb}) {
  final diff = s.rivalProgress - s.youProgress;
  final diffClamped = diff.clamp(-10, 10);

  double pCorrect;
  if (s.history.length < 10 && s.lastPlayerCorrect != null) {
    pCorrect = s.lastPlayerCorrect! ? coupledProb : (1 - coupledProb);
  } else {
    final correctCount = s.history.where((e) => e).length;
    final acc = s.history.isEmpty ? 0.0 : correctCount / s.history.length;
    final maxProb = 0.35 + 0.6 * acc;
    pCorrect = maxProb *
        (exp(-(diffClamped * diffClamped) / (2 * rivalSigma * rivalSigma)));
  }
  if (pCorrect < 0) pCorrect = 0;
  if (pCorrect > 1) pCorrect = 1;

  final rivalCorrect = _chance(rand, pCorrect);
  if (rivalCorrect) {
    s.rivalProgress = (s.rivalProgress + 1).clamp(0, 1 << 30);
    s.rivalX = s.rivalProgress % trackLength;
    s.rivalLastSide = false;
    if (s.rivalX == trackLength - 1) {
      s.winsRival++;
      s.rivalProgress = 0;
      s.rivalX = 0;
      s.rivalLane = 1;
      s.rivalLastSide = false;
    }
  } else {
    if (s.rivalLastSide) {
      s.rivalProgress = (s.rivalProgress - 1).clamp(0, 1 << 30);
      s.rivalX = s.rivalProgress % trackLength;
      s.rivalLastSide = false;
    } else {
      s.rivalLane = s.rivalLane == 0 ? 1 : 0;
      s.rivalLastSide = true;
    }
  }
}

SimState simulateRun({
  required Random rand,
  required double playerAccuracy,
  required double rivalSigma,
  required double coupledProb,
  int steps = 100,
}) {
  final state = SimState();
  for (int i = 0; i < steps; i++) {
    final correct = _chance(rand, playerAccuracy);
    state.history.add(correct);
    _applyPlayerMove(state, correct: correct);
    state.lastPlayerCorrect = correct;
    _applyRivalMove(state, rand, rivalSigma: rivalSigma, coupledProb: coupledProb);
  }
  return state;
}

class Config {
  Config({
    required this.accs,
    required this.runs,
    required this.steps,
    required this.seed,
    required this.rivalSigma,
    required this.coupledProb,
  });
  final List<double> accs;
  final int runs;
  final int steps;
  final int seed;
  final double rivalSigma;
  final double coupledProb;
}

Config parseArgs(List<String> args) {
  final accs = <double>[];
  int runs = 5000;
  int steps = 100;
  int? seed;
  double? rivalSigma;
  double? coupledProb;

  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--acc':
      case '-a':
        if (i + 1 >= args.length) throw ArgumentError('Fehlender Wert für $a');
        accs.addAll(args[++i].split(',').where((e) => e.trim().isNotEmpty).map((e) => double.parse(e)));
        break;
      case '--runs':
      case '-r':
        if (i + 1 >= args.length) throw ArgumentError('Fehlender Wert für $a');
        runs = int.parse(args[++i]);
        break;
      case '--steps':
      case '-s':
        if (i + 1 >= args.length) throw ArgumentError('Fehlender Wert für $a');
        steps = int.parse(args[++i]);
        break;
      case '--seed':
        if (i + 1 >= args.length) throw ArgumentError('Fehlender Wert für $a');
        seed = int.parse(args[++i]);
        break;
      case '--sigma':
        if (i + 1 >= args.length) throw ArgumentError('Fehlender Wert für $a');
        rivalSigma = double.parse(args[++i]);
        break;
      case '--coupled':
        if (i + 1 >= args.length) throw ArgumentError('Fehlender Wert für $a');
        coupledProb = double.parse(args[++i]);
        break;
      default:
        throw ArgumentError('Unbekanntes Argument: $a');
    }
  }

  if (accs.isEmpty) {
    accs.addAll([0.5, 0.6, 0.7, 0.8, 0.9]);
  }
  seed ??= DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  return Config(
    accs: accs,
    runs: runs,
    steps: steps,
    seed: seed,
    rivalSigma: rivalSigma ?? rivalSigmaDefault,
    coupledProb: coupledProb ?? coupledProbDefault,
  );
}

void main(List<String> args) {
  late Config cfg;
  try {
    cfg = parseArgs(args);
  } catch (e) {
    print('Argument-Fehler: $e');
    print(
        'Usage: dart tools/ladder_sim.dart [--acc 0.6,0.7] [--runs 5000] [--steps 100] [--seed 42] [--sigma 4.0] [--coupled 0.8]');
    return;
  }

  print('Seed: ${cfg.seed}');
  print('Runs pro Accuracy: ${cfg.runs}, Schritte pro Run: ${cfg.steps}');
  print('rivalSigma: ${cfg.rivalSigma}, coupledProb: ${cfg.coupledProb}');
  final master = Random(cfg.seed);

  for (final acc in cfg.accs) {
    int winsYou = 0;
    int winsRival = 0;
    for (int i = 0; i < cfg.runs; i++) {
      final runSeed = master.nextInt(1 << 30);
      final state = simulateRun(
        rand: Random(runSeed),
        playerAccuracy: acc,
        rivalSigma: cfg.rivalSigma,
        coupledProb: cfg.coupledProb,
        steps: cfg.steps,
      );
      winsYou += state.winsYou;
      winsRival += state.winsRival;
    }
    final totalWins = winsYou + winsRival;
    final youRate = totalWins == 0 ? 0.0 : winsYou / totalWins;
    print(
        'acc=${acc.toStringAsFixed(2)} -> you_wins=$winsYou, rival_wins=$winsRival, win_rate=${youRate.toStringAsFixed(3)}');
  }
}
