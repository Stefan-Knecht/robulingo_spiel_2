import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:robulingo_flutter/constants.dart';
import 'package:robulingo_flutter/flavor_config.dart';
import 'package:url_launcher/url_launcher.dart';

enum DailywordsModuleMode { training, dialog }

class DailywordsModuleChoice {
  const DailywordsModuleChoice({
    required this.rowId,
    required this.mode,
    this.startKey,
    this.dialogSceneId,
    this.dialogPath,
  });

  final String rowId;
  final DailywordsModuleMode mode;
  final String? startKey;
  final String? dialogSceneId;
  final String? dialogPath;
}

class DailywordsModuleProgress {
  const DailywordsModuleProgress({
    required this.completed,
    required this.total,
  });

  final int completed;
  final int total;

  double get ratio {
    if (total <= 0) return 0;
    return (completed / total).clamp(0.0, 1.0).toDouble();
  }
}

class DailywordsModuleSelector extends StatefulWidget {
  const DailywordsModuleSelector({
    super.key,
    required this.targetLanguageCode,
    this.nativeLanguageCode,
    this.recommendedRowId,
    this.recommendedMode,
    this.showHistoryButton = false,
    this.onOpenHistory,
    this.historyHasSupervisorInfo = false,
    this.onTargetLanguageChange,
    this.onNativeLanguageChange,
    this.progressByStartKey = const {},
    this.autoProceedDelay = const Duration(seconds: 6),
    required this.onSelect,
  });

  final String targetLanguageCode;
  final String? nativeLanguageCode;
  final String? recommendedRowId;
  final DailywordsModuleMode? recommendedMode;
  final bool showHistoryButton;
  final VoidCallback? onOpenHistory;
  final bool historyHasSupervisorInfo;
  final void Function(String languageCode)? onTargetLanguageChange;
  final void Function(String languageCode)? onNativeLanguageChange;
  final Map<String, DailywordsModuleProgress> progressByStartKey;
  final Duration autoProceedDelay;
  final void Function(DailywordsModuleChoice choice) onSelect;

  @override
  State<DailywordsModuleSelector> createState() =>
      _DailywordsModuleSelectorState();
}

class _DailywordsModuleSelectorState extends State<DailywordsModuleSelector> {
  bool _menuOpen = false;
  String _inputLanguageMode = 'l2';
  double _speechRate = 1.0;
  Timer? _autoProceedTimer;
  bool _autoProceedCanceled = false;
  bool _selectionTriggered = false;

  @override
  void initState() {
    super.initState();
    _scheduleAutoProceed();
  }

  @override
  void didUpdateWidget(covariant DailywordsModuleSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recommendedRowId != widget.recommendedRowId ||
        oldWidget.recommendedMode != widget.recommendedMode ||
        oldWidget.targetLanguageCode != widget.targetLanguageCode ||
        oldWidget.nativeLanguageCode != widget.nativeLanguageCode) {
      _selectionTriggered = false;
      _autoProceedCanceled = false;
      _scheduleAutoProceed();
    }
  }

  @override
  void dispose() {
    _autoProceedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const rows = _moduleRows;
    final recommended = _resolveRecommendedChoice();
    final size = MediaQuery.of(context).size;
    final compact = size.width < 720 || size.height < 620;
    final l1 = _normalizeLang(widget.nativeLanguageCode) ??
        _normalizeLang(widget.targetLanguageCode) ??
        'en';
    final tableWidth = min(size.width * 0.965, 1500.0);
    final topSafetyMargin = compact ? 18.0 : 28.0;
    final maxPanelHeight = size.height * 0.9 - topSafetyMargin;
    final rowHeight = compact ? 116.0 : 154.0;
    final headerHeight = compact ? 42.0 : 56.0;
    final chromeHeight = compact ? 76.0 : 94.0;
    final naturalHeight = chromeHeight + headerHeight + rowHeight * rows.length;
    final panelHeight = min(maxPanelHeight, naturalHeight);

    return Stack(
      children: [
        Center(
          child: Padding(
            padding: EdgeInsets.only(top: topSafetyMargin),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _cancelAutoProceed(),
              child: SizedBox(
                width: tableWidth,
                height: panelHeight,
                child: Column(
                  children: [
                    SizedBox(
                      height: compact ? 42 : 50,
                      child: _TopBar(
                        targetLanguageCode: widget.targetLanguageCode,
                        nativeLanguageCode: widget.nativeLanguageCode,
                        onMenuPressed: () {
                          _cancelAutoProceed();
                          setState(() => _menuOpen = true);
                        },
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final gridHeight =
                              headerHeight + rowHeight * rows.length;
                          return Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SizedBox(
                                width: tableWidth,
                                height: gridHeight,
                                child: _ModuleGrid(
                                  rows: rows,
                                  compact: compact,
                                  recommended: recommended,
                                  languageCode: l1,
                                  progressByStartKey: widget.progressByStartKey,
                                  onSelect: _selectChoice,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      height: compact ? 34 : 44,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Tooltip(
                          message: _t(l1, 'back_home'),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _openDailyWordsHome,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.arrow_forward,
                                    color: const Color(0xff215da8),
                                    size: compact ? 26 : 36,
                                  ),
                                  const SizedBox(width: 8),
                                  Image.asset(
                                    'assets/icons/module_rival.webp',
                                    width: compact ? 30 : 42,
                                    height: compact ? 30 : 42,
                                    fit: BoxFit.contain,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_menuOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _menuOpen = false),
              child: Container(color: const Color(0x33000000)),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: _BurgerMenuPanel(
              targetLanguageCode: widget.targetLanguageCode,
              nativeLanguageCode: widget.nativeLanguageCode,
              languageCode: l1,
              inputLanguageMode: _inputLanguageMode,
              speechRate: _speechRate,
              onClose: () => setState(() => _menuOpen = false),
              onTargetLanguageChange: widget.onTargetLanguageChange,
              onNativeLanguageChange: widget.onNativeLanguageChange,
              onInputLanguageModeChange: (value) {
                setState(() => _inputLanguageMode = value);
              },
              onSpeechRateChange: (value) {
                setState(() => _speechRate = value);
              },
            ),
          ),
        ],
      ],
    );
  }

  void _openDailyWordsHome() {
    _cancelAutoProceed();
    final uri = Uri.tryParse(activeFlavor.dashboardLandingUrl);
    if (uri == null) return;
    unawaited(
      launchUrl(uri,
          mode: LaunchMode.platformDefault, webOnlyWindowName: '_self'),
    );
  }

  void _scheduleAutoProceed() {
    if (_autoProceedCanceled || _selectionTriggered) return;
    _autoProceedTimer?.cancel();
    _autoProceedTimer = Timer(widget.autoProceedDelay, () {
      if (!mounted || _autoProceedCanceled || _selectionTriggered) return;
      _selectChoice(_resolveRecommendedChoice(), autoProceed: true);
    });
  }

  void _cancelAutoProceed() {
    if (_autoProceedCanceled) return;
    _autoProceedCanceled = true;
    _autoProceedTimer?.cancel();
    _autoProceedTimer = null;
  }

  void _selectChoice(DailywordsModuleChoice choice,
      {bool autoProceed = false}) {
    if (_selectionTriggered) return;
    _selectionTriggered = true;
    if (!autoProceed) {
      _cancelAutoProceed();
    } else {
      _autoProceedTimer?.cancel();
      _autoProceedTimer = null;
    }
    widget.onSelect(choice);
  }

  DailywordsModuleChoice _resolveRecommendedChoice() {
    final rowId = widget.recommendedRowId?.trim().isNotEmpty == true
        ? widget.recommendedRowId!.trim()
        : 'dailywords';
    final mode = widget.recommendedMode ?? DailywordsModuleMode.training;
    final row = _moduleRows.firstWhere(
      (entry) => entry.id == rowId,
      orElse: () => _moduleRows.first,
    );
    if (mode == DailywordsModuleMode.dialog && row.hasDialog) {
      return DailywordsModuleChoice(
        rowId: row.id,
        mode: DailywordsModuleMode.dialog,
        startKey: row.startKey,
        dialogSceneId: row.dialogSceneId,
        dialogPath: row.dialogPath,
      );
    }
    return DailywordsModuleChoice(
      rowId: row.id,
      mode: DailywordsModuleMode.training,
      startKey: row.startKey,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.targetLanguageCode,
    this.nativeLanguageCode,
    this.onMenuPressed,
  });

  final String targetLanguageCode;
  final String? nativeLanguageCode;
  final VoidCallback? onMenuPressed;

  @override
  Widget build(BuildContext context) {
    final l1 = nativeLanguageCode?.trim().isNotEmpty == true
        ? nativeLanguageCode!.trim()
        : Localizations.localeOf(context).languageCode.toLowerCase();
    final l2 = targetLanguageCode.trim().toLowerCase();
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _MenuButton(onPressed: onMenuPressed),
          ),
        ),
        Expanded(
          child: Text(
            '${langFlags[l1] ?? ''} ${_languageName(l1)}  ->  ${langFlags[l2] ?? ''} ${_languageName(l2)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff2b2117),
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontFamily: 'serif',
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xfffffbf4),
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xffe5d7c4)),
          ),
          child: const Icon(Icons.menu, size: 32, color: Color(0xff4a2c12)),
        ),
      ),
    );
  }
}

class _BurgerMenuPanel extends StatelessWidget {
  const _BurgerMenuPanel({
    required this.targetLanguageCode,
    this.nativeLanguageCode,
    required this.languageCode,
    required this.inputLanguageMode,
    required this.speechRate,
    required this.onClose,
    this.onTargetLanguageChange,
    this.onNativeLanguageChange,
    required this.onInputLanguageModeChange,
    required this.onSpeechRateChange,
  });

  final String targetLanguageCode;
  final String? nativeLanguageCode;
  final String languageCode;
  final String inputLanguageMode;
  final double speechRate;
  final VoidCallback onClose;
  final void Function(String languageCode)? onTargetLanguageChange;
  final void Function(String languageCode)? onNativeLanguageChange;
  final void Function(String mode) onInputLanguageModeChange;
  final void Function(double rate) onSpeechRateChange;

  @override
  Widget build(BuildContext context) {
    final l1 = _normalizeLang(nativeLanguageCode) ??
        _normalizeLang(targetLanguageCode) ??
        'en';
    final l2 = _normalizeLang(targetLanguageCode) ?? l1;
    final ui = _normalizeLang(languageCode) ?? l1;
    final panelWidth = min(MediaQuery.of(context).size.width * 0.86, 360.0);
    return Material(
      color: const Color(0xfffffbf4),
      elevation: 12,
      child: SizedBox(
        width: panelWidth,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t(ui, 'options'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'serif',
                          color: Color(0xff2b2117),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: _t(ui, 'close'),
                      child: IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xff2b2117),
                          side: const BorderSide(color: Color(0xffe5d7c4)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _MenuSectionTitle(_t(ui, 'module')),
                const Text('RealTalk', style: _menuNoteStyle),
                const SizedBox(height: 8),
                _DisabledMenuButton(label: _t(ui, 'module_selection')),
                const SizedBox(height: 20),
                _MenuSectionTitle(_t(ui, 'languages')),
                const SizedBox(height: 8),
                const Text('L1 -> L2', style: _menuLabelStyle),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _LanguageDropdown(
                        value: l1,
                        onChanged: onNativeLanguageChange,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('->',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    Expanded(
                      child: _LanguageDropdown(
                        value: l2,
                        onChanged: onTargetLanguageChange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(_t(ui, 'input'), style: _menuLabelStyle),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: inputLanguageMode,
                  decoration: _menuInputDecoration(),
                  items: [
                    DropdownMenuItem(
                      value: 'l2',
                      child:
                          Text('${langFlags[l2] ?? ''} ${_t(ui, 'l2_direct')}'),
                    ),
                    DropdownMenuItem(
                      value: 'l1',
                      child: Text(
                        '${langFlags[l1] ?? ''} ${_t(ui, 'l1_to_l2')}',
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onInputLanguageModeChange(value);
                  },
                ),
                const SizedBox(height: 20),
                _MenuSectionTitle(_t(ui, 'tempo')),
                const SizedBox(height: 8),
                Text(_t(ui, 'speech_rate'), style: _menuLabelStyle),
                const SizedBox(height: 6),
                DropdownButtonFormField<double>(
                  initialValue: speechRate,
                  decoration: _menuInputDecoration(),
                  items: [
                    DropdownMenuItem(
                      value: 0.70,
                      child: Text('${_t(ui, 'rate_slow')} (0.70x)'),
                    ),
                    DropdownMenuItem(
                      value: 0.85,
                      child: Text('${_t(ui, 'rate_somewhat_slow')} (0.85x)'),
                    ),
                    DropdownMenuItem(
                      value: 0.95,
                      child: Text('${_t(ui, 'rate_almost_normal')} (0.95x)'),
                    ),
                    DropdownMenuItem(
                      value: 1.00,
                      child: Text('${_t(ui, 'rate_normal')} (1.00x)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onSpeechRateChange(value);
                  },
                ),
                const SizedBox(height: 20),
                _MenuSectionTitle(_t(ui, 'fallback')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _RuntimeBadge(label: _t(ui, 'controlled_response')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t(ui, 'runtime_unavailable'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff695b4d),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({required this.value, required this.onChanged});

  final String value;
  final void Function(String languageCode)? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: _menuInputDecoration(),
      items: langChoices
          .map(
            (code) => DropdownMenuItem(
              value: code,
              child: Text(
                '${langFlags[code] ?? ''} ${_languageName(code)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value != null) onChanged!(value);
            },
    );
  }
}

class _DisabledMenuButton extends StatelessWidget {
  const _DisabledMenuButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: null,
      style: OutlinedButton.styleFrom(
        disabledForegroundColor: Colors.black87,
        side: const BorderSide(color: Colors.black, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(label),
    );
  }
}

class _MenuSectionTitle extends StatelessWidget {
  const _MenuSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
        color: Color(0xff2b2117),
      ),
    );
  }
}

class _RuntimeBadge extends StatelessWidget {
  const _RuntimeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xffdcfce7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xff16a34a)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xff166534),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

InputDecoration _menuInputDecoration() {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}

const _menuLabelStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w800,
  color: Color(0xff2b2117),
);

const _menuNoteStyle = TextStyle(
  fontSize: 12,
  color: Color(0xff695b4d),
);

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({
    required this.rows,
    required this.compact,
    required this.recommended,
    required this.languageCode,
    required this.progressByStartKey,
    required this.onSelect,
  });

  final List<_DailywordsModuleRow> rows;
  final bool compact;
  final DailywordsModuleChoice recommended;
  final String languageCode;
  final Map<String, DailywordsModuleProgress> progressByStartKey;
  final void Function(DailywordsModuleChoice choice) onSelect;

  @override
  Widget build(BuildContext context) {
    final rowHeight = compact ? 110.0 : 148.0;
    final headerHeight = compact ? 42.0 : 56.0;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 3),
      ),
      child: Column(
        children: [
          SizedBox(
            height: headerHeight,
            child: Row(
              children: [
                Expanded(
                  flex: 390,
                  child: _BorderedCell(
                    child: _HeaderCell(text: _t(languageCode, 'scene')),
                  ),
                ),
                Expanded(
                  flex: 285,
                  child: _BorderedCell(
                    child: _HeaderCell(text: _t(languageCode, 'training')),
                  ),
                ),
                Expanded(
                  flex: 290,
                  child: _BorderedCell(
                    child: _HeaderCell(text: _t(languageCode, 'dialog')),
                  ),
                ),
              ],
            ),
          ),
          for (final row in rows)
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  Expanded(
                    flex: 390,
                    child: _BorderedCell(
                      drawTop: true,
                      child: _SceneMergedCell(
                        title: _rowTitle(row, languageCode),
                        imageAsset: row.sceneAsset,
                        compact: compact,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 285,
                    child: _BorderedCell(
                      drawTop: true,
                      child: _ActionTableCell(
                        choice: DailywordsModuleChoice(
                          rowId: row.id,
                          mode: DailywordsModuleMode.training,
                          startKey: row.startKey,
                        ),
                        iconAsset: row.trainingIconAsset,
                        height: rowHeight,
                        enabled: true,
                        recommended: _sameChoice(
                          recommended,
                          DailywordsModuleChoice(
                            rowId: row.id,
                            mode: DailywordsModuleMode.training,
                          ),
                        ),
                        languageCode: languageCode,
                        progress: progressByStartKey[row.startKey],
                        onSelect: onSelect,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 290,
                    child: _BorderedCell(
                      drawTop: true,
                      child: _ActionTableCell(
                        choice: DailywordsModuleChoice(
                          rowId: row.id,
                          mode: DailywordsModuleMode.dialog,
                          startKey: row.startKey,
                          dialogSceneId: row.dialogSceneId,
                          dialogPath: row.dialogPath,
                        ),
                        iconAsset: row.dialogIconAsset,
                        iconScale: row.dialogIconAsset ==
                                'assets/icons/module_dialog.webp'
                            ? 2.0
                            : 1.0,
                        height: rowHeight,
                        enabled: row.hasDialog,
                        recommended: _sameChoice(
                          recommended,
                          DailywordsModuleChoice(
                            rowId: row.id,
                            mode: DailywordsModuleMode.dialog,
                          ),
                        ),
                        languageCode: languageCode,
                        onSelect: onSelect,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool _sameChoice(DailywordsModuleChoice a, DailywordsModuleChoice b) {
    return a.rowId == b.rowId && a.mode == b.mode;
  }
}

class _BorderedCell extends StatelessWidget {
  const _BorderedCell({
    required this.child,
    this.drawTop = false,
  });

  final Widget child;
  final bool drawTop;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: drawTop
              ? const BorderSide(color: Colors.black, width: 3)
              : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.center,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff2b2117),
            fontSize: 22,
            fontWeight: FontWeight.w900,
            fontFamily: 'serif',
          ),
        ),
      ),
    );
  }
}

class _SceneMergedCell extends StatelessWidget {
  const _SceneMergedCell({
    required this.title,
    required this.imageAsset,
    required this.compact,
  });

  final String title;
  final String imageAsset;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 22),
      child: Row(
        children: [
          Expanded(
            flex: 52,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xff2b2117),
                fontSize: compact ? 18 : 27,
                fontWeight: FontWeight.w900,
                fontFamily: 'serif',
              ),
            ),
          ),
          Expanded(
            flex: 48,
            child: Padding(
              padding: EdgeInsets.all(compact ? 3 : 5),
              child: Image.asset(
                imageAsset,
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTableCell extends StatelessWidget {
  const _ActionTableCell({
    required this.choice,
    required this.iconAsset,
    required this.height,
    required this.enabled,
    required this.recommended,
    required this.languageCode,
    required this.onSelect,
    this.progress,
    this.iconScale = 1.0,
  });

  final DailywordsModuleChoice choice;
  final String iconAsset;
  final double height;
  final bool enabled;
  final bool recommended;
  final String languageCode;
  final void Function(DailywordsModuleChoice choice) onSelect;
  final DailywordsModuleProgress? progress;
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    final diameter = min(height * 0.56, 136.0);
    final borderColor = recommended ? const Color(0xff0f8a3b) : Colors.black;
    final background = recommended ? const Color(0xffe2f7e9) : Colors.white;
    final showProgress = choice.mode == DailywordsModuleMode.training;
    return SizedBox(
      height: height,
      child: Center(
        child: Tooltip(
          message: choice.mode == DailywordsModuleMode.training
              ? _t(languageCode, 'training')
              : _t(languageCode, 'dialog'),
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? () => onSelect(choice) : null,
                child: SizedBox(
                  width: diameter,
                  height: showProgress ? diameter + 24 : diameter,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Container(
                        width: diameter,
                        height: diameter,
                        decoration: BoxDecoration(
                          color: background,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: borderColor,
                            width: recommended ? 5 : 4,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0xff000000),
                              offset: Offset(0, 9),
                              blurRadius: 0,
                              spreadRadius: -2,
                            ),
                            BoxShadow(
                              color: Color(0x22000000),
                              offset: Offset(0, 14),
                              blurRadius: 0,
                              spreadRadius: -8,
                            ),
                          ],
                        ),
                        child: Transform.scale(
                          scale: iconScale,
                          child: Padding(
                            padding: EdgeInsets.all(diameter * 0.05),
                            child: Image.asset(iconAsset, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      if (showProgress)
                        Positioned(
                          top: diameter + 12,
                          left: 0,
                          right: 0,
                          child: _ModuleProgressBar(progress: progress),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleProgressBar extends StatelessWidget {
  const _ModuleProgressBar({required this.progress});

  final DailywordsModuleProgress? progress;

  @override
  Widget build(BuildContext context) {
    final ratio = progress?.ratio ?? 0.0;
    final percent = (ratio * 100).round().clamp(0, 100);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(
                  height: 8,
                  color: const Color(0xffe5d7c4),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 8,
                    color: const Color(0xff215da8),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 34,
          child: Text(
            '$percent%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xff2b2117),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

const List<String> dailywordsTrainingStartKeys = [
  'start_curriculum_a.json',
  'start_curriculum_realtalk_cafe.json',
  'start_curriculum_t.json',
  'start_curriculum_l.json',
  'start_curriculum_b.json',
];

class _DailywordsModuleRow {
  const _DailywordsModuleRow({
    required this.id,
    required this.sceneAsset,
    required this.startKey,
    this.trainingIconAsset = 'assets/icons/module_mountain.webp',
    this.dialogIconAsset = 'assets/icons/module_dialog.webp',
    this.dialogSceneId,
    this.dialogPath,
  });

  final String id;
  final String sceneAsset;
  final String startKey;
  final String trainingIconAsset;
  final String dialogIconAsset;
  final String? dialogSceneId;
  final String? dialogPath;

  bool get hasDialog =>
      (dialogSceneId != null && dialogSceneId!.trim().isNotEmpty) ||
      (dialogPath != null && dialogPath!.trim().isNotEmpty);
}

String? _normalizeLang(String? value) {
  final raw = value?.trim().toLowerCase() ?? '';
  if (raw.isEmpty) return null;
  final candidate = raw.split(RegExp(r'[-_]')).first;
  return langChoices.contains(candidate) ? candidate : null;
}

String _rowTitle(_DailywordsModuleRow row, String languageCode) {
  final key = 'row_${row.id}';
  return _t(languageCode, key);
}

String _t(String languageCode, String key) {
  final lang = _normalizeLang(languageCode) ?? 'en';
  final table = _localizedText[lang] ?? _localizedText['en']!;
  return table[key] ?? _localizedText['en']![key] ?? key;
}

String _languageName(String code) {
  const names = {
    'de': 'Deutsch',
    'en': 'English',
    'ar': 'Arabic',
    'fr': 'Francais',
    'es': 'Espanol',
    'it': 'Italiano',
    'ru': 'Russian',
    'hi': 'Hindi',
    'el': 'Greek',
    'zh': 'Chinese',
    'tr': 'Turkce',
    'ja': 'Japanese',
  };
  return names[code] ?? code.toUpperCase();
}

const Map<String, Map<String, String>> _localizedText = {
  'en': {
    'scene': 'Scene',
    'training': 'Training',
    'dialog': 'Dialog',
    'back_home': 'Back to DailyWords',
    'options': 'Options',
    'export_debug': 'Export debug log',
    'export_dialog': 'Export dialog log',
    'close': 'Close',
    'module': 'Module',
    'module_selection': 'Module selection',
    'languages': 'Languages',
    'input': 'Input',
    'l2_direct': 'L2 direct',
    'l1_to_l2': 'Speak L1, transfer to L2',
    'tempo': 'Tempo',
    'speech_rate': 'Speech rate',
    'rate_slow': 'Slow',
    'rate_somewhat_slow': 'Somewhat slow',
    'rate_almost_normal': 'Almost normal',
    'rate_normal': 'Normal',
    'fallback': 'Fallback',
    'controlled_response': 'Controlled response',
    'runtime_unavailable': 'Parser n/a - Responder n/a',
    'row_dailywords': 'Daily Words',
    'row_cafe': 'Cafe',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'First Words',
  },
  'de': {
    'scene': 'Szene',
    'training': 'Training',
    'dialog': 'Dialog',
    'back_home': 'DailyWords Startseite',
    'options': 'Optionen',
    'export_debug': 'Debug-Log exportieren',
    'export_dialog': 'Dialog-Log exportieren',
    'close': 'Schließen',
    'module': 'Module',
    'module_selection': 'Modulauswahl',
    'languages': 'Sprachen',
    'input': 'Input',
    'l2_direct': 'L2 direkt',
    'l1_to_l2': 'L1 sprechen, nach L2 übertragen',
    'tempo': 'Tempo',
    'speech_rate': 'Sprechgeschwindigkeit',
    'rate_slow': 'Langsam',
    'rate_somewhat_slow': 'Etwas langsam',
    'rate_almost_normal': 'Fast normal',
    'rate_normal': 'Normal',
    'fallback': 'Fallback',
    'controlled_response': 'Kontrollierte Antwort',
    'runtime_unavailable': 'Parser n/a - Responder n/a',
    'row_dailywords': 'Tägliche Wörter',
    'row_cafe': 'Café',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'Erste Worte',
  },
  'es': {
    'scene': 'Escena',
    'training': 'Entrenamiento',
    'dialog': 'Dialogo',
    'back_home': 'Volver a DailyWords',
    'options': 'Opciones',
    'export_debug': 'Exportar depuracion',
    'export_dialog': 'Exportar dialogo',
    'close': 'Cerrar',
    'module': 'Modulo',
    'module_selection': 'Seleccion de modulo',
    'languages': 'Idiomas',
    'input': 'Entrada',
    'l2_direct': 'L2 directo',
    'l1_to_l2': 'Hablar L1, transferir a L2',
    'tempo': 'Ritmo',
    'speech_rate': 'Velocidad',
    'rate_slow': 'Lento',
    'rate_somewhat_slow': 'Algo lento',
    'rate_almost_normal': 'Casi normal',
    'rate_normal': 'Normal',
    'fallback': 'Fallback',
    'controlled_response': 'Respuesta controlada',
    'runtime_unavailable': 'Parser n/a - Responder n/a',
    'row_dailywords': 'Palabras diarias',
    'row_cafe': 'Cafe',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'Primeras palabras',
  },
  'fr': {
    'scene': 'Scene',
    'training': 'Entrainement',
    'dialog': 'Dialogue',
    'back_home': 'Retour a DailyWords',
    'options': 'Options',
    'export_debug': 'Exporter debug',
    'export_dialog': 'Exporter dialogue',
    'close': 'Fermer',
    'module': 'Module',
    'module_selection': 'Choix du module',
    'languages': 'Langues',
    'input': 'Entree',
    'l2_direct': 'L2 direct',
    'l1_to_l2': 'Parler L1, transferer vers L2',
    'tempo': 'Rythme',
    'speech_rate': 'Vitesse de parole',
    'rate_slow': 'Lent',
    'rate_somewhat_slow': 'Un peu lent',
    'rate_almost_normal': 'Presque normal',
    'rate_normal': 'Normal',
    'fallback': 'Fallback',
    'controlled_response': 'Reponse controlee',
    'runtime_unavailable': 'Parser n/d - Responder n/d',
    'row_dailywords': 'Mots quotidiens',
    'row_cafe': 'Cafe',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'Premiers mots',
  },
  'it': {
    'scene': 'Scena',
    'training': 'Allenamento',
    'dialog': 'Dialogo',
    'back_home': 'Torna a DailyWords',
    'options': 'Opzioni',
    'export_debug': 'Esporta debug',
    'export_dialog': 'Esporta dialogo',
    'close': 'Chiudi',
    'module': 'Modulo',
    'module_selection': 'Scelta modulo',
    'languages': 'Lingue',
    'input': 'Input',
    'l2_direct': 'L2 diretto',
    'l1_to_l2': 'Parla L1, trasferisci a L2',
    'tempo': 'Tempo',
    'speech_rate': 'Velocita voce',
    'rate_slow': 'Lento',
    'rate_somewhat_slow': 'Abbastanza lento',
    'rate_almost_normal': 'Quasi normale',
    'rate_normal': 'Normale',
    'fallback': 'Fallback',
    'controlled_response': 'Risposta controllata',
    'runtime_unavailable': 'Parser n/d - Responder n/d',
    'row_dailywords': 'Parole quotidiane',
    'row_cafe': 'Cafe',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'Prime parole',
  },
  'el': {
    'scene': 'Skini',
    'training': 'Ekpaidefsi',
    'dialog': 'Dialogos',
    'back_home': 'Piso sto DailyWords',
    'options': 'Epiloges',
    'export_debug': 'Exagogi debug',
    'export_dialog': 'Exagogi dialogou',
    'close': 'Kleisimo',
    'module': 'Module',
    'module_selection': 'Epilogi module',
    'languages': 'Glosses',
    'input': 'Input',
    'l2_direct': 'L2 apeftheias',
    'l1_to_l2': 'Miliste L1, metafora se L2',
    'tempo': 'Tempo',
    'speech_rate': 'Tachytita omilias',
    'rate_slow': 'Arga',
    'rate_somewhat_slow': 'Ligo arga',
    'rate_almost_normal': 'Sxedon kanonika',
    'rate_normal': 'Kanonika',
    'fallback': 'Fallback',
    'controlled_response': 'Elegchomeni apantisi',
    'runtime_unavailable': 'Parser n/a - Responder n/a',
    'row_dailywords': 'Kathimerines lexeis',
    'row_cafe': 'Cafe',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'Protes lexeis',
  },
  'ru': {
    'scene': 'Stsena',
    'training': 'Trenirovka',
    'dialog': 'Dialog',
    'back_home': 'Nazad k DailyWords',
    'options': 'Nastroiki',
    'export_debug': 'Eksport debug',
    'export_dialog': 'Eksport dialoga',
    'close': 'Zakryt',
    'module': 'Modul',
    'module_selection': 'Vybor modula',
    'languages': 'Yazyki',
    'input': 'Vvod',
    'l2_direct': 'L2 priamo',
    'l1_to_l2': 'Govorit L1, perenesti v L2',
    'tempo': 'Temp',
    'speech_rate': 'Skorost rechi',
    'rate_slow': 'Medlenno',
    'rate_somewhat_slow': 'Nemnogo medlenno',
    'rate_almost_normal': 'Pochti normalno',
    'rate_normal': 'Normalno',
    'fallback': 'Fallback',
    'controlled_response': 'Kontroliruemyi otvet',
    'runtime_unavailable': 'Parser n/a - Responder n/a',
    'row_dailywords': 'Ezhednevnye slova',
    'row_cafe': 'Cafe',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'Pervye slova',
  },
  'tr': {
    'scene': 'Sahne',
    'training': 'Alistirma',
    'dialog': 'Diyalog',
    'back_home': 'DailyWords e don',
    'options': 'Secenekler',
    'export_debug': 'Debug kaydini disa aktar',
    'export_dialog': 'Diyalog kaydini disa aktar',
    'close': 'Kapat',
    'module': 'Modul',
    'module_selection': 'Modul secimi',
    'languages': 'Diller',
    'input': 'Girdi',
    'l2_direct': 'L2 dogrudan',
    'l1_to_l2': 'L1 konus, L2 ye aktar',
    'tempo': 'Tempo',
    'speech_rate': 'Konusma hizi',
    'rate_slow': 'Yavas',
    'rate_somewhat_slow': 'Biraz yavas',
    'rate_almost_normal': 'Neredeyse normal',
    'rate_normal': 'Normal',
    'fallback': 'Fallback',
    'controlled_response': 'Kontrollu yanit',
    'runtime_unavailable': 'Parser yok - Responder yok',
    'row_dailywords': 'Gunluk kelimeler',
    'row_cafe': 'Cafe',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'Ilk kelimeler',
  },
  'ar': {
    'scene': 'مشهد',
    'training': 'تدريب',
    'dialog': 'حوار',
    'back_home': 'العودة إلى DailyWords',
    'options': 'خيارات',
    'export_debug': 'تصدير سجل التصحيح',
    'export_dialog': 'تصدير سجل الحوار',
    'close': 'إغلاق',
    'module': 'وحدة',
    'module_selection': 'اختيار الوحدة',
    'languages': 'لغات',
    'input': 'إدخال',
    'l2_direct': 'L2 مباشر',
    'l1_to_l2': 'تحدث L1، انقل إلى L2',
    'tempo': 'إيقاع',
    'speech_rate': 'سرعة الكلام',
    'rate_slow': 'بطيء',
    'rate_somewhat_slow': 'بطيء قليلا',
    'rate_almost_normal': 'شبه طبيعي',
    'rate_normal': 'طبيعي',
    'fallback': 'احتياطي',
    'controlled_response': 'استجابة مضبوطة',
    'runtime_unavailable': 'Parser n/a - Responder n/a',
    'row_dailywords': 'كلمات يومية',
    'row_cafe': 'مقهى',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'الكلمات الأولى',
  },
  'hi': {
    'scene': 'दृश्य',
    'training': 'अभ्यास',
    'dialog': 'संवाद',
    'back_home': 'DailyWords पर वापस',
    'options': 'विकल्प',
    'export_debug': 'Debug log निर्यात',
    'export_dialog': 'Dialog log निर्यात',
    'close': 'बंद करें',
    'module': 'मॉड्यूल',
    'module_selection': 'मॉड्यूल चयन',
    'languages': 'भाषाएं',
    'input': 'इनपुट',
    'l2_direct': 'L2 सीधा',
    'l1_to_l2': 'L1 बोलें, L2 में बदलें',
    'tempo': 'गति',
    'speech_rate': 'बोलने की गति',
    'rate_slow': 'धीमा',
    'rate_somewhat_slow': 'थोड़ा धीमा',
    'rate_almost_normal': 'लगभग सामान्य',
    'rate_normal': 'सामान्य',
    'fallback': 'वैकल्पिक',
    'controlled_response': 'नियंत्रित उत्तर',
    'runtime_unavailable': 'Parser n/a - Responder n/a',
    'row_dailywords': 'दैनिक शब्द',
    'row_cafe': 'कैफे',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'पहले शब्द',
  },
  'zh': {
    'scene': '场景',
    'training': '训练',
    'dialog': '对话',
    'back_home': '返回 DailyWords',
    'options': '选项',
    'export_debug': '导出调试日志',
    'export_dialog': '导出对话日志',
    'close': '关闭',
    'module': '模块',
    'module_selection': '模块选择',
    'languages': '语言',
    'input': '输入',
    'l2_direct': 'L2 直接',
    'l1_to_l2': '说 L1，转换到 L2',
    'tempo': '速度',
    'speech_rate': '语速',
    'rate_slow': '慢',
    'rate_somewhat_slow': '稍慢',
    'rate_almost_normal': '接近正常',
    'rate_normal': '正常',
    'fallback': '备用',
    'controlled_response': '受控回答',
    'runtime_unavailable': 'Parser n/a - Responder n/a',
    'row_dailywords': '每日词汇',
    'row_cafe': '咖啡馆',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': '初学词汇',
  },
  'ja': {
    'scene': 'シーン',
    'training': 'トレーニング',
    'dialog': 'ダイアログ',
    'back_home': 'DailyWords に戻る',
    'options': 'オプション',
    'export_debug': 'デバッグログを書き出す',
    'export_dialog': 'ダイアログログを書き出す',
    'close': '閉じる',
    'module': 'モジュール',
    'module_selection': 'モジュール選択',
    'languages': '言語',
    'input': '入力',
    'l2_direct': 'L2 直接',
    'l1_to_l2': 'L1 で話し、L2 へ変換',
    'tempo': 'テンポ',
    'speech_rate': '話す速度',
    'rate_slow': '遅い',
    'rate_somewhat_slow': 'やや遅い',
    'rate_almost_normal': 'ほぼ通常',
    'rate_normal': '通常',
    'fallback': 'フォールバック',
    'controlled_response': '制御された応答',
    'runtime_unavailable': 'Parser n/a - Responder n/a',
    'row_dailywords': '毎日の単語',
    'row_cafe': 'カフェ',
    'row_peter': 'Peter',
    'row_lara': 'Lara',
    'row_first_words': 'はじめての単語',
  },
};

const List<_DailywordsModuleRow> _moduleRows = [
  _DailywordsModuleRow(
    id: 'dailywords',
    sceneAsset: 'assets/icons/module_house.webp',
    startKey: 'start_curriculum_a.json',
    dialogSceneId: 'therapy',
  ),
  _DailywordsModuleRow(
    id: 'cafe',
    sceneAsset: 'assets/icons/module_cafe.webp',
    startKey: 'start_curriculum_realtalk_cafe.json',
    dialogSceneId: 'robo_cafe',
  ),
  _DailywordsModuleRow(
    id: 'peter',
    sceneAsset: 'assets/icons/module_peter.webp',
    startKey: 'start_curriculum_t.json',
    trainingIconAsset: 'assets/icons/module_construction.webp',
    dialogSceneId: 'bergstube_peter',
  ),
  _DailywordsModuleRow(
    id: 'lara',
    sceneAsset: 'assets/icons/module_lara.webp',
    startKey: 'start_curriculum_l.json',
    trainingIconAsset: 'assets/icons/module_construction.webp',
    dialogSceneId: 'taverna_lara',
  ),
  _DailywordsModuleRow(
    id: 'first_words',
    sceneAsset: 'assets/icons/module_toddler.webp',
    startKey: 'start_curriculum_b.json',
    dialogIconAsset: 'assets/icons/module_construction.webp',
    dialogPath: '/therapy/',
  ),
];
