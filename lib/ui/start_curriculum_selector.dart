// ------------------------------------------------------------
// Ziel (Laien): Start-Curriculum-Datei wählen (verschiedene Seed-Pfade).
// Verbindung: robulingo_app.dart nutzt Auswahl, lädt dann via ApiClient + Seeds.
// Tücken: Buttons müssen zu existierenden Dateien im R2/Worker passen.
// ------------------------------------------------------------
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:robulingo_flutter/constants.dart';

String _iconForStartKey(String key) =>
    startCurriculumIcons[key] ??
    startCurriculumIcons[defaultStartCurriculum] ??
    'assets/icons/cross.webp';

class StartCurriculumSelector extends StatelessWidget {
  const StartCurriculumSelector({
    super.key,
    required this.onSelect,
    this.onPickSelected,
  });

  final void Function(String fileName) onSelect;
  final VoidCallback? onPickSelected;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final double logoHeight = size.height * (isLandscape ? 0.16 : 0.2);
    final double logoWidth = size.width * (isLandscape ? 0.4 : 0.85);
    final double tileSize = isLandscape
        ? min(90.0, size.height * 0.22)
        : min(110.0, size.width * 0.28);
    final double iconSize = tileSize * 0.5;
    final double rowSpacing = isLandscape ? 12.0 : 12.0;
    final double verticalPadding = isLandscape ? 16.0 : 32.0;

    final optionRows = [
      [
        _StartOption(
            asset: _iconForStartKey('start_curriculum_a.json'),
            fileName: 'start_curriculum_a.json'),
      ],
      [
        _StartOption(
            asset: _iconForStartKey('start_curriculum_b.json'),
            fileName: 'start_curriculum_b.json'),
        _StartOption(
            asset: _iconForStartKey('start_curriculum_t.json'),
            fileName: 'start_curriculum_t.json'),
      ],
      [
        _StartOption(
            asset: _iconForStartKey('start_curriculum_s.json'),
            fileName: 'start_curriculum_s.json'),
        _StartOption(
            asset: _iconForStartKey('start_curriculum_l.json'),
            fileName: 'start_curriculum_l.json'),
        if (onPickSelected != null)
          _StartOption(
            asset: 'assets/icons/pick.webp',
            onTap: onPickSelected,
          ),
      ],
    ];

    final optionsColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < optionRows.length; i++) ...[
          _OptionsRow(
            options: optionRows[i],
            onSelect: onSelect,
            tileSize: tileSize,
            iconSize: iconSize,
          ),
          if (i != optionRows.length - 1) SizedBox(height: rowSpacing),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 24),
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
                    child: Center(child: optionsColumn),
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
                  child: Center(child: optionsColumn),
                ),
              ],
            ),
    );
  }
}

class _StartOption {
  final String asset;
  final String? fileName;
  final VoidCallback? onTap;
  const _StartOption({required this.asset, this.fileName, this.onTap});
}

class _OptionsRow extends StatelessWidget {
  const _OptionsRow({
    required this.options,
    required this.onSelect,
    required this.tileSize,
    required this.iconSize,
  });

  final List<_StartOption> options;
  final void Function(String fileName) onSelect;
  final double tileSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final rowChildren = options
        .map(
          (opt) => SizedBox(
            width: tileSize,
            height: tileSize,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                elevation: 3,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Colors.black, width: 2),
                ),
                backgroundColor: Colors.white,
              ),
              onPressed: opt.onTap ??
                  () {
                    if (opt.fileName != null) {
                      onSelect(opt.fileName!);
                    }
                  },
              child: Image.asset(opt.asset,
                  width: iconSize, height: iconSize, fit: BoxFit.contain),
            ),
          ),
        )
        .toList();

    return Row(
      mainAxisAlignment: options.length == 1
          ? MainAxisAlignment.center
          : MainAxisAlignment.spaceEvenly,
      children: rowChildren,
    );
  }
}
