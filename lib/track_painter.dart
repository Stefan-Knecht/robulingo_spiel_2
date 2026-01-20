import 'package:flutter/material.dart';

import 'constants.dart';

class TrackPainter extends CustomPainter {
  TrackPainter({required this.color, this.strokeWidth = 1.5});

  final Color color;
  final double strokeWidth;
  static const int boxCount = trackLength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Außenrahmen
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, paint);

    // Vertikale Linien für die Kästchen (eins mehr als boxCount, damit Marker auf Ecken sitzen kann)
    final step = size.width / boxCount;
    for (int i = 1; i < boxCount; i++) {
      final x = step * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
