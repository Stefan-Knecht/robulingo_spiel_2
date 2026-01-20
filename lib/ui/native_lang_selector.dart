// ------------------------------------------------------------
// Ziel (Laien): Muttersprache für zweizeilige Anzeige wählen (oder überspringen).
// Verbindung: robulingo_app.dart zeigt diese Seite bei allen Startcurricula vor dem Laden.
// Tücken: Anzeige nutzt Flags aus constants.dart; null = keine zweite Zeile im Session-Screen.
// ------------------------------------------------------------
import 'dart:math';

import 'package:flutter/material.dart';

import '../constants.dart';

class NativeLangSelector extends StatelessWidget {
  const NativeLangSelector(
      {super.key, required this.targetLang, required this.onSelect});

  final String targetLang;
  final void Function(String?) onSelect; // null = keine Muttersprache

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final double logoHeight = size.height * (isLandscape ? 0.16 : 0.2);
    final double logoWidth = size.width * (isLandscape ? 0.4 : 0.85);
    final double tileSize = isLandscape ? min(56.0, size.height * 0.16) : 64.0;
    final double flagFontSize = tileSize * 0.5;
    final double arrowSize = isLandscape ? 28.0 : 36.0;
    final double targetFontSize = isLandscape ? 32.0 : 40.0;

    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: isLandscape ? 16 : 32, horizontal: 24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Image.asset(
              'assets/icons/RL_logo.webp',
              width: logoWidth,
              height: logoHeight,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => onSelect(null),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDFF4E7),
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black, width: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Icon(Icons.check, size: 40),
            ),
            const SizedBox(height: 110),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: isLandscape ? 12 : 16,
                    runSpacing: isLandscape ? 12 : 16,
                    children: langChoices
                        .map(
                          (l) => _FlagButton(
                            flag: langFlags[l] ?? '',
                            label: l,
                            onTap: () => onSelect(l),
                            size: tileSize,
                            fontSize: flagFontSize,
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.arrow_forward, size: arrowSize),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    langFlags[targetLang] ?? targetLang,
                    style: TextStyle(fontSize: targetFontSize),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FlagButton extends StatelessWidget {
  const _FlagButton({
    required this.flag,
    required this.label,
    required this.onTap,
    required this.size,
    required this.fontSize,
  });
  final String flag;
  final String label;
  final VoidCallback onTap;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 3, offset: Offset(0, 2))
          ],
        ),
        child: Text(
          flag,
          style: TextStyle(fontSize: fontSize),
        ),
      ),
    );
  }
}
