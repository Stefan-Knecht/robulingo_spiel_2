// ------------------------------------------------------------
// Ziel (Laien): Pokal-Button mit optionalem wackelndem Hourglass anzeigen.
// Strategie: Statefull widget hält eine kleine Wiggle-Animation für das Hourglass.
// Schritte: Hourglass links vom Pokal rendern, optional wackeln lassen, Pokal tapbar.
// Tücken: Hourglass nur sichtbar, wenn show=true (Pokal freigeschaltet); Wiggle läuft per AnimationController.
// ------------------------------------------------------------
import 'package:flutter/material.dart';

class DashboardButtonRow extends StatefulWidget {
  const DashboardButtonRow({
    super.key,
    required this.show,
    required this.onTap,
    this.showHourglass = false,
    this.hourglassWiggle = false,
    this.hourglassMicStage = -1,
    this.hourglassMicOn = false,
    this.hourglassMicPaused = false,
    this.onHourglassTap,
  });

  final bool show;
  final VoidCallback onTap;
  final bool showHourglass;
  final bool hourglassWiggle;
  final int hourglassMicStage;
  final bool hourglassMicOn;
  final bool hourglassMicPaused;
  final VoidCallback? onHourglassTap;

  @override
  State<DashboardButtonRow> createState() => _DashboardButtonRowState();
}

class _DashboardButtonRowState extends State<DashboardButtonRow> with SingleTickerProviderStateMixin {
  late AnimationController _wiggle;

  @override
  void initState() {
    super.initState();
    _wiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      lowerBound: -0.12,
      upperBound: 0.12,
    );
    _syncWiggle();
  }

  @override
  void didUpdateWidget(covariant DashboardButtonRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hourglassWiggle != widget.hourglassWiggle ||
        oldWidget.showHourglass != widget.showHourglass ||
        oldWidget.hourglassMicStage != widget.hourglassMicStage ||
        oldWidget.hourglassMicOn != widget.hourglassMicOn ||
        oldWidget.hourglassMicPaused != widget.hourglassMicPaused) {
      _syncWiggle();
    }
  }

  void _syncWiggle() {
    final bool isListeningStage =
        widget.hourglassMicStage == 0 || widget.hourglassMicStage == 2;
    final bool recordingActive =
        isListeningStage && widget.hourglassMicOn && !widget.hourglassMicPaused;
    if (widget.showHourglass && widget.hourglassWiggle && recordingActive) {
      _wiggle.repeat(reverse: true);
    } else {
      _wiggle.stop();
      _wiggle.value = 0.0;
    }
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showHourglass && !widget.show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.showHourglass)
            AnimatedBuilder(
              animation: _wiggle,
              builder: (context, child) {
                final angle = _wiggle.value;
                final dx = 3 * (angle / 0.12);
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: Transform.rotate(
                    angle: angle,
                    child: child,
                  ),
                );
              },
              child: Container(
                width: 56,
                height: 56,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: widget.onHourglassTap,
                  child: Center(
                    child: _hourglassIcon(),
                  ),
                ),
              ),
            ),
          if (widget.show) _dashButton(onTap: widget.onTap),
        ],
      ),
    );
  }

  Widget _hourglassIcon() {
    final bool isListeningStage =
        widget.hourglassMicStage == 0 || widget.hourglassMicStage == 2;
    final bool isHintStage = widget.hourglassMicStage == 1;
    final bool recordingActive =
        isListeningStage && widget.hourglassMicOn && !widget.hourglassMicPaused;
    final IconData icon = isHintStage ? Icons.volume_up : Icons.mic;
    final Color color = isHintStage
        ? const Color(0xFFF39C12)
        : (recordingActive ? const Color(0xFF0FA958) : Colors.black54);
    return Icon(icon, size: 24, color: color);
  }

  Widget _dashButton({required VoidCallback onTap}) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events, size: 24, color: Colors.black87),
          ],
        ),
      ),
    );
  }
}
