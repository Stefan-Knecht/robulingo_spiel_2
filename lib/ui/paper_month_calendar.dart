import 'dart:math';

import 'package:flutter/material.dart';
import 'package:robulingo_flutter/utils/color_utils.dart';

import '../util/handdrawn.dart';
import 'paper_week_calendar.dart';

class PaperMonthCalendar extends StatelessWidget {
  const PaperMonthCalendar({
    super.key,
    required this.days,
    required this.todayIndex,
    this.animateMarks = true,
    this.onTapDay,
    this.paperStyle = const PaperStyle(),
    this.thresholdSeconds = 0,
    this.todayIncompleteColor,
  });

  final List<DayStatus> days;
  final int todayIndex;
  final bool animateMarks;
  final void Function(int index)? onTapDay;
  final PaperStyle paperStyle;
  final int thresholdSeconds;
  final Color? todayIncompleteColor;

  @override
  Widget build(BuildContext context) {
    assert(days.length == 28, "days must be length 28");
    return _PaperMonthCalendarBody(
      days: days,
      todayIndex: todayIndex,
      animateMarks: animateMarks,
      onTapDay: onTapDay,
      paperStyle: paperStyle,
      thresholdSeconds: thresholdSeconds,
      todayIncompleteColor: todayIncompleteColor,
    );
  }
}

class _PaperMonthCalendarBody extends StatefulWidget {
  const _PaperMonthCalendarBody({
    required this.days,
    required this.todayIndex,
    required this.animateMarks,
    required this.onTapDay,
    required this.paperStyle,
    required this.thresholdSeconds,
    required this.todayIncompleteColor,
  });

  final List<DayStatus> days;
  final int todayIndex;
  final bool animateMarks;
  final void Function(int index)? onTapDay;
  final PaperStyle paperStyle;
  final int thresholdSeconds;
  final Color? todayIncompleteColor;

  @override
  State<_PaperMonthCalendarBody> createState() =>
      _PaperMonthCalendarBodyState();
}

class _PaperMonthCalendarBodyState extends State<_PaperMonthCalendarBody>
    with TickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 600);
  static const Duration _stagger = Duration(milliseconds: 24);

  late final List<AnimationController> _controllers;
  late List<bool> _lastMarked;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      28,
      (_) => AnimationController(vsync: this, duration: _duration),
    );
    _lastMarked = widget.days
        .map((d) => d.qualified || d.rivalQualified)
        .toList(growable: false);
    for (int i = 0; i < 28; i++) {
      _controllers[i].value =
          widget.days[i].qualified || widget.days[i].rivalQualified ? 1.0 : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant _PaperMonthCalendarBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (int i = 0; i < 28; i++) {
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
      aspectRatio: 7 / 4.5,
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
                    painter: PaperMonthCalendarPainter(
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
                        painter: MonthMarksPainter(
                          days: widget.days,
                          todayIndex: widget.todayIndex,
                          markProgress: progress,
                          paperStyle: widget.paperStyle,
                          seedBase: _seedBase(),
                          thresholdSeconds: widget.thresholdSeconds,
                          todayIncompleteColor: widget.todayIncompleteColor,
                        ),
                      );
                    },
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: _MonthDateOverlay(days: widget.days),
                  ),
                ),
                Positioned.fill(
                  child: _MonthSemanticsOverlay(
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

class _MonthDateOverlay extends StatelessWidget {
  const _MonthDateOverlay({
    required this.days,
  });

  final List<DayStatus> days;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: const Color(0xAA2C3A42),
        );
    return Column(
      children: List.generate(4, (row) {
        return Expanded(
          child: Row(
            children: List.generate(7, (col) {
              final index = row * 7 + col;
              final date = days[index].date.toLocal();
              final dayLabel = localizations.formatDecimal(date.day);
              return Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 7, top: 5),
                    child: Text(
                      dayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: textStyle,
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _MonthSemanticsOverlay extends StatelessWidget {
  const _MonthSemanticsOverlay({
    required this.days,
    required this.onTapDay,
  });

  final List<DayStatus> days;
  final void Function(int index)? onTapDay;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return Column(
      children: List.generate(4, (row) {
        return Expanded(
          child: Row(
            children: List.generate(7, (col) {
              final index = row * 7 + col;
              final status = days[index];
              final dateLabel = localizations.formatFullDate(
                status.date.toLocal(),
              );
              final label = status.qualified
                  ? (status.rivalQualified
                      ? "$dateLabel, completed, rival trained"
                      : "$dateLabel, completed")
                  : (status.rivalQualified
                      ? "$dateLabel, rival trained"
                      : "$dateLabel, not completed");
              return Expanded(
                child: Semantics(
                  button: onTapDay != null,
                  label: label,
                  onTap: onTapDay == null ? null : () => onTapDay?.call(index),
                  child: const SizedBox.expand(),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class PaperMonthCalendarPainter extends CustomPainter {
  final PaperStyle paperStyle;
  final int seedBase;

  PaperMonthCalendarPainter({
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
    final count =
        ((size.width * size.height) / 2600).round().clamp(40, 220).toInt();
    final paint = Paint()
      ..color = Colors.black.withOpacityValue(paperStyle.noiseOpacity);
    for (int i = 0; i < count; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final radius = 0.4 + rng.nextDouble() * 0.8;
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  void _drawBinding(Canvas canvas, _MonthLayout layout) {
    const holes = 4;
    final span = layout.gridRect.width;
    final spacing = span / (holes + 1);
    final y = layout.cardRect.top + paperStyle.cardPadding * 0.6;
    for (int i = 0; i < holes; i++) {
      final x = layout.gridRect.left + spacing * (i + 1);
      final shadowPaint = Paint()..color = paperStyle.ringShadowColor;
      canvas.drawCircle(
          Offset(x, y + 1.2), paperStyle.ringHoleRadius + 0.6, shadowPaint);
      final holePaint = Paint()..color = paperStyle.ringHoleColor;
      canvas.drawCircle(Offset(x, y), paperStyle.ringHoleRadius, holePaint);
    }
  }

  void _drawGrid(Canvas canvas, _MonthLayout layout) {
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
        jitteredLinePath(tl, tr, seedBase + lineIndex++,
            jitter: paperStyle.lineJitter),
        jitteredLinePath(tr, br, seedBase + lineIndex++,
            jitter: paperStyle.lineJitter),
        jitteredLinePath(br, bl, seedBase + lineIndex++,
            jitter: paperStyle.lineJitter),
        jitteredLinePath(bl, tl, seedBase + lineIndex++,
            jitter: paperStyle.lineJitter),
      ];
      for (final path in paths) {
        canvas.drawPath(path, jitterPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PaperMonthCalendarPainter oldDelegate) {
    return oldDelegate.paperStyle != paperStyle ||
        oldDelegate.seedBase != seedBase;
  }
}

class MonthMarksPainter extends CustomPainter {
  final List<DayStatus> days;
  final int todayIndex;
  final List<double> markProgress;
  final PaperStyle paperStyle;
  final int seedBase;
  final int thresholdSeconds;
  final Color? todayIncompleteColor;

  MonthMarksPainter({
    required this.days,
    required this.todayIndex,
    required this.markProgress,
    required this.paperStyle,
    required this.seedBase,
    required this.thresholdSeconds,
    required this.todayIncompleteColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _layoutForSize(size, paperStyle);
    final todayLocalKey = _dayKeyLocal(DateTime.now());
    final localMatchIndex = days.indexWhere(
      (day) => _dayKeyLocal(day.date.toLocal()) == todayLocalKey,
    );
    for (int i = 0; i < layout.cells.length; i++) {
      final cell = layout.cells[i];
      final isToday =
          localMatchIndex != -1 ? i == localMatchIndex : i == todayIndex;
      Color? todayBadgeColor;
      if (isToday) {
        final activeSeconds = days[i].activeSeconds;
        final isInProgress =
            thresholdSeconds > 0 && activeSeconds < thresholdSeconds;
        final Color baseColor = isInProgress
            ? (todayIncompleteColor ?? const Color(0xFF6CCB5F))
            : paperStyle.playerMarkColor;
        todayBadgeColor = baseColor;
        final glowColor = isInProgress ? baseColor : paperStyle.glowColor;
        _drawTodayFill(
          canvas,
          cell,
          baseColor,
          fillOpacity: isInProgress ? 0.6 : 0.22,
          strokeOpacity: isInProgress ? 0.9 : 0.6,
        );
        _drawTodayGlow(canvas, cell, glowColor, isInProgress: isInProgress);
      }
      if (days[i].qualified) {
        final progress = i < markProgress.length ? markProgress[i] : 1.0;
        _drawPencilX(canvas, cell, progress, seedBase + 300 + i);
      }
      if (days[i].rivalQualified) {
        final progress = i < markProgress.length ? markProgress[i] : 1.0;
        _drawRivalCircle(canvas, cell, progress, seedBase + 600 + i);
      }
      if (isToday) {
        _drawPaperclip(canvas, cell);
        _drawTodayBadge(
          canvas,
          cell,
          todayBadgeColor ?? paperStyle.playerMarkColor,
        );
      }
    }
  }

  DateTime _dayKeyLocal(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  void _drawTodayFill(
    Canvas canvas,
    Rect cell,
    Color fillColor, {
    double fillOpacity = 0.45,
    double strokeOpacity = 0.7,
  }) {
    final inner = cell.deflate(paperStyle.gridStrokeWidth + 1.0);
    final fillPaint = Paint()
      ..color = fillColor.withOpacityValue(fillOpacity)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        inner,
        Radius.circular(paperStyle.cellRadius),
      ),
      fillPaint,
    );
    final strokePaint = Paint()
      ..color = fillColor.withOpacityValue(strokeOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        inner,
        Radius.circular(paperStyle.cellRadius),
      ),
      strokePaint,
    );
  }

  void _drawTodayGlow(
    Canvas canvas,
    Rect cell,
    Color glowColor, {
    required bool isInProgress,
  }) {
    final glowRect = cell.inflate(paperStyle.glowInflate);
    final glowPaint = Paint()
      ..color = glowColor.withOpacityValue(isInProgress ? 0.32 : 0.22)
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
    final outerRect =
        Rect.fromCenter(center: center, width: width, height: height);
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

  void _drawTodayBadge(Canvas canvas, Rect cell, Color fillColor) {
    final radius = min(cell.width, cell.height) * 0.085;
    final center = Offset(
      cell.right - radius * 1.1,
      cell.top + radius * 1.1,
    );
    final fillPaint = Paint()
      ..color = fillColor.withOpacityValue(0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fillPaint);
    final ringPaint = Paint()
      ..color = paperStyle.gridLineColor.withOpacityValue(0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, ringPaint);
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
  bool shouldRepaint(covariant MonthMarksPainter oldDelegate) {
    return oldDelegate.days != days ||
        oldDelegate.todayIndex != todayIndex ||
        oldDelegate.markProgress != markProgress ||
        oldDelegate.paperStyle != paperStyle ||
        oldDelegate.seedBase != seedBase ||
        oldDelegate.thresholdSeconds != thresholdSeconds ||
        oldDelegate.todayIncompleteColor != todayIncompleteColor;
  }
}

class _MonthLayout {
  final Rect cardRect;
  final Rect gridRect;
  final List<Rect> cells;
  const _MonthLayout({
    required this.cardRect,
    required this.gridRect,
    required this.cells,
  });
}

_MonthLayout _layoutForSize(Size size, PaperStyle style) {
  final cardRect = Offset.zero & size;
  final padding = style.cardPadding;
  final gridTop = padding + style.bindingHeight;
  final gridHeight = max(0.0, size.height - gridTop - padding);
  final gridWidth = max(0.0, size.width - padding * 2);
  final totalGapX = style.cellGap * 6;
  final totalGapY = style.cellGap * 3;
  final cellWidth = max(0.0, (gridWidth - totalGapX) / 7);
  final cellHeight = max(0.0, (gridHeight - totalGapY) / 4);
  final gridLeft = padding;
  final gridRect = Rect.fromLTWH(gridLeft, gridTop, gridWidth, gridHeight);

  final cells = <Rect>[];
  for (int row = 0; row < 4; row++) {
    for (int col = 0; col < 7; col++) {
      final left = gridLeft + col * (cellWidth + style.cellGap);
      final top = gridTop + row * (cellHeight + style.cellGap);
      cells.add(Rect.fromLTWH(left, top, cellWidth, cellHeight));
    }
  }
  return _MonthLayout(cardRect: cardRect, gridRect: gridRect, cells: cells);
}
