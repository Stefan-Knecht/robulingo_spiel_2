// ------------------------------------------------------------
// Ziel (Laien): Zentrale Session-Widgets für 2AFC + Benennen + Splash/Dashboard-Trigger bündeln.
// Verbindung: Wird direkt von robulingo_app.dart verwendet; nutzt HexagonTrack, Dashboard, Mic-UI.
// Tücken: Erwartet Status/Callbacks aus dem App-State (Trials, Naming-Flow, Wins); kein eigener State.
// ------------------------------------------------------------
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
    required this.imageBytes,
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
  });

  final Uint8List imageBytes;
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

    return Column(
      children: [
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
            alignment: Alignment.topRight,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: imageHeight,
                  minHeight: imageHeight,
                ),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          imageBytes,
                          fit: BoxFit.contain,
                        ),
                        if (namingOutcome != null)
                          Container(
                            color: namingOutcome!
                                ? Colors.green.withValues(alpha: 0.6)
                                : Colors.red.withValues(alpha: 0.45),
                          ),
                      ],
                    ),
                  ),
                ),
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
    required this.onSelect,
  });

  final Uint8List leftImageBytes;
  final Uint8List rightImageBytes;
  final double imageHeight;
  final bool hasAnswered;
  final bool? lastSelectionIsLeft;
  final bool targetOnLeft;
  final bool disableSelection;
  final void Function(bool choseLeft) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: imageHeight + 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
    required this.nativeText,
    required this.showNative,
    required this.showDashboardButton,
    required this.showGlobalHourglass,
    required this.onPrimeMic,
    required this.onOpenMicSettings,
    required this.onSkipNaming,
    required this.onSelect,
    required this.onOpenDashboard,
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
  final String? nativeText;
  final bool showNative;
  final bool showDashboardButton;
  final bool showGlobalHourglass;
  final VoidCallback onPrimeMic;
  final VoidCallback onOpenMicSettings;
  final void Function(String reason) onSkipNaming;
  final void Function(bool choseLeft) onSelect;
  final VoidCallback onOpenDashboard;

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
            imageBytes: targetOnLeft ? leftImageBytes : rightImageBytes,
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
          )
        : TrialOptionsRow(
            leftImageBytes: leftImageBytes,
            rightImageBytes: rightImageBytes,
            imageHeight: imageHeight,
            hasAnswered: hasAnswered,
            lastSelectionIsLeft: lastSelectionIsLeft,
            targetOnLeft: targetOnLeft,
            disableSelection: isNaming,
            onSelect: onSelect,
          );

    final contentColumn = Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLandscape) const SizedBox(height: 4),
        trialWidget,
        const SizedBox(height: 32),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (phoneticButtonVisible)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  padding: const EdgeInsets.all(2),
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  iconSize: 28,
                  icon: ImageIcon(
                    const AssetImage('assets/icons/phonetic.webp'),
                    color:
                        phoneticOverrideActive ? Colors.blue : Colors.grey[600],
                  ),
                  onPressed: onTogglePhonetic,
                  tooltip: phoneticOverrideActive
                      ? 'Phonetik bleibt noch $phoneticOverrideRemaining Durchläufe sichtbar'
                      : 'Phonetik für 10 Durchläufe anzeigen',
                ),
              ),
            Flexible(
              child: Text.rich(
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
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (showNative && nativeText != null && nativeText!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            nativeText!,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: Colors.green),
          ),
        ],
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
            const SizedBox(height: 12),
            contentColumn,
          ],
        ),
      );
    }

    final double trialHeight = imageHeight + 24;
    final double maxTrackHeight =
        (availableHeight - trialHeight - 12).clamp(0.0, availableHeight);
    final Widget landscapeTrackWidget = SizedBox(
      height: maxTrackHeight,
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: trackWidget,
      ),
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        landscapeTrackWidget,
        const SizedBox(height: 12),
        trialWidget,
      ],
    );
  }
}
