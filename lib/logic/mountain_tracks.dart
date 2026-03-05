import 'dart:math';

import 'package:flutter/material.dart';

const int defaultMountainTrackSteps = 150;

class MountainTracks {
  const MountainTracks({required this.left, required this.right});

  final List<Offset> left;
  final List<Offset> right;
}

/// Builds two shoulder tracks in normalized (0..1) coordinates.
MountainTracks buildDefaultMountainTracks({
  int stepCount = defaultMountainTrackSteps,
}) {
  assert(stepCount >= 2);

  const leftControl = <Offset>[
    Offset(0.17, 0.89),
    Offset(0.27, 0.85),
    Offset(0.19, 0.80),
    Offset(0.29, 0.74),
    Offset(0.18, 0.68),
    Offset(0.31, 0.62),
    Offset(0.21, 0.56),
    Offset(0.35, 0.49),
    Offset(0.24, 0.43),
    Offset(0.39, 0.36),
    Offset(0.29, 0.30),
    Offset(0.44, 0.23),
    Offset(0.48, 0.17),
  ];

  const rightControl = <Offset>[
    Offset(0.83, 0.89),
    Offset(0.73, 0.85),
    Offset(0.81, 0.80),
    Offset(0.71, 0.74),
    Offset(0.82, 0.68),
    Offset(0.69, 0.62),
    Offset(0.79, 0.56),
    Offset(0.65, 0.49),
    Offset(0.76, 0.43),
    Offset(0.61, 0.36),
    Offset(0.71, 0.30),
    Offset(0.56, 0.23),
    Offset(0.52, 0.17),
  ];

  final leftBase = _sampleTrack(leftControl, stepCount: stepCount);
  final rightBase = _sampleTrack(rightControl, stepCount: stepCount);

  return MountainTracks(
    left: _applyIrregularWobble(
      leftBase,
      seed: 0.31,
      xMin: 0.09,
      xMax: 0.52,
      isLeft: true,
    ),
    right: _applyIrregularWobble(
      rightBase,
      seed: 0.67,
      xMin: 0.48,
      xMax: 0.91,
      isLeft: false,
    ),
  );
}

List<Offset> _sampleTrack(List<Offset> controls, {required int stepCount}) {
  if (controls.length < 2) {
    return List<Offset>.filled(
      stepCount,
      controls.isEmpty ? Offset.zero : controls.first,
    );
  }

  final dense = _catmullRomDensePolyline(controls, samplesPerSegment: 96);
  final cumulative = _cumulativeLengths(dense);
  if (cumulative.isEmpty || cumulative.last <= 1e-9) {
    return List<Offset>.filled(stepCount, controls.first);
  }

  final totalLength = cumulative.last;
  final weights = _segmentSpacingWeights(stepCount);
  final weightSum = weights.fold<double>(0.0, (a, b) => a + b);

  final targets = <double>[0.0];
  double d = 0.0;
  for (final w in weights) {
    d += (w / weightSum) * totalLength;
    targets.add(d);
  }
  targets[targets.length - 1] = totalLength;

  return targets
      .map((target) => _pointAtDistance(dense, cumulative, target))
      .toList();
}

List<double> _segmentSpacingWeights(int stepCount) {
  if (stepCount <= 1) return const <double>[];
  final baseEnd = max(1, (stepCount * 0.30).round());
  final midEnd = min(
    stepCount - 1,
    max(baseEnd + 1, (stepCount * 0.80).round()),
  );
  final weights = <double>[];
  for (int i = 0; i < stepCount - 1; i++) {
    final int step = i + 1;
    if (step <= baseEnd) {
      // Wider spacing near the base.
      weights.add(1.20);
    } else if (step <= midEnd) {
      // More even spacing in mid-slope.
      weights.add(1.00);
    } else {
      // Tighter spacing near summit approach.
      weights.add(0.78);
    }
  }
  return weights;
}

List<Offset> _applyIrregularWobble(
  List<Offset> points, {
  required double seed,
  required double xMin,
  required double xMax,
  required bool isLeft,
}) {
  if (points.length < 3) return points;
  final out = <Offset>[];
  final last = points.length - 1;
  for (int i = 0; i < points.length; i++) {
    if (i == 0 || i == last) {
      out.add(points[i]);
      continue;
    }
    final t = i / last;
    final amp = t <= 0.30
        ? 0.016
        : t <= 0.80
            ? 0.012
            : 0.008;

    final waveX = sin((t * 21.0 + seed) * 2 * pi) * 0.50 +
        sin((t * 53.0 + seed * 1.9) * 2 * pi) * 0.34 +
        sin((t * 87.0 + seed * 0.7) * 2 * pi) * 0.16;
    final waveY = sin((t * 29.0 + seed * 1.3) * 2 * pi) * 0.7 +
        sin((t * 61.0 + seed * 0.9) * 2 * pi) * 0.3;

    final p = points[i];
    double x = (p.dx + waveX * amp).clamp(xMin, xMax);
    final centerProgress = ((t - 0.33) / 0.67).clamp(0.0, 1.0);
    if (centerProgress > 0.0) {
      final targetX = isLeft
          ? (0.43 + 0.065 * centerProgress)
          : (0.57 - 0.065 * centerProgress);
      final pull = 0.52 * pow(centerProgress, 1.05);
      x = x + (targetX - x) * pull;

      if (isLeft) {
        final minInward = 0.22 + 0.22 * centerProgress;
        x = x.clamp(minInward, 0.505);
      } else {
        final maxInward = 0.78 - 0.27 * centerProgress;
        x = x.clamp(0.495, maxInward);
      }
    }

    final y = (p.dy + waveY * amp * 0.26).clamp(0.02, 0.98);
    out.add(Offset(x, y));
  }
  return out;
}

List<Offset> _catmullRomDensePolyline(
  List<Offset> points, {
  required int samplesPerSegment,
}) {
  if (points.length < 2) return List<Offset>.from(points);
  final result = <Offset>[];
  final last = points.length - 1;

  for (int i = 0; i < last; i++) {
    final p0 = points[i == 0 ? 0 : i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[i + 2 > last ? last : i + 2];

    for (int s = 0; s < samplesPerSegment; s++) {
      final t = s / samplesPerSegment;
      result.add(_catmullRomPoint(p0, p1, p2, p3, t));
    }
  }
  result.add(points.last);
  return result;
}

Offset _catmullRomPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final t2 = t * t;
  final t3 = t2 * t;
  final x = 0.5 *
      ((2.0 * p1.dx) +
          (-p0.dx + p2.dx) * t +
          (2.0 * p0.dx - 5.0 * p1.dx + 4.0 * p2.dx - p3.dx) * t2 +
          (-p0.dx + 3.0 * p1.dx - 3.0 * p2.dx + p3.dx) * t3);
  final y = 0.5 *
      ((2.0 * p1.dy) +
          (-p0.dy + p2.dy) * t +
          (2.0 * p0.dy - 5.0 * p1.dy + 4.0 * p2.dy - p3.dy) * t2 +
          (-p0.dy + 3.0 * p1.dy - 3.0 * p2.dy + p3.dy) * t3);
  return Offset(x, y);
}

List<double> _cumulativeLengths(List<Offset> points) {
  if (points.isEmpty) return const <double>[];
  final out = <double>[0.0];
  for (int i = 1; i < points.length; i++) {
    out.add(out.last + (points[i] - points[i - 1]).distance);
  }
  return out;
}

Offset _pointAtDistance(List<Offset> points, List<double> cum, double target) {
  if (points.isEmpty) return Offset.zero;
  if (target <= 0.0) return points.first;
  final total = cum.last;
  if (target >= total) return points.last;

  int lo = 0;
  int hi = cum.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] < target) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }

  final i = lo;
  if (i <= 0) return points.first;
  final d0 = cum[i - 1];
  final d1 = cum[i];
  final span = d1 - d0;
  if (span <= 1e-9) return points[i];
  final t = (target - d0) / span;
  final a = points[i - 1];
  final b = points[i];
  return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
}
