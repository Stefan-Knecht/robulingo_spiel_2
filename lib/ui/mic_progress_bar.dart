// ------------------------------------------------------------
// Ziel (Laien): Fortschrittsbalken für Naming-Hörfenster unten anzeigen.
// Strategie: AnimatedBuilder nutzt micAnimation und Stage-Farben.
// Schritte: Basis-Leiste, Fortschritt, bewegte Mic-Blase rendern.
// Tücken: Breite hängt von Bildschirmbreite ab; nur zeigen, wenn Naming aktiv.
// ------------------------------------------------------------
import 'package:flutter/material.dart';

class MicProgressBar extends StatelessWidget {
  const MicProgressBar({
    super.key,
    required this.animation,
    required this.micStage,
    required this.micOn,
  });

  final Animation<double> animation;
  final int micStage;
  final bool micOn;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final fullWidth = MediaQuery.of(context).size.width - 24;
        final progressWidth = fullWidth * (animation.value.clamp(0.0, 1.0));
        Color progColor;
        if (micStage == 0) {
          progColor = Colors.blue;
        } else if (micStage == 1) {
          progColor = Colors.orange;
        } else if (micStage == 2) {
          progColor = Colors.green;
        } else {
          progColor = Colors.grey.shade400;
        }
        final bool isHintStage = micStage == 1;
        final IconData movingIcon =
            isHintStage ? Icons.volume_up : Icons.mic;
        final Color bubbleColor = isHintStage
            ? Colors.orangeAccent
            : (micOn ? Colors.greenAccent : Colors.white);
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              width: fullWidth,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Container(
              width: progressWidth,
              height: 6,
              decoration: BoxDecoration(
                color: progColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Positioned(
              left: (progressWidth - 20).clamp(0.0, fullWidth - 40),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4)
                  ],
                ),
                child: Icon(movingIcon, size: 18),
              ),
            ),
          ],
        );
      },
    );
  }
}
