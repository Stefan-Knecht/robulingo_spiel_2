// ------------------------------------------------------------
// Ziel (Laien): Fortschrittsbalken für Naming-Hörfenster unten anzeigen.
// Strategie: zeitbasierte Stage-Fortschritte (statt blinkender Aktivitätsanzeige).
// Schritte: Stage-Start merken, Fortschritt pro Segment aus verstrichener Zeit berechnen.
// Tücken: Breite hängt von Bildschirmbreite ab; nur zeigen, wenn Naming aktiv.
// ------------------------------------------------------------
import 'dart:async';

import 'package:flutter/material.dart';

class MicProgressBar extends StatefulWidget {
  const MicProgressBar({
    super.key,
    required this.micStage,
    required this.micOn,
    required this.isPaused,
    required this.firstWindowSeconds,
    required this.repeatWindowSeconds,
    this.hintWindowSeconds = 3,
  });

  final int micStage;
  final bool micOn;
  final bool isPaused;
  final int firstWindowSeconds;
  final int repeatWindowSeconds;
  final int hintWindowSeconds;

  @override
  State<MicProgressBar> createState() => _MicProgressBarState();
}

class _MicProgressBarState extends State<MicProgressBar> {
  DateTime _stageStartedAt = DateTime.now();
  DateTime? _pausedAt;
  Duration _pausedTotal = Duration.zero;
  Timer? _ticker;

  bool get _stageActive {
    if (widget.micStage == 1) return true;
    return (widget.micStage == 0 || widget.micStage == 2) && widget.micOn;
  }

  void _markStageStart() {
    _stageStartedAt = DateTime.now();
    _pausedAt = widget.isPaused ? DateTime.now() : null;
    _pausedTotal = Duration.zero;
  }

  void _syncTicker() {
    if (!_stageActive) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    if (_ticker != null) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || !_stageActive) return;
      setState(() {});
    });
  }

  double _elapsedProgress(int seconds) {
    final int durationMs = (seconds <= 0 ? 1 : seconds * 1000);
    final now = DateTime.now();
    var paused = _pausedTotal;
    if (widget.isPaused && _pausedAt != null) {
      paused += now.difference(_pausedAt!);
    }
    final int rawElapsedMs = now.difference(_stageStartedAt).inMilliseconds;
    final int pausedMs = paused.inMilliseconds;
    final int elapsedMs = (rawElapsedMs - pausedMs).clamp(0, durationMs);
    return elapsedMs / durationMs;
  }

  @override
  void initState() {
    super.initState();
    _markStageStart();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant MicProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool stageChanged = oldWidget.micStage != widget.micStage;
    final bool pausedChanged = oldWidget.isPaused != widget.isPaused;
    if (pausedChanged) {
      if (widget.isPaused) {
        _pausedAt = DateTime.now();
      } else if (_pausedAt != null) {
        _pausedTotal += DateTime.now().difference(_pausedAt!);
        _pausedAt = null;
      }
    }
    final bool resumedFromPause = oldWidget.isPaused &&
        !widget.isPaused &&
        (widget.micStage == 0 || widget.micStage == 2);
    final bool listeningRestarted = oldWidget.micOn != widget.micOn &&
        widget.micOn &&
        (widget.micStage == 0 || widget.micStage == 2);
    if (stageChanged || (listeningRestarted && !resumedFromPause)) {
      _markStageStart();
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool firstListening = widget.micStage == 0;
    final bool hintPlaying = widget.micStage == 1;
    final bool repeatListening = widget.micStage == 2;
    final int firstFlex = widget.firstWindowSeconds.clamp(1, 60);
    final int hintFlex = widget.hintWindowSeconds.clamp(1, 60);
    final int repeatFlex = widget.repeatWindowSeconds.clamp(1, 60);

    Widget stageSegment({
      required bool active,
      required bool done,
      required Color activeColor,
      required int flex,
      required double progress,
    }) {
      final Color base = done
          ? activeColor.withValues(alpha: 0.25)
          : const Color(0xFFD2D8DD);
      final double clampedProgress = progress.clamp(0.0, 1.0);
      return Expanded(
        flex: flex,
        child: SizedBox(
          height: 24,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: base),
                if (clampedProgress > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: clampedProgress,
                      child: Container(
                        color: active
                            ? activeColor
                            : activeColor.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border:
                        Border.all(color: const Color(0xFF6E7A84), width: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final double firstProgress =
        firstListening && (widget.micOn || widget.isPaused)
        ? _elapsedProgress(widget.firstWindowSeconds)
        : (widget.micStage > 0 ? 1.0 : 0.0);
    final double hintProgress = hintPlaying
        ? _elapsedProgress(widget.hintWindowSeconds)
        : (widget.micStage > 1 ? 1.0 : 0.0);
    final double repeatProgress =
        repeatListening && (widget.micOn || widget.isPaused)
        ? _elapsedProgress(widget.repeatWindowSeconds)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            stageSegment(
              active: firstListening && widget.micOn,
              done: widget.micStage > 0,
              activeColor: const Color(0xFF0FA958),
              flex: firstFlex,
              progress: firstProgress,
            ),
            const SizedBox(width: 6),
            stageSegment(
              active: hintPlaying,
              done: widget.micStage > 1,
              activeColor: const Color(0xFFF39C12),
              flex: hintFlex,
              progress: hintProgress,
            ),
            const SizedBox(width: 6),
            stageSegment(
              active: repeatListening && widget.micOn,
              done: false,
              activeColor: const Color(0xFF0FA958),
              flex: repeatFlex,
              progress: repeatProgress,
            ),
          ],
        ),
      ],
    );
  }
}
