import 'package:flutter/material.dart';

class RunProgressRing extends StatefulWidget {
  const RunProgressRing(
    this.runsDone, {
    super.key,
    this.size = 30,
    this.strokeWidth = 3,
    this.color,
    this.trackColor,
  });

  final int runsDone;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? trackColor;

  @override
  State<RunProgressRing> createState() => _RunProgressRingState();
}

class _RunProgressRingState extends State<RunProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  static const int _goalRuns = 200;

  bool _isCycleCompleted(int runs) {
    return runs > 0 && runs % _goalRuns == 0;
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 55),
    ]).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOutCubic,
    ));
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    if (_isCycleCompleted(widget.runsDone)) {
      _pulseController.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(covariant RunProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isCycleCompleted(oldWidget.runsDone) &&
        _isCycleCompleted(widget.runsDone)) {
      _pulseController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int safeRuns = widget.runsDone < 0 ? 0 : widget.runsDone;
    final bool completedCycle = _isCycleCompleted(safeRuns);
    final int cycleRuns = safeRuns % _goalRuns;
    final double progress = completedCycle ? 1.0 : (cycleRuns / _goalRuns);
    final Color ringColor = widget.color ?? const Color(0xFF2E7D32);
    final Color ringTrackColor = widget.trackColor ?? const Color(0x1F2E7D32);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final double glowOpacity = _glowAnimation.value * 0.35;
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: glowOpacity <= 0
                  ? const []
                  : [
                      BoxShadow(
                        color: ringColor.withValues(alpha: glowOpacity),
                        blurRadius: 10 + (8 * _glowAnimation.value),
                        spreadRadius: 1.5 * _glowAnimation.value,
                      ),
                    ],
            ),
            child: child,
          ),
        );
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CircularProgressIndicator(
          value: progress,
          strokeWidth: widget.strokeWidth,
          strokeCap: StrokeCap.round,
          color: ringColor,
          backgroundColor: ringTrackColor,
        ),
      ),
    );
  }
}
