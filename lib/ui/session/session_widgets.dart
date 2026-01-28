// ------------------------------------------------------------
// Ziel (Laien): Zentrale Session-Widgets für 2AFC + Benennen + Splash/Dashboard-Trigger bündeln.
// Verbindung: Wird direkt von robulingo_app.dart verwendet; nutzt HexagonTrack, Dashboard, Mic-UI.
// Tücken: Erwartet Status/Callbacks aus dem App-State (Trials, Naming-Flow, Wins); kein eigener State.
// ------------------------------------------------------------
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:robulingo_flutter/data/hint_models.dart';
import 'package:robulingo_flutter/logic/hexagon_controller.dart';
import 'package:robulingo_flutter/ui/dashboard/dashboard_screen.dart';
import 'package:robulingo_flutter/ui/dashboard_button.dart';
import 'package:robulingo_flutter/ui/hexagon_track.dart';
import 'package:robulingo_flutter/ui/training_calendar_panel.dart';

class RestartModuleProgress {
  const RestartModuleProgress({
    required this.iconAsset,
    required this.progress,
    required this.completed,
    required this.total,
    required this.freeItemsTotal,
    required this.freeItemsRemaining,
  });

  final String iconAsset;
  final double progress;
  final int completed;
  final int total;
  final int freeItemsTotal;
  final int freeItemsRemaining;

  RestartModuleProgress copyWith({
    String? iconAsset,
    double? progress,
    int? completed,
    int? total,
    int? freeItemsTotal,
    int? freeItemsRemaining,
  }) {
    return RestartModuleProgress(
      iconAsset: iconAsset ?? this.iconAsset,
      progress: progress ?? this.progress,
      completed: completed ?? this.completed,
      total: total ?? this.total,
      freeItemsTotal: freeItemsTotal ?? this.freeItemsTotal,
      freeItemsRemaining: freeItemsRemaining ?? this.freeItemsRemaining,
    );
  }
}

class RestartSplash extends StatefulWidget {
  const RestartSplash({
    super.key,
    required this.wins,
    required this.rivalWins,
    required this.viewCount,
    required this.onRestart,
    required this.onStart,
    required this.moduleProgress,
  });

  final int wins;
  final int rivalWins;
  final int viewCount;
  final VoidCallback onRestart;
  final VoidCallback onStart;
  final RestartModuleProgress moduleProgress;

  @override
  State<RestartSplash> createState() => _RestartSplashState();
}

class _RestartSplashState extends State<RestartSplash> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            Image.asset('assets/icons/RL_logo.webp',
                height: 120, fit: BoxFit.contain),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                height: 200,
                child: VictoryPanel(
                  wins: widget.wins,
                  rivalWins: widget.rivalWins,
                  rivalAssetPath: RivalAssetResolver.pathFor(
                    wins: widget.wins,
                    rivalWins: widget.rivalWins,
                    viewCount: widget.viewCount,
                  ),
                  therapistAssetPath: TherapistAssetResolver.pathFor(
                    wins: widget.wins,
                    rivalWins: widget.rivalWins,
                  ),
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: TrainingCalendarPanel(),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: widget.onRestart,
                    child: Image.asset('assets/icons/toolbox.webp',
                        width: 72, height: 72),
                  ),
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 140,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(widget.moduleProgress.iconAsset,
                                width: 64, height: 64, fit: BoxFit.contain),
                            const SizedBox(height: 10),
                            _RestartModuleProgressIndicator(
                                widget.moduleProgress),
                          ],
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onStart,
                    child: Image.asset('assets/icons/start_arrow.webp',
                        width: 88, height: 88),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestartModuleProgressIndicator extends StatelessWidget {
  const _RestartModuleProgressIndicator(this.progress);

  final RestartModuleProgress progress;

  @override
  Widget build(BuildContext context) {
    final double progressRatio = (progress.total > 0
            ? (progress.completed / progress.total)
            : progress.progress)
        .clamp(0.0, 1.0);
    final bool hasFreeBar = progress.freeItemsTotal > 0;
    final double freeRatio = hasFreeBar
        ? (progress.freeItemsRemaining / progress.freeItemsTotal)
            .clamp(0.0, 1.0)
        : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBar(
          context,
          ratio: progressRatio,
          color: Theme.of(context).colorScheme.primary,
        ),
        if (hasFreeBar) ...[
          const SizedBox(height: 4),
          _buildBar(
            context,
            ratio: freeRatio,
            color: Colors.green.shade200,
          ),
        ],
      ],
    );
  }

  Widget _buildBar(BuildContext context,
      {required double ratio, required Color color}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Container(
                width: double.infinity,
                height: 6,
                color: Colors.grey.shade300,
              ),
              FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  height: 6,
                  color: color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NamingView extends StatelessWidget {
  const NamingView({
    super.key,
    required this.leftImageBytes,
    required this.rightImageBytes,
    required this.targetOnLeft,
    required this.imageHeight,
    required this.namingOutcome,
    required this.namingStatus,
    required this.micPrimed,
    required this.micDenied,
    required this.micPermanentlyDenied,
    required this.speechPermanentlyDenied,
    required this.namingHold,
    required this.showHourglass,
    required this.namingInProgress,
    required this.liveTranscript,
    required this.onStartNaming,
    required this.onOpenSettings,
    required this.onSkip,
    this.onPostpone,
  });

  final Uint8List leftImageBytes;
  final Uint8List rightImageBytes;
  final bool targetOnLeft;
  final double imageHeight;
  final bool? namingOutcome;
  final String namingStatus;
  final bool micPrimed;
  final bool micDenied;
  final bool micPermanentlyDenied;
  final bool speechPermanentlyDenied;
  final bool namingHold;
  final bool showHourglass;
  final bool namingInProgress;
  final String liveTranscript;
  final VoidCallback onStartNaming;
  final VoidCallback onOpenSettings;
  final void Function(String reason) onSkip;
  final VoidCallback? onPostpone;

  @override
  Widget build(BuildContext context) {
    final bool isCorrect = namingOutcome == true;
    final Color borderColor = namingOutcome == null
        ? Colors.grey.shade400
        : (isCorrect ? Colors.green : Colors.red);
    final Color? cardFill = namingOutcome == null
        ? null
        : (isCorrect ? Colors.green.shade200 : Colors.red.shade200);
    final bool suppressDuringRepeat =
        namingStatus == 'Hör zu...' || namingStatus == 'Wiederhole...';
    final bool showRepeatIcon = namingStatus == 'Wiederhole...';
    final statusText = suppressDuringRepeat
        ? ''
        : (namingStatus.isEmpty
            ? (!micPrimed ? 'Tippe das Mikro, um zu benennen.' : '')
            : namingStatus);
    final bool showTranscript =
        namingOutcome != null || liveTranscript.isNotEmpty;
    final String transcriptText =
        liveTranscript.isEmpty ? 'Keine ASR-Erkennung' : liveTranscript;
    final Uint8List targetImageBytes =
        targetOnLeft ? leftImageBytes : rightImageBytes;
    final Uint8List otherImageBytes =
        targetOnLeft ? rightImageBytes : leftImageBytes;

    Widget buildImageTile(
      Uint8List bytes, {
      required bool isTarget,
      required bool dimNonTarget,
      required double tileWidth,
      required double tileHeight,
    }) {
      final bool showOutcome = isTarget && namingOutcome != null;
      final Widget image = Image.memory(bytes, fit: BoxFit.contain);
      final Widget imageLayer = dimNonTarget
          ? Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                  child: image,
                ),
                Container(color: Colors.grey.withValues(alpha: 0.35)),
              ],
            )
          : image;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          width: tileWidth,
          height: tileHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                imageLayer,
                if (showOutcome)
                  Container(
                    color: namingOutcome!
                        ? Colors.green.withValues(alpha: 0.6)
                        : Colors.red.withValues(alpha: 0.45),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (onPostpone != null)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Benennen verschieben',
              onPressed: namingInProgress ? null : onPostpone,
              icon: const ImageIcon(
                AssetImage('assets/icons/postpone.webp'),
                size: 28,
              ),
            ),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardFill,
            border: Border.all(
                color: borderColor, width: namingOutcome == null ? 3 : 4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final double maxWidth = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : imageHeight * 1.5;
                  final double desiredWidth = imageHeight * 0.75;
                  final double availableWidth =
                      (maxWidth - 24).clamp(0.0, maxWidth).toDouble();
                  final double tileWidth =
                      (availableWidth / 2).clamp(0.0, desiredWidth).toDouble();
                  final double tileHeight =
                      (tileWidth * 4 / 3).clamp(0.0, imageHeight).toDouble();

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      buildImageTile(
                        targetImageBytes,
                        isTarget: true,
                        dimNonTarget: false,
                        tileWidth: tileWidth,
                        tileHeight: tileHeight,
                      ),
                      buildImageTile(
                        otherImageBytes,
                        isTarget: false,
                        dimNonTarget: true,
                        tileWidth: tileWidth,
                        tileHeight: tileHeight,
                      ),
                    ],
                  );
                },
              ),
              if (namingOutcome != null)
                Positioned.fill(
                  child: Center(
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          namingOutcome! ? Colors.green : Colors.red,
                      child: Icon(
                        namingOutcome! ? Icons.check : Icons.close,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (statusText.isNotEmpty || showRepeatIcon) ...[
          const SizedBox(height: 8),
          if (showRepeatIcon)
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.green,
              child: Icon(Icons.refresh, color: Colors.white, size: 18),
            )
          else
            Text(statusText, style: const TextStyle(fontSize: 14)),
        ],
        if (showHourglass)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(Icons.hourglass_top,
                size: 18, color: Colors.grey.shade700),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ElevatedButton.icon(
            onPressed: namingInProgress ? null : onStartNaming,
            icon: const Icon(Icons.mic),
            label: const Text('Aufnehmen'),
          ),
        ),
        if (micDenied || namingHold)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => onSkip('mic-denied'),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Weiter'),
            ),
          ),
        if (micDenied || micPermanentlyDenied || speechPermanentlyDenied)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Einstellungen öffnen'),
            ),
          ),
        IconButton(
          onPressed: () => onSkip('user-skip'),
          icon: const Icon(Icons.refresh,
              color: Colors.red, size: 28, opticalSize: 28),
          tooltip: 'Überspringen',
        ),
        if (showTranscript) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: namingOutcome == null
                  ? Colors.grey.shade200
                  : (isCorrect ? Colors.green.shade50 : Colors.red.shade50),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                if (namingOutcome != null)
                  Icon(
                    isCorrect ? Icons.check : Icons.close,
                    size: 16,
                    color:
                        isCorrect ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                Text(
                  'ASR: $transcriptText',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: namingOutcome == null
                        ? Colors.grey.shade800
                        : (isCorrect
                            ? Colors.green.shade800
                            : Colors.red.shade800),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class TrialOptionsRow extends StatelessWidget {
  const TrialOptionsRow({
    super.key,
    required this.leftImageBytes,
    required this.rightImageBytes,
    required this.imageHeight,
    required this.hasAnswered,
    required this.lastSelectionIsLeft,
    required this.targetOnLeft,
    required this.disableSelection,
    this.spokenCueText,
    required this.onSelect,
  });

  final Uint8List leftImageBytes;
  final Uint8List rightImageBytes;
  final double imageHeight;
  final bool hasAnswered;
  final bool? lastSelectionIsLeft;
  final bool targetOnLeft;
  final bool disableSelection;
  final String? spokenCueText;
  final void Function(bool choseLeft) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: imageHeight,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TrialOption(
                  imageBytes: leftImageBytes,
                  imageHeight: imageHeight,
                  hasAnswered: hasAnswered,
                  lastSelectionIsLeft: lastSelectionIsLeft,
                  targetOnLeft: targetOnLeft,
                  isLeft: true,
                  disableSelection: disableSelection,
                  onSelect: onSelect,
                ),
                _TrialOption(
                  imageBytes: rightImageBytes,
                  imageHeight: imageHeight,
                  hasAnswered: hasAnswered,
                  lastSelectionIsLeft: lastSelectionIsLeft,
                  targetOnLeft: targetOnLeft,
                  isLeft: false,
                  disableSelection: disableSelection,
                  onSelect: onSelect,
                ),
              ],
            ),
          ),
          /*if (spokenCueText != null && spokenCueText!.isNotEmpty)
            Positioned(
              top: 0,
              left: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 6,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: const Text("")
              ),
            ),*/
        ],
      ),
    );
  }
}

class _TrialOption extends StatelessWidget {
  const _TrialOption({
    required this.imageBytes,
    required this.imageHeight,
    required this.hasAnswered,
    required this.lastSelectionIsLeft,
    required this.targetOnLeft,
    required this.isLeft,
    required this.disableSelection,
    required this.onSelect,
  });

  final Uint8List imageBytes;
  final double imageHeight;
  final bool hasAnswered;
  final bool? lastSelectionIsLeft;
  final bool targetOnLeft;
  final bool isLeft;
  final bool disableSelection;
  final void Function(bool choseLeft) onSelect;

  @override
  Widget build(BuildContext context) {
    final bool isSelected = hasAnswered && lastSelectionIsLeft == isLeft;
    final bool isTargetSide = targetOnLeft == isLeft;
    Color border = Colors.grey.shade400;
    Color? fill;
    if (hasAnswered) {
      if (isTargetSide) border = Colors.green;
      if (isSelected && isTargetSide) {
        fill = Colors.green.shade50;
      } else if (isSelected && !isTargetSide) {
        border = Colors.red;
        fill = Colors.red.shade50;
      }
    }

    return Expanded(
      child: GestureDetector(
        onTap: disableSelection ? null : () => onSelect(isLeft),
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border, width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: imageHeight,
              minHeight: imageHeight,
            ),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SessionBody extends StatelessWidget {
  const SessionBody({
    super.key,
    required this.ladder,
    required this.isNaming,
    required this.imageHeight,
    required this.leftImageBytes,
    required this.rightImageBytes,
    required this.targetOnLeft,
    required this.hasAnswered,
    required this.lastSelectionIsLeft,
    required this.namingOutcome,
    required this.namingStatus,
    required this.micPrimed,
    required this.micDenied,
    required this.micPermanentlyDenied,
    required this.speechPermanentlyDenied,
    required this.namingHold,
    required this.showHourglass,
    required this.namingInProgress,
    required this.liveTranscript,
    required this.targetText,
    required this.targetPhonetic,
    required this.phoneticButtonVisible,
    required this.phoneticOverrideActive,
    required this.phoneticOverrideRemaining,
    this.onTogglePhonetic,
    this.spokenCueText,
    required this.nativeText,
    required this.showNative,
    required this.hintEntries,
    required this.hintLabel,
    this.hintMissingText,
    required this.hintButtonVisible,
    required this.hintButtonActive,
    required this.onToggleHints,
    this.hintPanelKey,
    required this.audioHintEnabled,
    required this.onPlayAudioHint,
    required this.showDashboardButton,
    required this.showGlobalHourglass,
    required this.onPrimeMic,
    required this.onOpenMicSettings,
    required this.onSkipNaming,
    required this.onSelect,
    required this.onOpenDashboard,
    required this.hasPostponedNamingBlocks,
    required this.onReactivateNamingBlocks,
    required this.onPostponeNamingBlocks,
  });

  final HexagonState ladder;
  final bool isNaming;
  final double imageHeight;
  final Uint8List leftImageBytes;
  final Uint8List rightImageBytes;
  final bool targetOnLeft;
  final bool hasAnswered;
  final bool? lastSelectionIsLeft;
  final bool? namingOutcome;
  final String namingStatus;
  final bool micPrimed;
  final bool micDenied;
  final bool micPermanentlyDenied;
  final bool speechPermanentlyDenied;
  final bool namingHold;
  final bool showHourglass;
  final bool namingInProgress;
  final String liveTranscript;
  final String targetText;
  final String? targetPhonetic;
  final bool phoneticButtonVisible;
  final bool phoneticOverrideActive;
  final int phoneticOverrideRemaining;
  final VoidCallback? onTogglePhonetic;
  final String? spokenCueText;
  final String? nativeText;
  final bool showNative;
  final List<HintContent> hintEntries;
  final String hintLabel;
  final String? hintMissingText;
  final bool hintButtonVisible;
  final bool hintButtonActive;
  final VoidCallback onToggleHints;
  final Key? hintPanelKey;
  final bool audioHintEnabled;
  final VoidCallback onPlayAudioHint;
  final bool showDashboardButton;
  final bool showGlobalHourglass;
  final VoidCallback onPrimeMic;
  final VoidCallback onOpenMicSettings;
  final void Function(String reason) onSkipNaming;
  final void Function(bool choseLeft) onSelect;
  final VoidCallback onOpenDashboard;
  final bool hasPostponedNamingBlocks;
  final VoidCallback? onReactivateNamingBlocks;
  final VoidCallback? onPostponeNamingBlocks;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final double bottomBarHeight = namingInProgress ? 48.0 : 0.0;
    final double verticalInsets =
        MediaQuery.of(context).padding.vertical + 32 + bottomBarHeight;
    final double availableHeight = size.height - verticalInsets;

    final trackWidget = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HexagonTrack(
        youIndex: ladder.youIndex,
        rivalIndex: ladder.rivalIndex,
        youFlagVisible: ladder.youFlagVisible,
        rivalFlagVisible: ladder.rivalFlagVisible,
        youFlagAngle: ladder.youFlagAngle,
        rivalFlagAngle: ladder.rivalFlagAngle,
        youFlagShowIndex: ladder.youFlagShowIndex,
        rivalFlagShowIndex: ladder.rivalFlagShowIndex,
        youTrail: ladder.youTrail,
        rivalTrail: ladder.rivalTrail,
      ),
    );

    final trialWidget = isNaming
        ? NamingView(
            leftImageBytes: leftImageBytes,
            rightImageBytes: rightImageBytes,
            targetOnLeft: targetOnLeft,
            imageHeight: imageHeight,
            namingOutcome: namingOutcome,
            namingStatus: namingStatus,
            micPrimed: micPrimed,
            micDenied: micDenied,
            micPermanentlyDenied: micPermanentlyDenied,
            speechPermanentlyDenied: speechPermanentlyDenied,
            namingHold: namingHold,
            showHourglass: showHourglass,
            namingInProgress: namingInProgress,
            liveTranscript: liveTranscript,
            onStartNaming: onPrimeMic,
            onOpenSettings: onOpenMicSettings,
            onSkip: onSkipNaming,
            onPostpone: onPostponeNamingBlocks,
          )
        : TrialOptionsRow(
            leftImageBytes: leftImageBytes,
            rightImageBytes: rightImageBytes,
            imageHeight: imageHeight,
            hasAnswered: hasAnswered,
            lastSelectionIsLeft: lastSelectionIsLeft,
            targetOnLeft: targetOnLeft,
            disableSelection: isNaming,
            spokenCueText: spokenCueText,
            onSelect: onSelect,
          );

      final contentColumn = Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLandscape) const SizedBox(height: 4),
        trialWidget,
        //const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF9FAFF), Color(0xFFEFF3FF)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              if (targetText.trim().isNotEmpty ||
                  (targetPhonetic != null && targetPhonetic!.trim().isNotEmpty))
                Text.rich(
                  TextSpan(
                    text: targetText,
                    children: [
                      if (targetPhonetic != null && targetPhonetic!.isNotEmpty)
                        TextSpan(
                          text: '  ${targetPhonetic!}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontStyle: FontStyle.italic,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold),
                ),
              if (showNative && nativeText != null && nativeText!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  nativeText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.green),
                ),
              ],
              if (phoneticButtonVisible ||
                  audioHintEnabled ||
                  hintButtonVisible ||
                  hasPostponedNamingBlocks) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (hasPostponedNamingBlocks && !isNaming)
                      Tooltip(
                        message: 'Benennen',
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFEFF6FF),
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Colors.black12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: onReactivateNamingBlocks,
                          child: const ImageIcon(
                            AssetImage('assets/icons/antepone.webp'),
                            size: 20,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    if (phoneticButtonVisible)
                      Tooltip(
                        message: 'Phonetic',
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: phoneticOverrideActive
                                ? const Color(0xFFE7F0FF)
                                : Colors.white,
                            foregroundColor: Colors.black87,
                            side: BorderSide(
                              color: phoneticOverrideActive
                                  ? const Color(0xFF8AB4F8)
                                  : Colors.black12,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: onTogglePhonetic,
                          child: ImageIcon(
                            const AssetImage('assets/icons/phonetic.webp'),
                            color: phoneticOverrideActive
                                ? Colors.blue
                                : Colors.grey[700],
                            size: 20,
                          ),
                        ),
                      ),
                    if (audioHintEnabled)
                      Tooltip(
                        message: 'Audio hint',
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Colors.black12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: onPlayAudioHint,
                          child: const Icon(Icons.volume_up, size: 20),
                        ),
                      ),
                    if (hintButtonVisible)
                      Tooltip(
                        message: hintLabel,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: hintButtonActive
                                ? const Color(0xFFFFF2C0)
                                : Colors.white,
                            foregroundColor: Colors.black87,
                            side: BorderSide(
                              color: hintButtonActive
                                  ? const Color(0xFFE7C36A)
                                  : Colors.black12,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: onToggleHints,
                          child: ImageIcon(
                            const AssetImage('assets/icons/Magnifying_glass.webp'),
                            size: 20,
                            color: hintButtonActive
                                ? const Color(0xFF8A6B12)
                                : Colors.grey[800],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (hintEntries.isNotEmpty) ...[
                const SizedBox(height: 12),
                _HintPanel(key: hintPanelKey, label: hintLabel, hints: hintEntries),
              ] else if (hintMissingText != null &&
                  hintMissingText!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  hintMissingText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black45),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            DashboardButtonRow(
              show: showDashboardButton || ladder.hasFlagAppeared,
              showHourglass: showGlobalHourglass,
              hourglassWiggle: showGlobalHourglass,
              onTap: onOpenDashboard,
            ),
          ],
        ),
      ],
    );

    if (!isLandscape) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            trackWidget,
            contentColumn,
          ],
        ),
      );
    }

    final double trialHeight = imageHeight + 24;
    final double maxTrackHeight =
        (availableHeight - trialHeight - 12).clamp(0.0, availableHeight) * 0.85;
    final Widget landscapeTrackWidget = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxTrackHeight),
      child: Align(
        alignment: Alignment.topCenter,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: trackWidget,
        ),
      ),
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        landscapeTrackWidget,
        contentColumn,
      ],
    );
  }
}

class _HintPanel extends StatelessWidget {
  const _HintPanel({super.key, required this.label, required this.hints});

  final String label;
  final List<HintContent> hints;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7DD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          ...hints.map(
            (hint) {
              final title = hint.title?.trim();
              final body = hint.body?.trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null && title.isNotEmpty)
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    if (body != null && body.isNotEmpty)
                      Text(
                        body,
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    if (hint.examples.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Examples: ${hint.examples.join(', ')}',
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
