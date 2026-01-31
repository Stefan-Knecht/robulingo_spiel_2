// ------------------------------------------------------------
// Ziel (Laien): Erste Seite zur Sprachauswahl mit Logo.
// Strategie: Vollflächiger Grid aus Flaggen, ein Tap reicht.
// Schritte: RL-Logo zeigen, Wrap mit Flaggen bauen, Auswahl via Callback.
// Tücken: Bei neuen Sprachen muss die Flaggenmap in constants.dart gepflegt werden.
// ------------------------------------------------------------
import 'dart:math';

import 'package:flutter/material.dart';

import '../constants.dart';

class LangSelector extends StatefulWidget {
  const LangSelector({
    super.key,
    required this.onSelect,
    this.showUserIdRecovery = false,
    this.onRecoverUserId,
  });

  final void Function(String lang) onSelect;
  final bool showUserIdRecovery;
  final void Function(String userId)? onRecoverUserId;

  @override
  State<LangSelector> createState() => _LangSelectorState();
}

class _LangSelectorState extends State<LangSelector> {
  final TextEditingController _userIdController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  void _submitUserId() {
    final raw = _userIdController.text.trim();
    if (raw.isEmpty) return;
    widget.onRecoverUserId?.call(raw);
    _userIdController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final double logoHeight = size.height * (isLandscape ? 0.16 : 0.2);
    final double logoWidth = size.width * (isLandscape ? 0.4 : 0.85);
    final double tileSize =
        isLandscape ? min(84.0, size.height * 0.2) : 96.0;
    final double flagFontSize = tileSize * 0.48;
    final double spacing = isLandscape ? 16.0 : 24.0;
    final Widget recoveryPanel = widget.showUserIdRecovery
        ? Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Column(
              children: [
                const Text(
                  'User ID wiederherstellen',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: isLandscape ? 320 : double.infinity,
                  child: TextField(
                    controller: _userIdController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'User ID eingeben',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _submitUserId(),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed:
                      widget.onRecoverUserId == null ? null : _submitUserId,
                  child: const Text('User ID verwenden'),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isLandscape ? 16 : 32, horizontal: 24),
      child: isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: logoWidth,
                  child: Image.asset(
                    'assets/icons/RL_logo.webp',
                    width: logoWidth,
                    height: logoHeight,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: spacing,
                        runSpacing: spacing,
                        children: langChoices
                            .map(
                              (l) => GestureDetector(
                                onTap: () => widget.onSelect(l),
                                child: Container(
                                  width: tileSize,
                                  height: tileSize,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.black, width: 2),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                                    ],
                                  ),
                                  child: Text(
                                    langFlags[l] ?? '',
                                    style: TextStyle(fontSize: flagFontSize),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
                if (widget.showUserIdRecovery) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 240,
                    child: SingleChildScrollView(
                      child: recoveryPanel,
                    ),
                  ),
                ],
              ],
            )
          : Column(
              children: [
                Image.asset(
                  'assets/icons/RL_logo.webp',
                  width: logoWidth,
                  height: logoHeight,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: spacing,
                      runSpacing: spacing,
                      children: langChoices
                          .map(
                            (l) => GestureDetector(
                              onTap: () => widget.onSelect(l),
                              child: Container(
                                width: tileSize,
                                height: tileSize,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                                  ],
                                ),
                                child: Text(
                                  langFlags[l] ?? '',
                                  style: TextStyle(fontSize: flagFontSize),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                recoveryPanel,
              ],
            ),
    );
  }
}
