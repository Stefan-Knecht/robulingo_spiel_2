import 'dart:math';

import 'package:flutter/material.dart';
import 'package:robulingo_flutter/utils/color_utils.dart';

import '../util/handdrawn.dart';

// Einfache Daten fuer einen Kalendertag (Anzeigezustand).
// "rivalQualified" ist nur eine visuelle Markierung, kein echter Nutzer.
class DayStatus {
  final DateTime date;
  final bool qualified;
  final bool rivalQualified;
  final int activeSeconds;
  const DayStatus({
    required this.date,
    required this.qualified,
    this.rivalQualified = false,
    this.activeSeconds = 0,
  });

  DayStatus copyWith({
    bool? qualified,
    bool? rivalQualified,
    int? activeSeconds,
  }) {
    return DayStatus(
      date: date,
      qualified: qualified ?? this.qualified,
      rivalQualified: rivalQualified ?? this.rivalQualified,
      activeSeconds: activeSeconds ?? this.activeSeconds,
    );
  }
}

class PaperStyle {
  final Color paperColor;
  final Color gridLineColor;
  final Color pencilColor;
  final Color playerMarkColor;
  final Color rivalMarkColor;
  final Color glowColor;
  final Color clipColor;
  final Color ringHoleColor;
  final Color ringShadowColor;
  final Color scribbleColor;
  final double cardPadding;
  final double cellGap;
  final double cellRadius;
  final double cardRadius;
  final double gridStrokeWidth;
  final double pencilStrokeWidth;
  final double rivalStrokeWidth;
  final double lineJitter;
  final double markJitter;
  final double noiseOpacity;
  final double bindingHeight;
  final double ringHoleRadius;
  final double glowInflate;
  final double scribblePadding;
  final bool textureEnabled;
  final bool showBinding;

  const PaperStyle({
    this.paperColor = const Color(0xFFF4EFE6),
    this.gridLineColor = const Color(0xFFB7B0A6),
    this.pencilColor = const Color(0xFF2B2B2B),
    this.playerMarkColor = const Color(0xFF2B2B2B),
    this.rivalMarkColor = const Color(0xFFE27A2A),
    this.glowColor = const Color(0xFFE6D9B8),
    this.clipColor = const Color(0xFF6A6A6A),
    this.ringHoleColor = const Color(0xFFD7D2C8),
    this.ringShadowColor = const Color(0x33000000),
    this.scribbleColor = const Color(0xFF3A3A3A),
    this.cardPadding = 16,
    this.cellGap = 8,
    this.cellRadius = 10,
    this.cardRadius = 18,
    this.gridStrokeWidth = 1.2,
    this.pencilStrokeWidth = 2.4,
    this.rivalStrokeWidth = 2.2,
    this.lineJitter = 2.2,
    this.markJitter = 1.6,
    this.noiseOpacity = 0.08,
    this.bindingHeight = 12,
    this.ringHoleRadius = 3.6,
    this.glowInflate = 4,
    this.scribblePadding = 6,
    this.textureEnabled = true,
    this.showBinding = true,
  });
}

List<DayStatus> dayStatusFromJson(Map<String, dynamic> json) {
  final items = json["days"] as List<dynamic>? ?? const [];
  return items.map((entry) {
    final map = entry as Map<String, dynamic>;
    final dateStr = map["date"] as String? ?? "1970-01-01";
    final date = DateTime.parse("${dateStr}T00:00:00Z");
    final qualified = map["qualified"] as bool? ?? false;
    final rivalQualified = map["rival_qualified"] as bool? ?? false;
    final activeSeconds = map["active_seconds"] as int? ?? 0;
    return DayStatus(
      date: date,
      qualified: qualified,
      rivalQualified: rivalQualified,
      activeSeconds: activeSeconds,
    );
  }).toList(growable: false);
}

class PaperWeekCalendar extends StatelessWidget {
  const PaperWeekCalendar({
    super.key,
    required this.days,
    required this.todayIndex,
    this.todayProgress = 0.0,
    this.animateMarks = true,
    this.onTapDay,
    this.paperStyle = const PaperStyle(),
  });

  final List<DayStatus> days;
  final int todayIndex;
  final double todayProgress;
  final bool animateMarks;
  final void Function(int index)? onTapDay;
  final PaperStyle paperStyle;

  @override
  Widget build(BuildContext context) {
    assert(days.length == 7, "days must be length 7");
    return _PaperWeekCalendarBody(
      days: days,
      todayIndex: todayIndex,
      todayProgress: todayProgress.clamp(0.0, 1.0).toDouble(),
      animateMarks: animateMarks,
      onTapDay: onTapDay,
      paperStyle: paperStyle,
    );
  }
}

class _PaperWeekCalendarBody extends StatefulWidget {
  const _PaperWeekCalendarBody({
    required this.days,
    required this.todayIndex,
    required this.todayProgress,
    required this.animateMarks,
    required this.onTapDay,
    required this.paperStyle,
  });

  final List<DayStatus> days;
  final int todayIndex;
  final double todayProgress;
  final bool animateMarks;
  final void Function(int index)? onTapDay;
  final PaperStyle paperStyle;

  @override
  State<_PaperWeekCalendarBody> createState() => _PaperWeekCalendarBodyState();
}

class _PaperWeekCalendarBodyState extends State<_PaperWeekCalendarBody>
    with TickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 600);
  static const Duration _stagger = Duration(milliseconds: 40);

  late final List<AnimationController> _controllers;
  late List<bool> _lastMarked;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      7,
      (_) => AnimationController(vsync: this, duration: _duration),
    );
    _lastMarked = widget.days
        .map((d) => d.qualified || d.rivalQualified)
        .toList(growable: false);
    for (int i = 0; i < 7; i++) {
      _controllers[i].value =
          widget.days[i].qualified || widget.days[i].rivalQualified ? 1.0 : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant _PaperWeekCalendarBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (int i = 0; i < 7; i++) {
      final wasMarked = _lastMarked[i];
      final isMarked =
          widget.days[i].qualified || widget.days[i].rivalQualified;
      if (!wasMarked && isMarked) {
        if (widget.animateMarks) {
          _controllers[i].value = 0.0;
          Future<void>.delayed(_stagger * i, () {
            if (!mounted) return;
            _controllers[i].forward();
          });
        } else {
          _controllers[i].value = 1.0;
        }
      } else if (wasMarked && !isMarked) {
        _controllers[i].value = 0.0;
      } else if (isMarked && !widget.animateMarks) {
        _controllers[i].value = 1.0;
      }
    }
    _lastMarked = widget.days
        .map((d) => d.qualified || d.rivalQualified)
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  int _seedBase() {
    if (widget.days.isEmpty) return 0;
    final utc = widget.days.first.date.toUtc();
    return utc.millisecondsSinceEpoch ~/ const Duration(days: 1).inMilliseconds;
  }

  int? _hitTestIndex(Offset position, Size size) {
    final layout = _layoutForSize(size, widget.paperStyle);
    for (int i = 0; i < layout.cells.length; i++) {
      if (layout.cells[i].contains(position)) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 7 / 2.2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: widget.onTapDay == null
                ? null
                : (details) {
                    final index = _hitTestIndex(details.localPosition, size);
                    if (index != null) {
                      widget.onTapDay?.call(index);
                    }
                  },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: PaperCalendarPainter(
                      paperStyle: widget.paperStyle,
                      seedBase: _seedBase(),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge(_controllers),
                    builder: (context, child) {
                      final progress = _controllers
                          .map((controller) => controller.value)
                          .toList(growable: false);
                      return CustomPaint(
                        painter: MarksPainter(
                          days: widget.days,
                          todayIndex: widget.todayIndex,
                          todayProgress: widget.todayProgress,
                          markProgress: progress,
                          paperStyle: widget.paperStyle,
                          seedBase: _seedBase(),
                        ),
                      );
                    },
                  ),
                ),
                Positioned.fill(
                  child: _SemanticsOverlay(
                    days: widget.days,
                    onTapDay: widget.onTapDay,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SemanticsOverlay extends StatelessWidget {
  const _SemanticsOverlay({
    required this.days,
    required this.onTapDay,
  });

  final List<DayStatus> days;
  final void Function(int index)? onTapDay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(7, (index) {
        final status = days[index];
        return Expanded(
          child: Semantics(
            button: onTapDay != null,
            label: status.qualified
                ? (status.rivalQualified
                    ? "Day ${index + 1} of 7, completed, rival trained"
                    : "Day ${index + 1} of 7, completed")
                : (status.rivalQualified
                    ? "Day ${index + 1} of 7, rival trained"
                    : "Day ${index + 1} of 7, not completed"),
            onTap: onTapDay == null ? null : () => onTapDay?.call(index),
            child: const SizedBox.expand(),
          ),
        );
      }),
    );
  }
}

class PaperCalendarPainter extends CustomPainter {
  final PaperStyle paperStyle;
  final int seedBase;

  PaperCalendarPainter({
    required this.paperStyle,
    required this.seedBase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _layoutForSize(size, paperStyle);
    final cardRRect = RRect.fromRectAndRadius(
      layout.cardRect,
      Radius.circular(paperStyle.cardRadius),
    );
    final drawBackground = paperStyle.paperColor.a > 0;
    if (drawBackground) {
      final shadowPath = Path()..addRRect(cardRRect);
      canvas.drawShadow(
          shadowPath, Colors.black.withOpacityValue(0.15), 8, true);
      canvas.drawRRect(cardRRect, Paint()..color = paperStyle.paperColor);
    }

    if (drawBackground && paperStyle.textureEnabled) {
      _drawNoise(canvas, size);
    }
    if (paperStyle.showBinding) {
      _drawBinding(canvas, layout);
    }
    _drawGrid(canvas, layout);
  }

  void _drawNoise(Canvas canvas, Size size) {
    final rng = Random(seedBase);
    final count = ((size.width * size.height) / 2800)
        .round()
        .clamp(30, 160)
        .toInt();
    final paint =
        Paint()..color = Colors.black.withOpacityValue(paperStyle.noiseOpacity);
    for (int i = 0; i < count; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final radius = 0.4 + rng.nextDouble() * 0.8;
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  void _drawBinding(Canvas canvas, _PaperLayout layout) {
    const holes = 4;
    final span = layout.gridRect.width;
    final spacing = span / (holes + 1);
    final y = layout.cardRect.top + paperStyle.cardPadding * 0.6;
    for (int i = 0; i < holes; i++) {
      final x = layout.gridRect.left + spacing * (i + 1);
      final shadowPaint = Paint()..color = paperStyle.ringShadowColor;
      canvas.drawCircle(Offset(x, y + 1.2), paperStyle.ringHoleRadius + 0.6, shadowPaint);
      final holePaint = Paint()..color = paperStyle.ringHoleColor;
      canvas.drawCircle(Offset(x, y), paperStyle.ringHoleRadius, holePaint);
    }
  }

  void _drawGrid(Canvas canvas, _PaperLayout layout) {
    final bool transparentPaper = paperStyle.paperColor.a == 0;
    final double baseOpacity = transparentPaper ? 1.0 : 0.55;
    final double jitterOpacity = transparentPaper ? 1.0 : 0.75;
    final basePaint = Paint()
      ..color = paperStyle.gridLineColor.withOpacityValue(baseOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = paperStyle.gridStrokeWidth;
    for (final cell in layout.cells) {
      final rrect = RRect.fromRectAndRadius(
        cell,
        Radius.circular(paperStyle.cellRadius),
      );
      canvas.drawRRect(rrect, basePaint);
    }

    final jitterPaint = Paint()
      ..color = paperStyle.gridLineColor.withOpacityValue(jitterOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = paperStyle.gridStrokeWidth;
    int lineIndex = 0;
    for (final cell in layout.cells) {
      final tl = cell.topLeft;
      final tr = cell.topRight;
      final br = cell.bottomRight;
      final bl = cell.bottomLeft;
      final paths = [
        jitteredLinePath(tl, tr, seedBase + lineIndex++, jitter: paperStyle.lineJitter),
        jitteredLinePath(tr, br, seedBase + lineIndex++, jitter: paperStyle.lineJitter),
        jitteredLinePath(br, bl, seedBase + lineIndex++, jitter: paperStyle.lineJitter),
        jitteredLinePath(bl, tl, seedBase + lineIndex++, jitter: paperStyle.lineJitter),
      ];
      for (final path in paths) {
        canvas.drawPath(path, jitterPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PaperCalendarPainter oldDelegate) {
    return oldDelegate.paperStyle != paperStyle || oldDelegate.seedBase != seedBase;
  }
}

class MarksPainter extends CustomPainter {
  final List<DayStatus> days;
  final int todayIndex;
  final double todayProgress;
  final List<double> markProgress;
  final PaperStyle paperStyle;
  final int seedBase;

  MarksPainter({
    required this.days,
    required this.todayIndex,
    required this.todayProgress,
    required this.markProgress,
    required this.paperStyle,
    required this.seedBase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _layoutForSize(size, paperStyle);
    for (int i = 0; i < layout.cells.length; i++) {
      final cell = layout.cells[i];
      if (i == todayIndex) {
        _drawTodayGlow(canvas, cell);
      }
      if (i == todayIndex && !days[i].qualified && todayProgress > 0) {
        _drawScribble(canvas, cell, todayProgress, seedBase + 100 + i);
      }
          if (days[i].qualified) {
            final progress = i < markProgress.length ? markProgress[i] : 1.0;
            _drawPencilX(canvas, cell, progress, seedBase + 300 + i);
          }
          if (days[i].rivalQualified) {
            final progress = i < markProgress.length ? markProgress[i] : 1.0;
            _drawRivalCircle(canvas, cell, progress, seedBase + 600 + i);
          }
          if (i == todayIndex) {
            _drawPaperclip(canvas, cell);
          }
        }
  }

  void _drawTodayGlow(Canvas canvas, Rect cell) {
    final glowRect = cell.inflate(paperStyle.glowInflate);
    final glowPaint = Paint()
      ..color = paperStyle.glowColor.withOpacityValue(0.16)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        glowRect,
        Radius.circular(paperStyle.cellRadius + paperStyle.glowInflate),
      ),
      glowPaint,
    );
  }

  void _drawPaperclip(Canvas canvas, Rect cell) {
    final width = cell.width * 0.22;
    final height = cell.height * 0.22;
    final center = Offset(cell.center.dx, cell.top + height * 0.6);
    final outerRect = Rect.fromCenter(center: center, width: width, height: height);
    final innerRect = outerRect
        .deflate(width * 0.18)
        .shift(Offset(width * 0.08, height * 0.08));
    final paint = Paint()
      ..color = paperStyle.clipColor.withOpacityValue(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(outerRect, Radius.circular(width * 0.6)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, Radius.circular(width * 0.5)),
      paint,
    );
  }

  void _drawScribble(Canvas canvas, Rect cell, double progress, int seed) {
    final rng = Random(seed);
    final inset = cell.deflate(paperStyle.scribblePadding);
    final count = (6 + progress * 20).round().clamp(4, 24).toInt();
    for (int i = 0; i < count; i++) {
      final y = inset.top + inset.height * rng.nextDouble();
      final x1 = inset.left + inset.width * rng.nextDouble();
      final x2 = inset.left + inset.width * rng.nextDouble();
      final start = Offset(x1, y + (rng.nextDouble() - 0.5) * 6);
      final end = Offset(x2, y + (rng.nextDouble() - 0.5) * 6);
      final alpha = 0.10 + (0.12 * progress) + rng.nextDouble() * 0.04;
      final opacity = alpha.clamp(0.1, 0.22).toDouble();
      final paint = Paint()
        ..color = paperStyle.scribbleColor.withOpacityValue(opacity)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke;
      final path = jitteredLinePath(
        start,
        end,
        seed + i,
        points: 6,
        jitter: 1.2,
      );
      canvas.drawPath(path, paint);
    }
  }

  void _drawPencilX(Canvas canvas, Rect cell, double progress, int seed) {
    if (progress <= 0) return;
    final inset = cell.deflate(cell.shortestSide * 0.22);
    final a = inset.topLeft;
    final b = inset.bottomRight;
    final c = inset.topRight;
    final d = inset.bottomLeft;
    final first = (progress * 2).clamp(0.0, 1.0).toDouble();
    final second = ((progress - 0.5) * 2).clamp(0.0, 1.0).toDouble();
    _drawPencilStroke(canvas, a, b, first, seed);
    _drawPencilStroke(canvas, c, d, second, seed + 11);
  }

  void _drawPencilStroke(
    Canvas canvas,
    Offset start,
    Offset end,
    double progress,
    int seed,
  ) {
    if (progress <= 0) return;
    final rng = Random(seed);
    final baseAlpha = 0.65 + rng.nextDouble() * 0.25;
    final path = jitteredLinePath(
      start,
      end,
      seed,
      points: 8,
      jitter: paperStyle.markJitter,
    );
    final clipped = partialPath(path, progress);
    final paint = Paint()
      ..color = paperStyle.playerMarkColor.withOpacityValue(baseAlpha)
      ..strokeWidth = paperStyle.pencilStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
    canvas.drawPath(clipped, paint);
    final shadowPaint = Paint()
      ..color = paperStyle.playerMarkColor.withOpacityValue(baseAlpha * 0.6)
      ..strokeWidth = paperStyle.pencilStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(clipped.shift(const Offset(0.5, 0.5)), shadowPaint);
  }

  void _drawRivalCircle(Canvas canvas, Rect cell, double progress, int seed) {
    if (progress <= 0) return;
    final rng = Random(seed);
    final baseAlpha = 0.6 + rng.nextDouble() * 0.25;
    final inset = cell.deflate(cell.shortestSide * 0.22);
    final radius = min(inset.width, inset.height) / 2;
    final center = inset.center;
    final path = _roughOvalPath(center, radius, seed);
    final clipped = partialPath(path, progress);
    final paint = Paint()
      ..color = paperStyle.rivalMarkColor.withOpacityValue(baseAlpha)
      ..strokeWidth = paperStyle.rivalStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
    canvas.drawPath(clipped, paint);
  }

  Path _roughOvalPath(Offset center, double radius, int seed) {
    final rng = Random(seed);
    const int points = 14;
    final double radialJitter = radius * 0.12;
    const double angleJitter = 0.18;
    final path = Path();
    for (int i = 0; i <= points; i++) {
      final t = (i / points) * pi * 2;
      final angle = t + (rng.nextDouble() - 0.5) * angleJitter;
      final r = radius + (rng.nextDouble() - 0.5) * radialJitter;
      final x = center.dx + cos(angle) * r;
      final y = center.dy + sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant MarksPainter oldDelegate) {
    return oldDelegate.days != days ||
        oldDelegate.todayIndex != todayIndex ||
        oldDelegate.todayProgress != todayProgress ||
        oldDelegate.markProgress != markProgress ||
        oldDelegate.paperStyle != paperStyle ||
        oldDelegate.seedBase != seedBase;
  }
}

class _PaperLayout {
  final Rect cardRect;
  final Rect gridRect;
  final List<Rect> cells;
  const _PaperLayout({
    required this.cardRect,
    required this.gridRect,
    required this.cells,
  });
}

_PaperLayout _layoutForSize(Size size, PaperStyle style) {
  final cardRect = Offset.zero & size;
  final padding = style.cardPadding;
  final gridTop = padding + style.bindingHeight;
  final gridHeight = max(0.0, size.height - gridTop - padding);
  final gridWidth = max(0.0, size.width - padding * 2);
  final totalGap = style.cellGap * 6;
  final cellWidth = max(0.0, (gridWidth - totalGap) / 7);
  final gridLeft = padding;
  final gridRect = Rect.fromLTWH(gridLeft, gridTop, gridWidth, gridHeight);

  final cells = <Rect>[];
  for (int i = 0; i < 7; i++) {
    final left = gridLeft + i * (cellWidth + style.cellGap);
    cells.add(Rect.fromLTWH(left, gridTop, cellWidth, gridHeight));
  }
  return _PaperLayout(cardRect: cardRect, gridRect: gridRect, cells: cells);
}
