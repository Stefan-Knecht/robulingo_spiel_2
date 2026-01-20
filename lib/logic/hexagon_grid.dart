import 'dart:math';

import 'package:flutter/material.dart';

const int hexagonGridCols = 10;
const int hexagonGridRows = 3;

const List<Offset> _unitHex = [
  Offset(0.0, -1.0),
  Offset(0.8660254, -0.5),
  Offset(0.8660254, 0.5),
  Offset(0.0, 1.0),
  Offset(-0.8660254, 0.5),
  Offset(-0.8660254, -0.5),
];

class HexCellData {
  HexCellData({required this.row, required this.col, required this.points});
  final int row;
  final int col;
  final List<Offset> points;
}

class HexGridData {
  HexGridData({
    required this.nodes,
    required this.adjacency,
    required this.cells,
    required this.nodeIndexByCellVertex,
    required this.finishNodes,
    required this.maxX,
  });

  final List<Offset> nodes;
  final Map<int, Set<int>> adjacency;
  final List<HexCellData> cells;
  final Map<String, int> nodeIndexByCellVertex;
  final Set<int> finishNodes;
  final double maxX;

  int? nodeIndexFor(int row, int col, int vertex) =>
      nodeIndexByCellVertex['$row:$col:$vertex'];
}

HexGridData buildHexGrid({double side = 1.0}) {
  final List<HexCellData> cells = [];
  final Map<String, int> nodeIndexByKey = {};
  final Map<String, int> nodeIndexByCellVertex = {};
  final List<Offset> nodes = [];

  int addNode(Offset p) {
    final key = '${p.dx.toStringAsFixed(6)}:${p.dy.toStringAsFixed(6)}';
    if (nodeIndexByKey.containsKey(key)) return nodeIndexByKey[key]!;
    final idx = nodes.length;
    nodeIndexByKey[key] = idx;
    nodes.add(p);
    return idx;
  }

  for (int row = 0; row < hexagonGridRows; row++) {
    for (int col = 0; col < hexagonGridCols; col++) {
      final double xOffset =
          col * (1.7320508 * side) + (row.isOdd ? 0.8660254 * side : 0.0);
      final double yOffset = row * (1.5 * side);
      final points = _unitHex
          .map((p) => Offset((p.dx * side) + xOffset, (p.dy * side) + yOffset))
          .toList();
      cells.add(HexCellData(row: row, col: col, points: points));
      for (int v = 0; v < points.length; v++) {
        final idx = addNode(points[v]);
        nodeIndexByCellVertex['$row:$col:$v'] = idx;
      }
    }
  }

  final Map<int, Set<int>> adjacency = {};

  void connect(int a, int b) {
    adjacency.putIfAbsent(a, () => <int>{}).add(b);
    adjacency.putIfAbsent(b, () => <int>{}).add(a);
  }

  for (final cell in cells) {
    final verts = List.generate(6, (i) => nodeIndexByCellVertex['${cell.row}:${cell.col}:$i']!);
    for (int i = 0; i < 6; i++) {
      final int a = verts[i];
      final int b = verts[(i + 1) % 6];
      connect(a, b);
    }
  }

  final double maxX = nodes.map((p) => p.dx).reduce(max);
  const int lastCol = hexagonGridCols - 1;
  final Set<int> finishNodes = {
    for (final cell in cells.where((c) => c.col == lastCol && c.row == 1))
      for (int v = 0; v < 6; v++)
        if ((cell.points[v].dx - maxX).abs() < 1e-6)
          nodeIndexByCellVertex['${cell.row}:${cell.col}:$v']!
  };

  return HexGridData(
    nodes: nodes,
    adjacency: adjacency,
    cells: cells,
    nodeIndexByCellVertex: nodeIndexByCellVertex,
    finishNodes: finishNodes,
    maxX: maxX,
  );
}
