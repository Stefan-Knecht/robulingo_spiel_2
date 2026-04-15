// ------------------------------------------------------------
// Ziel (Laien): Minimaler Text/Demo-Screen, um das Hexagon-Rennen manuell mit "Richtig"/"Falsch" Klicks zu testen.
// Strategie: HexagonController + HexagonTrack einbinden, Buttons zum Auslösen der Schritte, kurzer Status-Text für Wins.
// ------------------------------------------------------------
import 'package:flutter/material.dart';

import '../logic/hexagon_controller.dart';
import 'hexagon_track.dart';

class HexagonDemoPage extends StatefulWidget {
  const HexagonDemoPage({super.key});

  @override
  State<HexagonDemoPage> createState() => _HexagonDemoPageState();
}

class _HexagonDemoPageState extends State<HexagonDemoPage> {
  late HexagonController controller;
  final List<bool> _recent = [];
  String status = 'Tippe auf Richtig/Falsch, um die Kreise zu bewegen.';

  @override
  void initState() {
    super.initState();
    controller = HexagonController(
      onChanged: () => setState(() {}),
      onYouWin: () => setState(() => status = 'Du hast gewonnen!'),
      onRivalWin: () => setState(() => status = 'Rival hat gewonnen.'),
      accuracyProvider: () =>
          _recent.isEmpty ? [true] : List<bool>.from(_recent),
      onMove: (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _record(bool correct) {
    _recent.add(correct);
    if (_recent.length > 10) {
      _recent.removeAt(0);
    }
    controller.applyPlayerStep(correct);
    if (status.startsWith('Du hast') || status.startsWith('Rival')) {
      // Reset Status nach einem Win für die nächsten Schritte.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        setState(() => status = 'Weiter geht\'s.');
      });
    }
  }

  void _reset() {
    _recent.clear();
    status = 'Reset. Tippe auf Richtig/Falsch, um erneut zu starten.';
    controller.reset(clearWins: false);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hexagon Race Demo'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  status,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
              HexagonTrack(
                youIndex: controller.state.youIndex,
                rivalIndex: controller.state.rivalIndex,
                youFlagVisible: controller.state.youFlagVisible,
                rivalFlagVisible: controller.state.rivalFlagVisible,
                youFlagAngle: controller.state.youFlagAngle,
                rivalFlagAngle: controller.state.rivalFlagAngle,
                youFlagShowIndex: controller.state.youFlagShowIndex,
                rivalFlagShowIndex: controller.state.rivalFlagShowIndex,
                youTrail: controller.state.youTrail,
                rivalTrail: controller.state.rivalTrail,
                tooltipLanguageCode: 'en',
                mountainTheme: 'default',
                mountainYouWon: false,
                mountainRivalWon: false,
                wins: controller.state.winsYou,
                rivalWins: controller.state.winsRival,
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _record(true),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Richtig'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _record(false),
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: const Text('Falsch'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                  OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Wins: Du ${controller.state.winsYou} | Rival ${controller.state.winsRival}',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
