// ------------------------------------------------------------
// Ziel (Laien): Erste Seite zur Sprachauswahl mit Logo.
// Strategie: Vollflächiger Grid aus Flaggen, ein Tap reicht.
// Schritte: RL-Logo zeigen, Wrap mit Flaggen bauen, Auswahl via Callback.
// Tücken: Bei neuen Sprachen muss die Flaggenmap in constants.dart gepflegt werden.
// ------------------------------------------------------------
import 'dart:math';

import 'package:flutter/material.dart';

import '../constants.dart';

class LangSelector extends StatelessWidget {
  const LangSelector({super.key, required this.onSelect});

  final void Function(String lang) onSelect;

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
                                onTap: () => onSelect(l),
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
                              onTap: () => onSelect(l),
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
              ],
            ),
    );
  }
}
