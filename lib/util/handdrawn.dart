import 'dart:math';

import 'package:flutter/material.dart';

double _randRange(Random rng, double min, double max) {
  return min + (max - min) * rng.nextDouble();
}

List<Offset> jitteredLinePoints(
  Offset start,
  Offset end,
  int seed, {
  int points = 8,
  double jitter = 2.0,
}) {
  final rng = Random(seed);
  final List<Offset> result = [];
  for (int i = 0; i < points; i++) {
    final t = points == 1 ? 0.0 : i / (points - 1);
    final x = start.dx + (end.dx - start.dx) * t;
    final y = start.dy + (end.dy - start.dy) * t;
    result.add(
      Offset(
        x + _randRange(rng, -jitter, jitter),
        y + _randRange(rng, -jitter, jitter),
      ),
    );
  }
  return result;
}

Path jitteredLinePath(
  Offset start,
  Offset end,
  int seed, {
  int points = 8,
  double jitter = 2.0,
}) {
  final pts = jitteredLinePoints(
    start,
    end,
    seed,
    points: points,
    jitter: jitter,
  );
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (int i = 1; i < pts.length; i++) {
    path.lineTo(pts[i].dx, pts[i].dy);
  }
  return path;
}

Path partialPath(Path path, double t) {
  if (t <= 0) {
    return Path();
  }
  if (t >= 1) {
    return path;
  }
  final metrics = path.computeMetrics().toList();
  if (metrics.isEmpty) {
    return path;
  }
  final metric = metrics.first;
  return metric.extractPath(0, metric.length * t);
}
