// ------------------------------------------------------------
// Ziel (Laien): Explizite Mikro-Freigabe einholen, bevor Benennung startet.
// Verbindung: Von robulingo_app.dart getriggert, bevor NamingFlow läuft; steuert namingBlock bei Ablehnung/Timeout.
// Tücken: Timeout nach 15s; Ergebnis wird über Callbacks nach oben gereicht.
// ------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MicGate extends StatefulWidget {
  const MicGate({
    super.key,
    required this.onAllow,
    required this.onDeny,
    required this.onTimeout,
  });

  final VoidCallback onAllow;
  final VoidCallback onDeny;
  final VoidCallback onTimeout;

  @override
  State<MicGate> createState() => _MicGateState();
}

class _MicGateState extends State<MicGate> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: -0.18,
      upperBound: 0.18,
    )..repeat(reverse: true);
    Future.delayed(const Duration(seconds: 15), () {
      if (_handled) return;
      _handled = true;
      widget.onTimeout();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleAllow() {
    if (_handled) return;
    _handled = true;
    widget.onAllow();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter) {
            _handleAllow();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_downward,
                      size: 64, color: Colors.green.shade800),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_ctrl.value * 20, 0),
                        child: child,
                      );
                    },
                    child: GestureDetector(
                      onTap: _handleAllow,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.greenAccent,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                          ],
                        ),
                        child: const Icon(Icons.mic, size: 54, color: Colors.black),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 24,
              right: 24,
              child: GestureDetector(
                onTap: () {
                  if (_handled) return;
                  _handled = true;
                  widget.onDeny();
                },
                child: Image.asset(
                  'assets/icons/mic_delay.webp',
                  width: 34,
                  height: 34,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
