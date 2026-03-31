// ------------------------------------------------------------
// Ziel (Laien): Start-Curriculum-Datei wählen (verschiedene Seed-Pfade).
// Verbindung: robulingo_app.dart nutzt Auswahl, lädt dann via ApiClient + Seeds.
// Tücken: Buttons müssen zu existierenden Dateien im R2/Worker passen.
// ------------------------------------------------------------
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:robulingo_flutter/constants.dart';
import 'package:robulingo_flutter/flavor_config.dart';
import 'package:url_launcher/url_launcher.dart';

String _iconForStartKey(String key) =>
    startCurriculumIcons[key] ??
    startCurriculumIcons[defaultStartCurriculum] ??
    'assets/icons/cross.webp';

String _tooltipText(BuildContext context, String tooltipKey) {
  final languageCode = Localizations.localeOf(context).languageCode.toLowerCase();
  const messages = <String, Map<String, String>>{
    'daily_words': {
      'de': 'Wörter des täglichen Lebens',
      'en': 'Words for everyday life',
      'es': 'Palabras de la vida cotidiana',
      'fr': 'Mots de la vie quotidienne',
      'it': 'Parole della vita quotidiana',
      'el': 'Λέξεις της καθημερινής ζωής',
      'ru': 'Слова повседневной жизни',
      'tr': 'Günlük yaşam sözcükleri',
      'ar': 'كلمات من الحياة اليومية',
      'hi': 'दैनिक जीवन के शब्द',
      'zh': '日常生活词汇',
      'ja': '日常生活のことば',
    },
    'cafe_words': {
      'de': 'Wörter und Phrasen im Cafe',
      'en': 'Words and phrases in the cafe',
      'es': 'Palabras y frases en el cafe',
      'fr': 'Mots et phrases au cafe',
      'it': 'Parole e frasi al cafe',
      'el': 'Λέξεις και φράσεις στο καφέ',
      'ru': 'Слова и фразы в кафе',
      'tr': 'Kafede kullanılan kelimeler ve ifadeler',
      'ar': 'كلمات وعبارات في المقهى',
      'hi': 'कैफे के शब्द और वाक्यांश',
      'zh': '咖啡馆中的词语和短句',
      'ja': 'カフェで使う単語とフレーズ',
    },
    'dialog_browser': {
      'de': 'Dialog-Training braucht anspruchsvolle Browser und Geräte',
      'en': 'Dialog training needs capable browsers and devices',
      'es': 'El entrenamiento de dialogo necesita navegadores y dispositivos potentes',
      'fr': 'L entrainement au dialogue a besoin de navigateurs et d appareils performants',
      'it': 'L allenamento al dialogo richiede browser e dispositivi capaci',
      'el': 'Η προπόνηση διαλόγου χρειάζεται ισχυρά προγράμματα περιήγησης και συσκευές',
      'ru': 'Тренировка диалога требует мощных браузеров и устройств',
      'tr': 'Diyalog egitimi guclu tarayicilar ve cihazlar gerektirir',
      'ar': 'يتطلب تدريب الحوار متصفحات واجهزة قوية',
      'hi': 'संवाद प्रशिक्षण के लिए सक्षम ब्राउज़र और डिवाइस चाहिए',
      'zh': '对话训练需要较强的浏览器和设备',
      'ja': '対話トレーニングには高性能なブラウザと端末が必要です',
    },
    'elementary_words': {
      'de': 'Elementare Wörter',
      'en': 'Elementary words',
      'es': 'Palabras elementales',
      'fr': 'Mots elementaires',
      'it': 'Parole elementari',
      'el': 'Στοιχειώδεις λέξεις',
      'ru': 'Элементарные слова',
      'tr': 'Temel kelimeler',
      'ar': 'كلمات اساسية',
      'hi': 'प्राथमिक शब्द',
      'zh': '基础词汇',
      'ja': '基礎的なことば',
    },
  };
  final table = messages[tooltipKey];
  if (table == null) {
    return '';
  }
  return table[languageCode] ?? table['en'] ?? '';
}

void _openRealTalk(BuildContext context) {
  final rawUrl = activeFlavor.realTalkUrl?.trim();
  if (rawUrl == null || rawUrl.isEmpty) return;
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return;
  unawaited(
    launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_self',
    ),
  );
}

class StartCurriculumSelector extends StatelessWidget {
  const StartCurriculumSelector({
    super.key,
    required this.onSelect,
    this.onPickSelected,
    this.showHistoryButton = false,
    this.onOpenHistory,
    this.historyHasSupervisorInfo = false,
  });

  final void Function(String fileName) onSelect;
  final VoidCallback? onPickSelected;
  final bool showHistoryButton;
  final VoidCallback? onOpenHistory;
  final bool historyHasSupervisorInfo;

  @override
  Widget build(BuildContext context) {
    final historyIconAsset = historyHasSupervisorInfo
        ? 'assets/icons/eye_red.webp'
        : 'assets/icons/eye.webp';
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
    final double featureTileMaxSize = isLandscape
        ? min(180.0, size.height * 0.3)
        : min(220.0, size.width * 0.42);

    final allowed = activeFlavor.allowedStartCurricula.toSet();
    final dialogFeatureOptions = <_StartOption>[];
    if (allowed.contains('start_curriculum_dialog.json')) {
      dialogFeatureOptions.add(
        _StartOption(
          asset: _iconForStartKey('start_curriculum_dialog.json'),
          fileName: 'start_curriculum_dialog.json',
          iconScale:
              startCurriculumIconScaleForKey('start_curriculum_dialog.json'),
          tooltipKey: 'cafe_words',
        ),
      );
    }
    if ((activeFlavor.realTalkUrl?.trim().isNotEmpty ?? false)) {
      dialogFeatureOptions.add(
        _StartOption(
          asset: 'assets/icons/dialog.webp',
          onTap: () => _openRealTalk(context),
          iconScale: 1.32,
          tooltipKey: 'dialog_browser',
        ),
      );
    }
    final optionRows = <List<_StartOption>>[];

    if (allowed.contains('start_curriculum_a.json')) {
      optionRows.add([
        _StartOption(
          asset: _iconForStartKey('start_curriculum_a.json'),
          fileName: 'start_curriculum_a.json',
          iconScale: startCurriculumIconScaleForKey('start_curriculum_a.json'),
          tooltipKey: 'daily_words',
        ),
      ]);
    }

    final secondRow = <_StartOption>[];
    if (allowed.contains('start_curriculum_b.json')) {
      secondRow.add(_StartOption(
        asset: _iconForStartKey('start_curriculum_b.json'),
        fileName: 'start_curriculum_b.json',
        iconScale: startCurriculumIconScaleForKey('start_curriculum_b.json'),
        tooltipKey: 'elementary_words',
      ));
    }
    if (allowed.contains('start_curriculum_t.json')) {
      secondRow.add(_StartOption(
        asset: _iconForStartKey('start_curriculum_t.json'),
        fileName: 'start_curriculum_t.json',
        iconScale: startCurriculumIconScaleForKey('start_curriculum_t.json'),
      ));
    }
    if (secondRow.isNotEmpty) {
      optionRows.add(secondRow);
    }

    final thirdRow = <_StartOption>[];
    if (allowed.contains('start_curriculum_s.json')) {
      thirdRow.add(_StartOption(
        asset: _iconForStartKey('start_curriculum_s.json'),
        fileName: 'start_curriculum_s.json',
        iconScale: startCurriculumIconScaleForKey('start_curriculum_s.json'),
      ));
    }
    if (allowed.contains('start_curriculum_l.json')) {
      thirdRow.add(_StartOption(
        asset: _iconForStartKey('start_curriculum_l.json'),
        fileName: 'start_curriculum_l.json',
        iconScale: startCurriculumIconScaleForKey('start_curriculum_l.json'),
      ));
    }
    if (activeFlavor.allowPickManifest && onPickSelected != null) {
      thirdRow.add(
        _StartOption(
          asset: 'assets/icons/pick.webp',
          onTap: onPickSelected,
          iconScale: 1.0,
        ),
      );
    }
    if (thirdRow.isNotEmpty) {
      optionRows.add(thirdRow);
    }

    final optionsColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (optionRows.isNotEmpty) ...[
          _OptionsRow(
            options: optionRows.first,
            onSelect: onSelect,
            tileSize: tileSize,
            iconSize: iconSize,
          ),
        ],
        if (dialogFeatureOptions.isNotEmpty) ...[
          if (optionRows.isNotEmpty) SizedBox(height: rowSpacing),
          _FeatureOptionsRow(
            options: dialogFeatureOptions,
            onSelect: onSelect,
            maxTileSize: featureTileMaxSize,
          ),
        ],
        for (int i = 1; i < optionRows.length; i++) ...[
          SizedBox(height: rowSpacing),
          _OptionsRow(
            options: optionRows[i],
            onSelect: onSelect,
            tileSize: tileSize,
            iconSize: iconSize,
          ),
        ],
      ],
    );

    final Widget content = Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 24),
      child: isLandscape
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
                  child: SingleChildScrollView(
                    child: Center(child: optionsColumn),
                  ),
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
                  child: Center(child: optionsColumn),
                ),
              ],
            ),
    );

    return Stack(
      children: [
        Positioned.fill(child: content),
        if (showHistoryButton && onOpenHistory != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: Tooltip(
                message: 'Supervisor & progress info',
                child: IconButton(
                  icon: Image.asset(
                    historyIconAsset,
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                  onPressed: onOpenHistory,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FeatureOptionsRow extends StatelessWidget {
  const _FeatureOptionsRow({
    required this.options,
    required this.onSelect,
    required this.maxTileSize,
  });

  final List<_StartOption> options;
  final void Function(String fileName) onSelect;
  final double maxTileSize;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxTileSize * options.length + spacing * (options.length - 1);
        final tileSize = min(
          maxTileSize,
          (availableWidth - spacing * (options.length - 1)) / options.length,
        );
        final iconSize = tileSize * 0.7;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < options.length; i++) ...[
              SizedBox(
                width: tileSize,
                height: tileSize,
                child: Tooltip(
                  message: _tooltipText(context, options[i].tooltipKey),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      elevation: 4,
                      padding: const EdgeInsets.all(18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: const BorderSide(color: Colors.black, width: 2),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    onPressed: options[i].onTap ??
                        () {
                          if (options[i].fileName != null) {
                            onSelect(options[i].fileName!);
                          }
                        },
                    child: Image.asset(
                      options[i].asset,
                      width: iconSize * options[i].iconScale,
                      height: iconSize * options[i].iconScale,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              if (i != options.length - 1) const SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}

class _StartOption {
  final String asset;
  final String? fileName;
  final VoidCallback? onTap;
  final double iconScale;
  final String tooltipKey;
  const _StartOption({
    required this.asset,
    this.fileName,
    this.onTap,
    this.iconScale = 1.0,
    this.tooltipKey = '',
  });
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
            child: Tooltip(
              message: _tooltipText(context, opt.tooltipKey),
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
                child: Image.asset(
                  opt.asset,
                  width: iconSize * opt.iconScale,
                  height: iconSize * opt.iconScale,
                  fit: BoxFit.contain,
                ),
              ),
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
