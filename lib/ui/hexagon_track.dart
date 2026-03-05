import 'package:flutter/material.dart';

import '../logic/hexagon_controller.dart';
import '../logic/mountain_tracks.dart';

class HexagonTrack extends StatelessWidget {
  const HexagonTrack({
    super.key,
    required this.youIndex,
    required this.rivalIndex,
    required this.youFlagVisible,
    required this.rivalFlagVisible,
    required this.youFlagAngle,
    required this.rivalFlagAngle,
    required this.youFlagShowIndex,
    required this.rivalFlagShowIndex,
    required this.youTrail,
    required this.rivalTrail,
    required this.tooltipLanguageCode,
    this.uiScale = 1.0,
    this.centerGrid = false,
    this.runsDone = 0,
  });

  final int youIndex;
  final int rivalIndex;
  final bool youFlagVisible;
  final bool rivalFlagVisible;
  final double youFlagAngle;
  final double rivalFlagAngle;
  final int youFlagShowIndex;
  final int rivalFlagShowIndex;
  final List<HexTrailPoint> youTrail;
  final List<HexTrailPoint> rivalTrail;
  final String tooltipLanguageCode;
  final double uiScale;
  final bool centerGrid;
  final int runsDone;

  String _backgroundAsset() {
    if (rivalFlagVisible) return 'assets/icons/mountain_orange.png';
    if (youFlagVisible) return 'assets/icons/mountain_blue.png';
    return 'assets/icons/mountain_color.png';
  }

  @override
  Widget build(BuildContext context) {
    final tracks = buildDefaultMountainTracks();
    final double scale = uiScale.clamp(0.4, 2.0);

    final board = LayoutBuilder(
      builder: (context, constraints) {
        const double aspectRatio = 3 / 2;
        const double fallbackWidth = 900;
        final double baseWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : (constraints.maxHeight.isFinite
                ? constraints.maxHeight * aspectRatio
                : fallbackWidth);
        final double width = baseWidth * scale;
        final double height = width / aspectRatio;

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _backgroundAsset(),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
              ColoredBox(color: Colors.white.withValues(alpha: 0.32)),
              CustomPaint(
                painter: _MountainTrackPainter(
                  leftSteps: tracks.left,
                  rightSteps: tracks.right,
                  youIndex: youIndex,
                  rivalIndex: rivalIndex,
                  youTrail: youTrail,
                  rivalTrail: rivalTrail,
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!centerGrid) return board;
    return Align(
      alignment: Alignment.topCenter,
      child: FractionallySizedBox(widthFactor: 0.9, child: board),
    );
  }
}

class _MountainTrackPainter extends CustomPainter {
  _MountainTrackPainter({
    required this.leftSteps,
    required this.rightSteps,
    required this.youIndex,
    required this.rivalIndex,
    required this.youTrail,
    required this.rivalTrail,
  });

  final List<Offset> leftSteps;
  final List<Offset> rightSteps;
  final int youIndex;
  final int rivalIndex;
  final List<HexTrailPoint> youTrail;
  final List<HexTrailPoint> rivalTrail;

  @override
  void paint(Canvas canvas, Size size) {
    final left = leftSteps.map((p) => _toCanvas(p, size)).toList();
    final right = rightSteps.map((p) => _toCanvas(p, size)).toList();
    final leftVisited = youTrail.map((e) => e.index).toSet();
    final rightVisited = rivalTrail.map((e) => e.index).toSet();

    _drawTrackPolyline(canvas, left, const Color(0xFF1E40AF));
    _drawTrackPolyline(canvas, right, const Color(0xFFD97706));

    _drawTrail(
      canvas,
      left,
      youTrail,
      const Color(0xCC1E40AF),
      size.shortestSide * 0.0062,
    );
    _drawTrail(
      canvas,
      right,
      rivalTrail,
      const Color(0xCCD97706),
      size.shortestSide * 0.0062,
    );

    _drawNodes(
      canvas,
      left,
      visited: leftVisited,
      baseColor: const Color(0xFF1D4ED8),
      otherColor: const Color(0xFF6B7280),
      radius: size.shortestSide * 0.0052,
    );
    _drawNodes(
      canvas,
      right,
      visited: rightVisited,
      baseColor: const Color(0xFFF59E0B),
      otherColor: const Color(0xFF6B7280),
      radius: size.shortestSide * 0.0052,
    );

    _drawNextHighlight(
      canvas,
      points: left,
      currentIndex: youIndex,
      color: const Color(0xFF1D4ED8),
      radius: size.shortestSide * 0.011,
    );
    _drawNextHighlight(
      canvas,
      points: right,
      currentIndex: rivalIndex,
      color: const Color(0xFFF59E0B),
      radius: size.shortestSide * 0.011,
    );

    _drawClimber(
      canvas,
      points: left,
      index: youIndex,
      fill: const Color(0xFF1D4ED8),
      radius: size.shortestSide * 0.063,
      yOffset: -size.shortestSide * 0.0255,
    );
    _drawClimber(
      canvas,
      points: right,
      index: rivalIndex,
      fill: const Color(0xFFF59E0B),
      radius: size.shortestSide * 0.063,
      yOffset: size.shortestSide * 0.0255,
    );
  }

  void _drawTrackPolyline(Canvas canvas, List<Offset> points, Color color) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    final paint = Paint()
      ..color = color.withValues(alpha: 0.70)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 5.04;
    canvas.drawPath(path, paint);
  }

  void _drawTrail(
    Canvas canvas,
    List<Offset> points,
    List<HexTrailPoint> trail,
    Color color,
    double width,
  ) {
    if (trail.length < 2) return;
    final clean = trail
        .map((e) => e.index)
        .where((i) => i >= 0 && i < points.length)
        .toList();
    if (clean.length < 2) return;

    final path = Path()..moveTo(points[clean.first].dx, points[clean.first].dy);
    for (int i = 1; i < clean.length; i++) {
      path.lineTo(points[clean[i]].dx, points[clean[i]].dy);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  void _drawNodes(
    Canvas canvas,
    List<Offset> points, {
    required Set<int> visited,
    required Color baseColor,
    required Color otherColor,
    required double radius,
  }) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.65;
    final fill = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final isVisited = visited.contains(i);
      fill.color = isVisited
          ? baseColor.withValues(alpha: 0.88)
          : Colors.white.withValues(alpha: 0.80);
      stroke.color = isVisited
          ? Colors.white.withValues(alpha: 0.95)
          : otherColor.withValues(alpha: 0.86);
      canvas.drawCircle(points[i], radius, fill);
      canvas.drawCircle(points[i], radius, stroke);
    }
  }

  void _drawNextHighlight(
    Canvas canvas, {
    required List<Offset> points,
    required int currentIndex,
    required Color color,
    required double radius,
  }) {
    if (points.isEmpty) return;
    final next = (currentIndex + 1).clamp(0, points.length - 1);
    if (next == currentIndex && currentIndex >= points.length - 1) return;
    final center = points[next];

    final halo = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 1.95, halo);

    final ring = Paint()
      ..color = color.withValues(alpha: 0.96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.55;
    canvas.drawCircle(center, radius, ring);
  }

  void _drawClimber(
    Canvas canvas, {
    required List<Offset> points,
    required int index,
    required Color fill,
    required double radius,
    required double yOffset,
  }) {
    if (points.isEmpty) return;
    final clamped = index.clamp(0, points.length - 1);
    final center = points[clamped].translate(0, yOffset);

    final body = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.25;

    canvas.drawCircle(center, radius, body);
    canvas.drawCircle(center, radius, outline);
  }

  Offset _toCanvas(Offset normalized, Size size) {
    return Offset(normalized.dx * size.width, normalized.dy * size.height);
  }

  @override
  bool shouldRepaint(covariant _MountainTrackPainter oldDelegate) {
    return oldDelegate.leftSteps != leftSteps ||
        oldDelegate.rightSteps != rightSteps ||
        oldDelegate.youIndex != youIndex ||
        oldDelegate.rivalIndex != rivalIndex ||
        oldDelegate.youTrail != youTrail ||
        oldDelegate.rivalTrail != rivalTrail;
  }
}
