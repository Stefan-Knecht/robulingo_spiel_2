// ------------------------------------------------------------
// Ziel (Laien): Hexagon-Gitter als gemeinsames Rennfeld rendern (Spieler & Rival).
// Strategie: Gleiche Maße wie Ladder nutzen: Track-Breite in 20 Teilstücke, Hex-Form via vorgegebene Punkte, 10x3 Grid.
// ------------------------------------------------------------
import 'package:flutter/material.dart';

import '../logic/hexagon_controller.dart';
import '../logic/hexagon_grid.dart';

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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final double labelWidth = isLandscape ? 100.0 : 52.0;
    final double iconSize = isLandscape ? 176.0 : 52.0;
    final double flagSize = isLandscape ? 160.0 : 44.0;
    final double marginFactor = isLandscape ? 0.2 : 0.15;
    final double flagColumnWidth = isLandscape ? 100.0 : 58.0;
    final double gridStrokeWidth = isLandscape ? 1.6 : 1.0;
    final double markerRadius = isLandscape ? 48.0 : 10.0;
    final double trailStrokeWidth = isLandscape ? 10.0 : 5.0;
    final EdgeInsets outerPadding = EdgeInsets.symmetric(
      horizontal: isLandscape ? 16 : 8,
      vertical: 8,
    );

    return Padding(
      padding: outerPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final unitGrid = buildHexGrid(side: 1.0);
          final double unitMinX = unitGrid.nodes.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
          final double unitMaxX = unitGrid.nodes.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
          final double widthFactor = unitMaxX - unitMinX;
          final double availableWidth =
              (constraints.maxWidth - labelWidth - flagColumnWidth).clamp(80.0, 2000.0);
          final double side = availableWidth / (widthFactor + 2 * marginFactor);

          final grid = buildHexGrid(side: side);
          final double minX = grid.nodes.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
          final double maxX = grid.nodes.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
          final double minY = grid.nodes.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
          final double maxY = grid.nodes.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
          final double margin = side * marginFactor;
          final Offset translation = Offset(-minX + margin, -minY + margin);

          final List<_HexCell> shiftedCells = grid.cells
              .map((cell) => _HexCell(
                    row: cell.row,
                    col: cell.col,
                    points: cell.points.map((p) => p + translation).toList(),
                  ))
              .toList();
          final List<Offset> shiftedNodes =
              grid.nodes.map((p) => p + translation).toList();

          final trackWidth = (maxX - minX) + 2 * margin;
          final trackHeight = (maxY - minY) + 2 * margin;
          const int lastCol = hexagonGridCols - 1;
          final List<_Edge> finishEdges = shiftedCells
              .where((c) => c.col == lastCol && c.row == 1)
              .map((c) => _Edge(c.points[1], c.points[2]))
              .toList();
          final iconsHeight = iconSize * 2 + 12;
          final baseHeight = iconsHeight > trackHeight ? iconsHeight : trackHeight;
          final totalWidth = labelWidth + trackWidth + flagColumnWidth;
          final int playerStartIdx = grid.nodeIndexFor(2, 0, 5) ?? 0;
          final int rivalStartIdx = grid.nodeIndexFor(0, 0, 4) ?? 0;
          final Offset playerStartPos = shiftedNodes[playerStartIdx];
          final Offset rivalStartPos = shiftedNodes[rivalStartIdx];
          final double topBandStart = 0.05 * trackHeight;
          final double topBandEnd = 0.4 * trackHeight;
          final double bottomBandStart = 0.6 * trackHeight;
          final double bottomBandEnd = 0.95 * trackHeight;
          final double topBandMin = topBandStart;
          final double topBandMax = topBandEnd - iconSize;
          final double bottomBandMin = bottomBandStart;
          final double bottomBandMax = bottomBandEnd - iconSize;
          final double safeTopMax = topBandMax >= topBandMin ? topBandMax : topBandMin;
          final double safeBottomMax =
              bottomBandMax >= bottomBandMin ? bottomBandMax : bottomBandMin;
          double rivalTop = ((rivalStartPos.dy - iconSize / 2)
                  .clamp(topBandMin, safeTopMax))
              .toDouble();
          double playerTop = ((playerStartPos.dy - iconSize / 2)
                  .clamp(bottomBandMin, safeBottomMax))
              .toDouble();
          final double flagTopRival = (trackHeight / 2) - flagSize - 4;
          final double flagTopPlayer = (trackHeight / 2) + 4;

          return SizedBox(
            height: baseHeight + 24,
            width: totalWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: labelWidth,
                      height: trackHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: (labelWidth - iconSize) / 2,
                            top: rivalTop,
                            child: Image.asset(
                              'assets/icons/rival.webp',
                              width: iconSize,
                              height: iconSize,
                              fit: BoxFit.contain,
                            ),
                          ),
                          Positioned(
                            left: (labelWidth - iconSize) / 2,
                            top: playerTop,
                            child: Image.asset(
                              'assets/icons/player.webp',
                              width: iconSize,
                              height: iconSize,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: trackWidth,
                      height: trackHeight,
                      child: CustomPaint(
                        size: Size(trackWidth, trackHeight),
                        painter: _HexagonPainter(
                          cells: shiftedCells,
                          nodes: shiftedNodes,
                          youIndex: youIndex,
                          rivalIndex: rivalIndex,
                          youTrail: youTrail,
                          rivalTrail: rivalTrail,
                          finishEdges: finishEdges,
                          gridStrokeWidth: gridStrokeWidth,
                          markerRadius: markerRadius,
                          trailStrokeWidth: trailStrokeWidth,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: flagColumnWidth,
                      height: trackHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (youFlagVisible)
                            Positioned(
                              left: (flagColumnWidth - flagSize) / 2,
                              top: flagTopPlayer,
                              child: Transform.rotate(
                                angle: youFlagAngle,
                                  child: Image.asset(
                                    'assets/icons/flag_player_$youFlagShowIndex.webp',
                                    width: flagSize,
                                    height: flagSize,
                                    fit: BoxFit.contain,
                                  ),
                              ),
                            ),
                          if (rivalFlagVisible)
                            Positioned(
                              left: (flagColumnWidth - flagSize) / 2,
                              top: flagTopRival,
                              child: Transform.rotate(
                                angle: rivalFlagAngle,
                                  child: Image.asset(
                                    'assets/icons/flag_rival_$rivalFlagShowIndex.webp',
                                    width: flagSize,
                                    height: flagSize,
                                    fit: BoxFit.contain,
                                  ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HexagonPainter extends CustomPainter {
  _HexagonPainter({
    required this.cells,
    required this.nodes,
    required this.youIndex,
    required this.rivalIndex,
    required this.youTrail,
    required this.rivalTrail,
    required this.finishEdges,
    required this.gridStrokeWidth,
    required this.markerRadius,
    required this.trailStrokeWidth,
  });

  final List<_HexCell> cells;
  final List<Offset> nodes;
  final int youIndex;
  final int rivalIndex;
  final List<HexTrailPoint> youTrail;
  final List<HexTrailPoint> rivalTrail;
  final List<_Edge> finishEdges;
  final double gridStrokeWidth;
  final double markerRadius;
  final double trailStrokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final nodePositions = nodes;

    final gridPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = gridStrokeWidth;
    for (final cell in cells) {
      final path = Path()..addPolygon(cell.points, true);
      canvas.drawPath(path, gridPaint);
    }

    final finishPaint = Paint()
      ..color = Colors.green.shade700.withValues(alpha: 0.95)
      ..strokeWidth = 8.0;
    for (final edge in finishEdges) {
      canvas.drawLine(edge.a, edge.b, finishPaint);
    }

    void drawTrail(List<HexTrailPoint> trail, Color color) {
      if (trail.length < 2) return;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = trailStrokeWidth
        ..strokeCap = StrokeCap.round;
      final points = trail
          .map((pt) => (pt.index >= 0 && pt.index < nodePositions.length)
              ? nodePositions[pt.index]
              : null)
          .where((p) => p != null)
          .cast<Offset>()
          .toList();
      for (int i = 0; i < points.length - 1; i++) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }

    drawTrail(youTrail, Colors.blue.withValues(alpha: 0.65));
    drawTrail(rivalTrail, Colors.orange.withValues(alpha: 0.65));

    Offset? nodeFor(int idx) {
      if (idx < 0 || idx >= nodePositions.length) return null;
      return nodePositions[idx];
    }

    final youCenter = nodeFor(youIndex);
    final rivalCenter = nodeFor(rivalIndex);
    if (youCenter != null) {
      final paint = Paint()
        ..color = Colors.blue.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(youCenter.translate(0, -markerRadius * 0.3), markerRadius, paint);
    }
    if (rivalCenter != null) {
      final paint = Paint()
        ..color = Colors.orange.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(rivalCenter.translate(0, markerRadius * 0.3), markerRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HexagonPainter oldDelegate) {
    return oldDelegate.youIndex != youIndex ||
        oldDelegate.rivalIndex != rivalIndex ||
        oldDelegate.youTrail != youTrail ||
        oldDelegate.rivalTrail != rivalTrail ||
        oldDelegate.nodes != nodes ||
        oldDelegate.finishEdges != finishEdges ||
        oldDelegate.trailStrokeWidth != trailStrokeWidth;
  }
}

class _HexCell {
  _HexCell({required this.row, required this.col, required this.points});
  final int row;
  final int col;
  final List<Offset> points;
}

class _Edge {
  _Edge(this.a, this.b);
  final Offset a;
  final Offset b;

  @override
  bool operator ==(Object other) {
    return other is _Edge &&
        ((a == other.a && b == other.b) || (a == other.b && b == other.a));
  }

  @override
  int get hashCode => a.hashCode ^ b.hashCode;
}
