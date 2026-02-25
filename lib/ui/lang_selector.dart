// ------------------------------------------------------------
// Ziel (Laien): Erste Seite zur Sprachauswahl mit Logo.
// Strategie: Vollflächiger Grid aus Flaggen, ein Tap reicht.
// Schritte: RL-Logo zeigen, Wrap mit Flaggen bauen, Auswahl via Callback.
// Tücken: Bei neuen Sprachen muss die Flaggenmap in constants.dart gepflegt werden.
// ------------------------------------------------------------
import 'dart:math';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../flavor_config.dart';

class LangSelector extends StatefulWidget {
  const LangSelector({
    super.key,
    required this.onSelect,
    this.showHistoryButton = false,
    this.onOpenHistory,
    this.historyHasSupervisorInfo = false,
  });

  final void Function(String lang) onSelect;
  final bool showHistoryButton;
  final VoidCallback? onOpenHistory;
  final bool historyHasSupervisorInfo;

  @override
  State<LangSelector> createState() => _LangSelectorState();
}

class _LangSelectorState extends State<LangSelector> {
  @override
  Widget build(BuildContext context) {
    final bool showHistoryButton =
        widget.showHistoryButton && widget.onOpenHistory != null;
    final historyIconAsset =
        widget.historyHasSupervisorInfo ? 'assets/icons/eye_red.webp' : 'assets/icons/eye.webp';
    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final double logoHeight = size.height * (isLandscape ? 0.16 : 0.2);
    final double logoWidth = size.width * (isLandscape ? 0.4 : 0.85);
    final double tileSize = isLandscape ? min(84.0, size.height * 0.2) : 96.0;
    final double flagFontSize = tileSize * 0.48;
    final double spacing = isLandscape ? 16.0 : 24.0;

    Widget buildTile(String lang) {
      return GestureDetector(
        onTap: () => widget.onSelect(lang),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              )
            ],
          ),
          child: Text(
            langFlags[lang] ?? '',
            style: TextStyle(fontSize: flagFontSize),
          ),
        ),
      );
    }

    Widget buildLanguageGrid() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final columns = max(
            1,
            ((maxWidth + spacing) / (tileSize + spacing)).floor(),
          );
          return GridView.builder(
            padding: EdgeInsets.only(bottom: showHistoryButton ? 56 : 8),
            physics: const ClampingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: 1,
            ),
            itemCount: langChoices.length,
            itemBuilder: (context, index) => buildTile(langChoices[index]),
          );
        },
      );
    }

    final Widget mainContent = isLandscape
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: logoWidth,
                child: Image.asset(
                  activeFlavor.brandLogoAsset,
                  width: logoWidth,
                  height: logoHeight,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildLanguageGrid(),
              ),
            ],
          )
        : Column(
            children: [
              Image.asset(
                activeFlavor.brandLogoAsset,
                width: logoWidth,
                height: logoHeight,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: buildLanguageGrid(),
              ),
            ],
          );

    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: isLandscape ? 16 : 32, horizontal: 24),
      child: Stack(
        children: [
          Positioned.fill(child: mainContent),
          if (showHistoryButton)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: IconButton(
                  icon: Image.asset(
                    historyIconAsset,
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                  onPressed: widget.onOpenHistory,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
