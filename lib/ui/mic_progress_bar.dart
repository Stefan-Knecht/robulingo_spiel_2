// ------------------------------------------------------------
// Ziel (Laien): Fortschrittsbalken für Naming-Hörfenster unten anzeigen.
// Strategie: AnimatedBuilder nutzt micAnimation und Stage-Farben.
// Schritte: Basis-Leiste, Fortschritt, bewegte Mic-Blase rendern.
// Tücken: Breite hängt von Bildschirmbreite ab; nur zeigen, wenn Naming aktiv.
// ------------------------------------------------------------
import 'dart:math' as math;

import 'package:flutter/material.dart';

class MicProgressBar extends StatelessWidget {
  const MicProgressBar({
    super.key,
    required this.animation,
    required this.micStage,
    required this.micOn,
    required this.firstWindowSeconds,
    required this.repeatWindowSeconds,
    this.hintWindowSeconds = 3,
  });

  final Animation<double> animation;
  final int micStage;
  final bool micOn;
  final int firstWindowSeconds;
  final int repeatWindowSeconds;
  final int hintWindowSeconds;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final bool isListeningStage = micStage == 0 || micStage == 2;
        final bool firstListening = micStage == 0;
        final bool hintPlaying = micStage == 1;
        final bool repeatListening = micStage == 2;
        final double pulseScale = isListeningStage && micOn
            ? (0.94 + 0.14 * math.sin(animation.value * math.pi * 2 * 10).abs())
                .clamp(0.9, 1.08)
            : 1.0;
        final bool isHintStage = micStage == 1;
        final IconData movingIcon = isHintStage ? Icons.volume_up : Icons.mic;
        final Color bubbleColor = isHintStage
            ? const Color(0xFFFFF2D6)
            : (micOn ? const Color(0xFFE8F7EE) : Colors.white);
        // Low-risk dynamics: moving indicator is visual-only (not strict timing).
        final double loop = animation.value.clamp(0.0, 1.0);
        final double pingPong =
            loop <= 0.5 ? (loop * 2.0) : ((1.0 - loop) * 2.0);
        final double sweepX = -1.0 + (2.0 * pingPong);
        final int firstFlex = firstWindowSeconds.clamp(1, 60);
        final int hintFlex = hintWindowSeconds.clamp(1, 60);
        final int repeatFlex = repeatWindowSeconds.clamp(1, 60);
        Widget stageSegment({
          required bool active,
          required bool done,
          required Color activeColor,
          required int flex,
          bool showPointer = false,
        }) {
          final Color fill = active
              ? activeColor
              : (done
                  ? activeColor.withValues(alpha: 0.35)
                  : const Color(0xFFD2D8DD));
          return Expanded(
            flex: flex,
            child: SizedBox(
              height: 24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: fill),
                    if (showPointer)
                      Align(
                        alignment: Alignment(sweepX, 0),
                        child: Container(
                          width: 8,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFF2C3A42),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: const Color(0xFF6E7A84), width: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                stageSegment(
                  active: firstListening && micOn,
                  done: micStage > 0,
                  activeColor: const Color(0xFF0FA958),
                  flex: firstFlex,
                  showPointer: firstListening && micOn,
                ),
                const SizedBox(width: 6),
                stageSegment(
                  active: hintPlaying,
                  done: micStage > 1,
                  activeColor: const Color(0xFFF39C12),
                  flex: hintFlex,
                ),
                const SizedBox(width: 6),
                stageSegment(
                  active: repeatListening && micOn,
                  done: false,
                  activeColor: const Color(0xFF0FA958),
                  flex: repeatFlex,
                  showPointer: repeatListening && micOn,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Transform.scale(
              scale: pulseScale,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF3F4A52), width: 1),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6)
                  ],
                ),
                child: Icon(
                  movingIcon,
                  size: 18,
                  color: isListeningStage && micOn
                      ? const Color(0xFF0FA958)
                      : (isHintStage
                          ? const Color(0xFFF39C12)
                          : const Color(0xFF607D8B)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
