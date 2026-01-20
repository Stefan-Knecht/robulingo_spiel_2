// ------------------------------------------------------------
// Ziel (Laien): Ladder/Track anzeigen mit Spieler- und Rival-Marker + Flaggen.
// Strategie: Wiederverwendbares Widget statt Inline-Painting in main.dart.
// Schritte: Zwei Tracks zeichnen, Marker/Flaggen positionieren, Icons aus Assets laden.
// Tücken: trackLength kommt aus constants.dart; Flaggen-Index/Visibility muss von außen stimmen.
// ------------------------------------------------------------
import 'package:flutter/material.dart';

import '../constants.dart';
import '../logic/ladder_controller.dart';
import '../track_painter.dart';

class LadderTrack extends StatelessWidget {
  const LadderTrack({
    super.key,
    required this.youX,
    required this.youLane,
    required this.rivalX,
    required this.rivalLane,
    required this.youFlagVisible,
    required this.rivalFlagVisible,
    required this.youFlagAngle,
    required this.rivalFlagAngle,
    required this.youFlagShowIndex,
    required this.rivalFlagShowIndex,
    required this.youTrail,
    required this.rivalTrail,
  });

  final int youX;
  final int youLane;
  final int rivalX;
  final int rivalLane;
  final bool youFlagVisible;
  final bool rivalFlagVisible;
  final double youFlagAngle;
  final double rivalFlagAngle;
  final int youFlagShowIndex;
  final int rivalFlagShowIndex;
  final List<TrailPoint> youTrail;
  final List<TrailPoint> rivalTrail;

  @override
  Widget build(BuildContext context) {
    const laneSize = 26.0;
    const markerSize = 18.0;
    const labelWidth = 64.0;
    const iconSize = 52.0;
    const strokeWidth = 1.5;

    Widget buildTrack(
      Color color,
      int pos,
      String label,
      int lane, {
      required bool showFlag,
      required double angle,
      required List<TrailPoint> trail,
    }) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = (constraints.maxWidth - labelWidth).clamp(10.0, 9999.0);
          const trackHeight = laneSize + markerSize; // genug Platz für Marker ober-/unterhalb
          final markerTop = lane == 0 ? 0.0 : laneSize;
          const dotSize = 8.0;
          final stepWidth = trackWidth / trackLength;
          final visibleTrail =
              trail.length > 120 ? trail.sublist(trail.length - 120) : trail;

          return SizedBox(
            height: trackHeight,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: label.isNotEmpty
                          ? Image.asset(
                              label == 'Du' ? 'assets/icons/player.webp' : 'assets/icons/rival.webp',
                              width: iconSize,
                              height: iconSize,
                              fit: BoxFit.contain,
                            )
                          : const SizedBox.shrink(),
                    ),
                    CustomPaint(
                      size: Size(trackWidth, laneSize),
                      painter: TrackPainter(color: color, strokeWidth: strokeWidth),
                    ),
                  ],
                ),
                Positioned(
                  left: labelWidth,
                  top: 0,
                  child: CustomPaint(
                    size: Size(trackWidth, trackHeight),
                    painter: _TrailPainter(
                      trail: visibleTrail,
                      color: color.withValues(alpha: 0.65),
                      laneSize: laneSize,
                      markerSize: markerSize,
                    ),
                  ),
                ),
                ...visibleTrail.map((pt) {
                  final left = labelWidth + pt.x * stepWidth - (dotSize / 2);
                  final top =
                      (pt.lane == 0 ? 0.0 : laneSize) + (markerSize / 2 - dotSize / 2);
                  return Positioned(
                    left: left,
                    top: top,
                    child: Container(
                      width: dotSize,
                      height: dotSize,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
                Positioned(
                  left: labelWidth + pos * (trackWidth / trackLength) - (markerSize / 2),
                  top: markerTop,
                  child: Container(
                    width: markerSize,
                    height: markerSize,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                if (showFlag)
                  Positioned(
                    right: 0,
                    top: -markerSize * 0.5,
                    child: Transform.rotate(
                      angle: angle,
                      child: Image.asset(
                        label == 'Du'
                            ? 'assets/icons/flag_player_$youFlagShowIndex.webp'
                            : 'assets/icons/flag_rival_$rivalFlagShowIndex.webp',
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          buildTrack(Colors.blue, youX, 'Du', youLane,
              showFlag: youFlagVisible,
              angle: youFlagAngle,
              trail: youTrail),
          const SizedBox(height: 10),
          buildTrack(Colors.orange, rivalX, 'Rival', rivalLane,
              showFlag: rivalFlagVisible,
              angle: rivalFlagAngle,
              trail: rivalTrail),
        ],
      ),
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter({
    required this.trail,
    required this.color,
    required this.laneSize,
    required this.markerSize,
  });

  final List<TrailPoint> trail;
  final Color color;
  final double laneSize;
  final double markerSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.length < 2) return;
    final step = size.width / trackLength;
    double yForLane(int lane) => (lane == 0 ? 0.0 : laneSize) + markerSize / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < trail.length - 1; i++) {
      final a = trail[i];
      final b = trail[i + 1];
      canvas.drawLine(
        Offset(a.x * step, yForLane(a.lane)),
        Offset(b.x * step, yForLane(b.lane)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPainter oldDelegate) {
    return oldDelegate.trail != trail || oldDelegate.color != color;
  }
}
