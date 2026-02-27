// ------------------------------------------------------------
// Ziel (Laien): Session-Dashboard anzeigen (Siege, Kalender, Erfolgsserie).
// Verbindung: robulingo_app.dart öffnet es über DashboardButton; liest Logs + Live-Stats.
// Tücken: NDJSON-Logs müssen existieren; Asset-Pfade für Rival/Therapist hängen von Wins/ViewCount ab.
// ------------------------------------------------------------
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:robulingo_flutter/flavor_config.dart';

import '../../logic/log_storage.dart';

const Map<String, Map<String, String>> _dashboardTooltipTexts = {
  'victory_panel': {
    'en': "Your and rival's victories",
    'de': 'Deine und die Siege deines Rivalen',
    'ar': 'انتصاراتك وانتصارات منافسك',
    'fr': 'Vos victoires et celles de votre rival',
    'es': 'Tus victorias y las de tu rival',
    'it': 'Le tue vittorie e quelle del tuo rivale',
    'ru': 'Ваши победы и победы соперника',
    'hi': 'आपकी और प्रतिद्वंद्वी की जीतें',
    'el': 'Οι νίκες σου και του αντιπάλου',
    'zh': '你和对手的胜利',
    'tr': 'Senin ve rakibin galibiyetleri',
    'ja': 'あなたとライバルの勝利数',
  },
  'training_panel': {
    'en': 'Training on last days',
    'de': 'Training an den letzten Tagen',
    'ar': 'التدريب خلال الأيام الأخيرة',
    'fr': 'Entraînement des derniers jours',
    'es': 'Entrenamiento de los últimos días',
    'it': 'Allenamento degli ultimi giorni',
    'ru': 'Тренировки за последние дни',
    'hi': 'पिछले दिनों का प्रशिक्षण',
    'el': 'Προπόνηση των τελευταίων ημερών',
    'zh': '最近几天的训练',
    'tr': 'Son günlerdeki antrenman',
    'ja': '直近数日のトレーニング',
  },
  'success_panel': {
    'en': 'Progress in comprehension and naming',
    'de': 'Fortschritt im Verstehen und Benennen',
    'ar': 'التقدم في الفهم والتسمية',
    'fr': 'Progression en compréhension et dénomination',
    'es': 'Progreso en comprensión y denominación',
    'it': 'Progresso in comprensione e denominazione',
    'ru': 'Прогресс в понимании и назывании',
    'hi': 'समझ और नामकरण में प्रगति',
    'el': 'Πρόοδος στην κατανόηση και ονομασία',
    'zh': '理解与命名进展',
    'tr': 'Anlama ve adlandırmada ilerleme',
    'ja': '理解と命名の進捗',
  },
  'exit_game': {
    'en': 'Exit game',
    'de': 'Spiel beenden',
    'ar': 'الخروج من اللعبة',
    'fr': 'Quitter le jeu',
    'es': 'Salir del juego',
    'it': 'Esci dal gioco',
    'ru': 'Выйти из игры',
    'hi': 'गेम से बाहर निकलें',
    'el': 'Έξοδος από το παιχνίδι',
    'zh': '退出游戏',
    'tr': 'Oyundan çık',
    'ja': 'ゲームを終了',
  },
  'continue_playing': {
    'en': 'Continue playing',
    'de': 'Weiter spielen',
    'ar': 'متابعة اللعب',
    'fr': 'Continuer à jouer',
    'es': 'Seguir jugando',
    'it': 'Continua a giocare',
    'ru': 'Продолжить игру',
    'hi': 'खेलना जारी रखें',
    'el': 'Συνέχισε το παιχνίδι',
    'zh': '继续游戏',
    'tr': 'Oynamaya devam et',
    'ja': 'プレイを続ける',
  },
  'you': {
    'en': 'You',
    'de': 'Du',
    'ar': 'أنت',
    'fr': 'Vous',
    'es': 'Tú',
    'it': 'Tu',
    'ru': 'Вы',
    'hi': 'आप',
    'el': 'Εσύ',
    'zh': '你',
    'tr': 'Sen',
    'ja': 'あなた',
  },
  'your_rival': {
    'en': 'Your rival',
    'de': 'Dein Rivale',
    'ar': 'منافسك',
    'fr': 'Votre rival',
    'es': 'Tu rival',
    'it': 'Il tuo rivale',
    'ru': 'Ваш соперник',
    'hi': 'आपका प्रतिद्वंद्वी',
    'el': 'Ο αντίπαλός σου',
    'zh': '你的对手',
    'tr': 'Rakibin',
    'ja': 'あなたのライバル',
  },
};

String _dashboardTooltipText(String key, String languageCode) {
  final byKey = _dashboardTooltipTexts[key];
  if (byKey == null) return key;
  final code = languageCode.trim().toLowerCase();
  return byKey[code] ?? byKey['en'] ?? key;
}

class DashboardScreen extends StatefulWidget {
  final String focus;
  final int wins;
  final int rivalWins;
  final int mastered;
  final int dashboardViewCount;
  final DateTime? sessionStart;
  final List<bool> comprehensionHistory;
  final List<bool> namingHistory;
  final Map<String, int> comprehensionAttempts;
  final Map<String, int> namingAttempts;
  final Future<void> Function() onExitToResumePanel;
  final Future<String> Function()? onExportProtocol;
  final VoidCallback? onReturnToGame;
  final String tooltipLanguageCode;

  const DashboardScreen({
    super.key,
    required this.focus,
    required this.wins,
    required this.rivalWins,
    required this.mastered,
    required this.dashboardViewCount,
    required this.sessionStart,
    required this.comprehensionHistory,
    required this.namingHistory,
    required this.comprehensionAttempts,
    required this.namingAttempts,
    required this.onExitToResumePanel,
    required this.tooltipLanguageCode,
    this.onExportProtocol,
    this.onReturnToGame,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _dataFuture;
  bool _exitInProgress = false;
  static const String _cliCommandsText = '''←    →
F     J
''';

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_DashboardData> _loadData() async {
    final currentMinutes = _currentSessionMinutes();
    final weekMinutes = await DashboardDataLoader.loadWeekMinutes(
        currentSessionMinutes: currentMinutes);
    final rivalAssetPath = RivalAssetResolver.pathFor(
      wins: widget.wins,
      rivalWins: widget.rivalWins,
      viewCount: widget.dashboardViewCount,
    );
    final therapistAssetPath = TherapistAssetResolver.pathFor(
        wins: widget.wins, rivalWins: widget.rivalWins);
    final successPoints = await SuccessSeriesLoader.load(
      liveSessionStart: widget.sessionStart,
      liveComprehensionAttempts: widget.comprehensionAttempts,
      liveNamingAttempts: widget.namingAttempts,
    );
    return _DashboardData(
      weekMinutes: weekMinutes,
      rivalAssetPath: rivalAssetPath,
      therapistAssetPath: therapistAssetPath,
      successPoints: successPoints,
    );
  }

  int _currentSessionMinutes() {
    if (widget.sessionStart == null) return 0;
    return max(
        0, DateTime.now().toUtc().difference(widget.sessionStart!).inMinutes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1.0);
            final compactLayout =
                constraints.maxHeight < 700 || textScale > 1.15;
            const contentHorizontal = 12.0;
            const topReserved = 56.0;
            const bottomReserved = 110.0;
            final linkMaxWidth =
                (constraints.maxWidth - 140).clamp(120.0, 360.0).toDouble();

            return FutureBuilder<_DashboardData>(
              future: _dataFuture,
              builder: (context, snapshot) {
                final weekMinutes = snapshot.data?.weekMinutes ?? const <int>[];
                final rivalAssetPath =
                    snapshot.data?.rivalAssetPath ?? 'assets/icons/rival.webp';
                final therapistAssetPath = snapshot.data?.therapistAssetPath ??
                    'assets/icons/therapist_neutral.webp';
                final successPoints =
                    snapshot.data?.successPoints ?? const <SuccessPoint>[];
                final victoryTooltip = _dashboardTooltipText(
                    'victory_panel', widget.tooltipLanguageCode);
                final trainingTooltip = _dashboardTooltipText(
                    'training_panel', widget.tooltipLanguageCode);
                final successTooltip = _dashboardTooltipText(
                    'success_panel', widget.tooltipLanguageCode);
                final exitGameTooltip = _dashboardTooltipText(
                    'exit_game', widget.tooltipLanguageCode);
                final continuePlayingTooltip = _dashboardTooltipText(
                    'continue_playing', widget.tooltipLanguageCode);
                final youTooltip =
                    _dashboardTooltipText('you', widget.tooltipLanguageCode);
                final rivalTooltip = _dashboardTooltipText(
                    'your_rival', widget.tooltipLanguageCode);

                Widget dashboardPanels;
                if (compactLayout) {
                  final usableHeight =
                      (constraints.maxHeight - topReserved - bottomReserved)
                          .clamp(300.0, 1400.0)
                          .toDouble();
                  final panelHeight = ((usableHeight - 20.0) / 3)
                      .clamp(120.0, 320.0)
                      .toDouble();
                  dashboardPanels = SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(contentHorizontal,
                        topReserved, contentHorizontal, bottomReserved),
                    child: Column(
                      children: [
                        SizedBox(
                          height: panelHeight,
                          child: VictoryPanel(
                            wins: widget.wins,
                            rivalWins: widget.rivalWins,
                            rivalAssetPath: rivalAssetPath,
                            therapistAssetPath: therapistAssetPath,
                            tooltipMessage: victoryTooltip,
                            youTooltipMessage: youTooltip,
                            rivalTooltipMessage: rivalTooltip,
                            showPlayerBadge: false,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: panelHeight,
                          child: CalendarPanel(
                            weekMinutes: weekMinutes,
                            tooltipMessage: trainingTooltip,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: panelHeight,
                          child: SuccessPanel(
                            points: successPoints,
                            tooltipMessage: successTooltip,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  dashboardPanels = Padding(
                    padding: const EdgeInsets.fromLTRB(contentHorizontal,
                        topReserved, contentHorizontal, bottomReserved),
                    child: Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: VictoryPanel(
                            wins: widget.wins,
                            rivalWins: widget.rivalWins,
                            rivalAssetPath: rivalAssetPath,
                            therapistAssetPath: therapistAssetPath,
                            tooltipMessage: victoryTooltip,
                            youTooltipMessage: youTooltip,
                            rivalTooltipMessage: rivalTooltip,
                            showPlayerBadge: false,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          flex: 3,
                          child: CalendarPanel(
                            weekMinutes: weekMinutes,
                            tooltipMessage: trainingTooltip,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          flex: 3,
                          child: SuccessPanel(
                            points: successPoints,
                            tooltipMessage: successTooltip,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Stack(
                  children: [
                    Positioned.fill(child: dashboardPanels),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                        tooltip: 'Protokoll exportieren',
                        icon: Icon(
                          Icons.download,
                          size: 38,
                          color: Colors.green.shade700,
                          weight: 800,
                        ),
                        onPressed: widget.onExportProtocol == null
                            ? null
                            : () async {
                                try {
                                  final msg =
                                      await widget.onExportProtocol!.call();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(msg)),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('Export fehlgeschlagen: $e')),
                                  );
                                }
                              },
                      ),
                    ),
                    if (kIsWeb)
                      Positioned(
                        top: 8,
                        left: 64,
                        child: IconButton(
                          tooltip: 'CLI commands',
                          icon: Icon(
                            Icons.code,
                            size: 34,
                            color: Colors.green.shade700,
                            weight: 800,
                          ),
                          onPressed: _showCliCommandsDialog,
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        tooltip: continuePlayingTooltip,
                        icon: Icon(
                          Icons.refresh,
                          size: 40,
                          color: Colors.green.shade700,
                          weight: 800,
                        ),
                        onPressed: () {
                          widget.onReturnToGame?.call();
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Tooltip(
                        message: exitGameTooltip,
                        child: _ExitIconButton(
                          busy: _exitInProgress,
                          onPressed: _handleExitToResume,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: SizedBox(
                        width: linkMaxWidth,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
                            final landingUrl = activeFlavor.dashboardLandingUrl;
                            final uri = Uri.parse(landingUrl);
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          },
                          child: Text(
                            activeFlavor.dashboardLandingUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              decoration: TextDecoration.underline,
                              color: Colors.blue.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_exitInProgress) ...[
                      const Positioned.fill(
                        child: ModalBarrier(
                          dismissible: false,
                          color: Color(0x1A000000),
                        ),
                      ),
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleExitToResume() async {
    if (_exitInProgress) return;
    setState(() {
      _exitInProgress = true;
    });
    try {
      await widget.onExitToResumePanel.call();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('[dashboard][exit-to-resume-error] $e');
      if (!mounted) return;
      setState(() {
        _exitInProgress = false;
      });
    }
  }

  void _showCliCommandsDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  _cliCommandsText,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ExitIconButton extends StatefulWidget {
  const _ExitIconButton({
    required this.onPressed,
    this.busy = false,
  });

  final Future<void> Function() onPressed;
  final bool busy;

  @override
  State<_ExitIconButton> createState() => _ExitIconButtonState();
}

class _ExitIconButtonState extends State<_ExitIconButton> {
  static const _animDuration = Duration(milliseconds: 70);
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final showPressedShadow = _pressed && !widget.busy;
    return Semantics(
      button: true,
      label: 'Exit to resume panel',
      child: MouseRegion(
        cursor:
            widget.busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (_) {
            if (widget.busy) return;
            setState(() {
              _pressed = true;
            });
          },
          onTapUp: (_) {
            if (widget.busy) return;
            setState(() {
              _pressed = false;
            });
          },
          onTapCancel: () {
            if (widget.busy) return;
            setState(() {
              _pressed = false;
            });
          },
          onTap: widget.busy ? null : widget.onPressed,
          child: AnimatedContainer(
            duration: _animDuration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              boxShadow: showPressedShadow
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(0, 0),
                      ),
                    ]
                  : const [],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  'assets/icons/exit.webp',
                  width: 86.4,
                  height: 86.4,
                  fit: BoxFit.contain,
                ),
                if (widget.busy)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardData {
  final List<int> weekMinutes;
  final String rivalAssetPath;
  final String therapistAssetPath;
  final List<SuccessPoint> successPoints;
  _DashboardData({
    required this.weekMinutes,
    required this.rivalAssetPath,
    required this.therapistAssetPath,
    required this.successPoints,
  });
}

class DashboardDataLoader {
  static Future<List<int>> loadWeekMinutes(
      {int currentSessionMinutes = 0}) async {
    try {
      final Map<String, _SessionSpan> spans = {};
      final storage = LogStorage();
      final lines = await storage.readLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          final tsStr = data['ts'] as String?;
          final session = data['session'] as String? ?? 'unknown';
          if (tsStr == null) continue;
          final ts = DateTime.tryParse(tsStr)?.toUtc();
          if (ts == null) continue;
          final span = spans.putIfAbsent(session, () => _SessionSpan());
          span.update(ts);
        } catch (_) {
          // ignore malformed line
        }
      }

      final Map<DateTime, int> minutesByWeek = {};
      spans.forEach((_, span) {
        if (!span.isValid) return;
        final week = _weekStart(span.end!);
        minutesByWeek[week] = (minutesByWeek[week] ?? 0) + span.durationMinutes;
      });
      if (currentSessionMinutes > 0) {
        final nowWeek = _weekStart(DateTime.now().toUtc());
        minutesByWeek[nowWeek] =
            (minutesByWeek[nowWeek] ?? 0) + currentSessionMinutes;
      }
      return _lastFiveWeeks(minutesByWeek);
    } catch (_) {
      final nowWeek = _weekStart(DateTime.now().toUtc());
      return _lastFiveWeeks({nowWeek: currentSessionMinutes});
    }
  }

  static DateTime _weekStart(DateTime ts) {
    final d = ts.toUtc();
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateTime.utc(monday.year, monday.month, monday.day);
  }

  static List<int> _lastFiveWeeks(Map<DateTime, int> minutesByWeek) {
    final nowWeek = _weekStart(DateTime.now().toUtc());
    final List<int> res = [];
    for (int i = 4; i >= 0; i--) {
      final week = _weekStart(nowWeek.subtract(Duration(days: 7 * i)));
      res.add(minutesByWeek[week] ?? 0);
    }
    return res;
  }
}

class _SessionSpan {
  DateTime? start;
  DateTime? end;

  bool get isValid => start != null && end != null;

  void update(DateTime ts) {
    start = start == null || ts.isBefore(start!) ? ts : start;
    end = end == null || ts.isAfter(end!) ? ts : end;
  }

  int get durationMinutes => max(1, end!.difference(start!).inMinutes);
}

class RivalAssetResolver {
  static const Map<String, int> _emotionCounts = {
    'talking': 15,
    'content': 14,
    'bloating': 12,
    'expecting': 23,
    'dissatisfied': 11,
    'angry': 14,
  };
  static const List<String> _emotionScale = [
    'angry',
    'dissatisfied',
    'expecting',
    'talking',
    'content',
    'bloating',
  ];

  static String pathFor(
      {required int wins,
      required int rivalWins,
      required int viewCount,
      int emotionBoostSteps = 0}) {
    final diff = rivalWins - wins; // Vorsprung des Rivalen
    final baseEmotion = _emotionForDiff(diff);
    final emotion = _boostEmotion(baseEmotion, emotionBoostSteps);
    final count = _emotionCounts[emotion] ?? 1;
    // rotiere bei jedem Dashboard-Open auf die nächste Variante
    final variantIndex = viewCount % count;
    final numStr = (variantIndex + 1).toString().padLeft(2, '0');
    return 'assets/icons/rival_${emotion}_$numStr.webp';
  }

  static String _emotionForDiff(int diff) {
    if (diff >= 5) return 'bloating';
    if (diff >= 3) return 'content';
    if (diff >= 1) return 'talking';
    if (diff <= -5) return 'angry';
    if (diff <= -3) return 'dissatisfied';
    if (diff <= -1) return 'expecting';
    return 'content';
  }

  static String _boostEmotion(String base, int steps) {
    if (steps <= 0) return base;
    final idx = _emotionScale.indexOf(base);
    if (idx == -1) return base;
    final boosted = min(_emotionScale.length - 1, idx + steps);
    return _emotionScale[boosted];
  }
}

class TherapistAssetResolver {
  static String pathFor({required int wins, required int rivalWins}) {
    final diff = wins - rivalWins; // Vorsprung des Spielers
    if (diff > 4) return 'assets/icons/therapist_hilarious.webp';
    if (diff >= 2) return 'assets/icons/therapist_content.webp';
    if (diff >= -1) return 'assets/icons/therapist_neutral.webp';
    if (diff >= -4) return 'assets/icons/therapist_concerned.webp';
    return 'assets/icons/therapist_worried.webp';
  }
}

class SuccessPoint {
  final int trainingDayIndex;
  final String trainingDayUtc;
  final int comprehensionMasteredCumulative;
  final int namingMasteredCumulative;
  SuccessPoint({
    required this.trainingDayIndex,
    required this.trainingDayUtc,
    required this.comprehensionMasteredCumulative,
    required this.namingMasteredCumulative,
  });
}

class _TrainingDayAccumulator {
  _TrainingDayAccumulator({
    required this.dayKeyUtc,
    required this.dayStartUtcMs,
  });

  final String dayKeyUtc;
  final int dayStartUtcMs;
  bool hasTrainingActivity = false;
  final Set<String> comprehensionMastered = <String>{};
  final Set<String> namingMastered = <String>{};
}

class SuccessSeriesLoader {
  static Future<List<SuccessPoint>> load({
    required DateTime? liveSessionStart,
    required Map<String, int> liveComprehensionAttempts,
    required Map<String, int> liveNamingAttempts,
  }) async {
    final Map<String, _TrainingDayAccumulator> byDay = {};
    try {
      final storage = LogStorage();
      final lines = await storage.readLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        Map<String, dynamic> data;
        try {
          data = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final type = data['type'] as String?;
        final tsStr = data['ts'] as String?;
        final ts = tsStr == null ? null : DateTime.tryParse(tsStr)?.toUtc();
        if (ts == null) continue;
        final dayKey = _dayKeyUtc(ts);
        final day = byDay.putIfAbsent(
          dayKey,
          () => _TrainingDayAccumulator(
            dayKeyUtc: dayKey,
            dayStartUtcMs:
                DateTime.utc(ts.year, ts.month, ts.day).millisecondsSinceEpoch,
          ),
        );
        switch (type) {
          case 'trial_result':
          case 'naming_result':
            day.hasTrainingActivity = true;
            break;
          case 'item_mastered':
            final uuid = data['uuid'] as String?;
            if (uuid != null && uuid.trim().isNotEmpty) {
              day.comprehensionMastered.add(uuid.trim());
              day.hasTrainingActivity = true;
            }
            break;
          case 'item_naming_mastered':
            final uuid = data['uuid'] as String?;
            if (uuid != null && uuid.trim().isNotEmpty) {
              day.namingMastered.add(uuid.trim());
              day.hasTrainingActivity = true;
            }
            break;
          default:
            break;
        }
      }
    } catch (_) {
      // ignore log errors
    }

    // Keep current training day visible while session is active.
    final bool liveHasActivity =
        liveComprehensionAttempts.values.any((attempts) => attempts > 0) ||
            liveNamingAttempts.values.any((attempts) => attempts > 0);
    if (liveSessionStart != null && liveHasActivity) {
      final now = DateTime.now().toUtc();
      final dayKey = _dayKeyUtc(now);
      final day = byDay.putIfAbsent(
        dayKey,
        () => _TrainingDayAccumulator(
          dayKeyUtc: dayKey,
          dayStartUtcMs:
              DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch,
        ),
      );
      day.hasTrainingActivity = true;
    }

    final List<_TrainingDayAccumulator> ordered = byDay.values
        .where((d) => d.hasTrainingActivity)
        .toList()
      ..sort((a, b) => a.dayStartUtcMs.compareTo(b.dayStartUtcMs));

    final Set<String> cumulativeComprehensionMastered = <String>{};
    final Set<String> cumulativeNamingMastered = <String>{};
    final List<SuccessPoint> result = [];
    for (int i = 0; i < ordered.length; i++) {
      final day = ordered[i];
      cumulativeComprehensionMastered.addAll(day.comprehensionMastered);
      cumulativeNamingMastered.addAll(day.namingMastered);
      result.add(SuccessPoint(
        trainingDayIndex: i + 1,
        trainingDayUtc: day.dayKeyUtc,
        comprehensionMasteredCumulative: cumulativeComprehensionMastered.length,
        namingMasteredCumulative: cumulativeNamingMastered.length,
      ));
    }

    return result;
  }

  static String _dayKeyUtc(DateTime tsUtc) {
    final y = tsUtc.year.toString().padLeft(4, '0');
    final m = tsUtc.month.toString().padLeft(2, '0');
    final d = tsUtc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class VictoryPanel extends StatelessWidget {
  final int wins;
  final int rivalWins;
  final String rivalAssetPath;
  final String therapistAssetPath;
  final Color? backgroundColor;
  final String tooltipMessage;
  final String youTooltipMessage;
  final String rivalTooltipMessage;
  final bool showPlayerBadge;

  const VictoryPanel({
    super.key,
    required this.wins,
    required this.rivalWins,
    required this.rivalAssetPath,
    required this.therapistAssetPath,
    this.tooltipMessage = '',
    this.youTooltipMessage = '',
    this.rivalTooltipMessage = '',
    this.showPlayerBadge = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final therapistImage = Image.asset(
      therapistAssetPath,
      width: 108,
      height: 108,
      fit: BoxFit.contain,
    );
    final therapistWidget = (!showPlayerBadge && youTooltipMessage.isNotEmpty)
        ? Tooltip(
            message: youTooltipMessage,
            child: therapistImage,
          )
        : IgnorePointer(child: therapistImage);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black87, width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _VictoryPainter(wins: wins, rivalWins: rivalWins),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 24,
            child: therapistWidget,
          ),
          if (showPlayerBadge)
            Positioned(
              bottom: 14,
              left: 124,
              child: Tooltip(
                message: youTooltipMessage,
                child: Image.asset(
                  'assets/icons/player.webp',
                  width: 44,
                  height: 44,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          Positioned(
            bottom: 12,
            right: 24,
            child: Tooltip(
              message: rivalTooltipMessage,
              child: Image.asset(
                rivalAssetPath,
                width: 130,
                height: 130,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: _trophyAlignment(),
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: tooltipMessage.trim().isEmpty
                    ? const _WiggleTrophy()
                    : Tooltip(
                        message: tooltipMessage,
                        child: const _WiggleTrophy(),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Alignment _trophyAlignment() {
    if (wins > rivalWins) return const Alignment(-0.7, -1.0);
    if (rivalWins > wins) return const Alignment(0.7, -1.0);
    return const Alignment(0.0, -1.0);
  }
}

class _VictoryPainter extends CustomPainter {
  final int wins;
  final int rivalWins;
  static const int maxSegments = 20;
  _VictoryPainter({required this.wins, required this.rivalWins});

  @override
  void paint(Canvas canvas, Size size) {
    final double baseY = size.height * 0.85;
    final double chartH = size.height * 0.6;
    final double threshold = chartH * 0.8;
    final int maxVal = max(1, max(wins, rivalWins));
    final double baseSegment = chartH * 0.8 / 10;
    double scale = 1.0;
    double projected = baseSegment * maxVal;
    while (maxVal > 0 && projected * scale > threshold) {
      scale *= 0.5;
    }
    final segmentH = baseSegment * scale;

    final barW = size.width * 0.2;
    final gap = size.width * 0.16;
    final youX = size.width / 2 - gap - barW / 2;
    final rivalX = size.width / 2 + gap - barW / 2;

    final paintYou = Paint()..color = Colors.blue.shade600;
    final paintRival = Paint()..color = Colors.orange.shade600;
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    void drawSegments(int count, double x, Paint fill) {
      final visible = min(count, maxSegments);
      for (int i = 0; i < visible; i++) {
        final top = baseY - segmentH * (i + 1);
        if (top < baseY - threshold) break;
        final rect = Rect.fromLTWH(x, top, barW, segmentH - 1);
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, border);
      }
    }

    drawSegments(wins, youX, paintYou);
    drawSegments(rivalWins, rivalX, paintRival);

    final axis = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;
    canvas.drawLine(Offset(youX, baseY), Offset(rivalX + barW, baseY), axis);
  }

  @override
  bool shouldRepaint(covariant _VictoryPainter oldDelegate) =>
      oldDelegate.wins != wins || oldDelegate.rivalWins != rivalWins;
}

class _WiggleTrophy extends StatefulWidget {
  const _WiggleTrophy();

  @override
  State<_WiggleTrophy> createState() => _WiggleTrophyState();
}

class _WiggleTrophyState extends State<_WiggleTrophy>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = sin(_controller.value * pi * 2) * 0.05;
        return Transform.rotate(
          angle: angle,
          child: child,
        );
      },
      child: const Icon(
        Icons.emoji_events,
        color: Colors.black,
        shadows: [
          Shadow(
            color: Colors.white70,
            blurRadius: 6,
            offset: Offset(0, 0),
          ),
        ],
        size: 48,
      ),
    );
  }
}

class CalendarPanel extends StatelessWidget {
  final List<int> weekMinutes;
  final String tooltipMessage;
  const CalendarPanel({
    super.key,
    required this.weekMinutes,
    required this.tooltipMessage,
  });

  @override
  Widget build(BuildContext context) {
    final data = weekMinutes.isEmpty
        ? List<int>.filled(5, 0)
        : weekMinutes.take(5).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black87, width: 2),
      ),
      child: Stack(
        children: [
          IgnorePointer(
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _CalendarPainter(weekMinutes: data),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Tooltip(
              message: tooltipMessage,
              child: Icon(Icons.calendar_today,
                  color: Colors.blue.shade700, size: 34),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarPainter extends CustomPainter {
  final List<int> weekMinutes;
  _CalendarPainter({required this.weekMinutes});

  @override
  void paint(Canvas canvas, Size size) {
    final baseY = size.height * 0.85;
    final chartH = size.height * 0.65;
    final barW = size.width / (weekMinutes.length * 1.8);
    const maxMinutes = 300;
    final paintBar = Paint()..color = Colors.blue.shade500;
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < weekMinutes.length; i++) {
      final double h =
          (weekMinutes[i].clamp(0, maxMinutes) / maxMinutes) * chartH;
      final double x = (i + 1).toDouble() * (barW * 1.4);
      final rect = Rect.fromLTWH(x, baseY - h, barW, h);
      canvas.drawRect(rect, paintBar);
      canvas.drawRect(rect, border);
    }

    final axis = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;
    canvas.drawLine(
        Offset(barW, baseY), Offset(size.width - barW, baseY), axis);
    canvas.drawLine(
        Offset(barW, baseY), Offset(barW, baseY - chartH - 6), axis);
  }

  @override
  bool shouldRepaint(covariant _CalendarPainter oldDelegate) =>
      oldDelegate.weekMinutes != weekMinutes;
}

class SuccessPanel extends StatelessWidget {
  final List<SuccessPoint> points;
  final String tooltipMessage;

  const SuccessPanel({
    super.key,
    required this.points,
    required this.tooltipMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black87, width: 2),
      ),
      child: Stack(
        children: [
          IgnorePointer(
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _SuccessPainter(
                    points: points,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            child: Tooltip(
              message: tooltipMessage,
              child: Icon(Icons.trending_up,
                  color: Colors.amber.shade700, size: 36),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessPainter extends CustomPainter {
  final List<SuccessPoint> points;
  _SuccessPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final left = size.width * 0.08;
    final bottom = size.height * 0.82;
    final right = size.width * 0.92;
    final top = size.height * 0.2;
    final chartW = right - left;
    final chartH = bottom - top;

    final int maxTrainingDay =
        points.isEmpty ? 0 : points.map((p) => p.trainingDayIndex).fold(0, max);

    final int maxItems = points.isEmpty
        ? 0
        : points
            .map((p) => max(
                  p.comprehensionMasteredCumulative,
                  p.namingMasteredCumulative,
                ))
            .fold(0, max);
    // Auto-scale y-axis to 125% of the current maximum cumulative value.
    final int yMax = max(1, (maxItems * 1.25).ceil());
    const double xTargetRatio = 0.75;
    final double effectiveXMax =
        maxTrainingDay <= 0 ? 1.0 : maxTrainingDay / xTargetRatio;

    final axis = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), axis);
    canvas.drawLine(Offset(left, bottom), Offset(left, top), axis);

    final guide = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final guideY = bottom - chartH * 0.8;
    canvas.drawLine(Offset(left, guideY), Offset(right, guideY), guide);
    void drawYAxisLabel({
      required String text,
      required double y,
      Color color = Colors.black87,
      double dx = 6,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - dx, y - tp.height / 2));
    }

    void drawIconCountLabel({
      required IconData icon,
      required int count,
      required double y,
      required Color color,
      double dx = 10,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
                fontSize: 20,
                color: color,
              ),
            ),
            TextSpan(
              text: ' $count',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - dx, y - tp.height / 2));
    }

    drawYAxisLabel(text: '0', y: bottom);
    drawYAxisLabel(text: '$yMax', y: top);
    if (maxTrainingDay > 0) {
      final startLabel = TextPainter(
        text: const TextSpan(
          text: 'T1',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      startLabel.paint(canvas, Offset(left, bottom + 2));
      final endLabel = TextPainter(
        text: TextSpan(
          text: 'T$maxTrainingDay',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      endLabel.paint(
        canvas,
        Offset(
          (left +
                  chartW * (maxTrainingDay / effectiveXMax) -
                  endLabel.width / 2)
              .clamp(left, right - endLabel.width),
          bottom + 2,
        ),
      );
    }

    void drawSeries(List<Offset> pts, Color color, {bool dashed = false}) {
      if (pts.length < 2) {
        if (pts.isNotEmpty) {
          canvas.drawCircle(pts.first, 3, Paint()..color = color);
        }
        return;
      }
      if (dashed) {
        _drawDashed(canvas, pts, color);
      } else {
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (int i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        final stroke = Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawPath(path, stroke);
      }
      canvas.drawCircle(pts.last, 4, Paint()..color = Colors.black);
      canvas.drawCircle(pts.last, 3, Paint()..color = color);
    }

    List<Offset> seriesFrom(List<int> values) {
      final List<Offset> pts = [];
      for (int i = 0; i < values.length; i++) {
        final p = points[i];
        final x = left + chartW * (p.trainingDayIndex / effectiveXMax);
        final y = bottom - chartH * (values[i] / yMax);
        pts.add(Offset(x, y));
      }
      return pts;
    }

    final compUp =
        points.map((p) => p.comprehensionMasteredCumulative).toList();
    final namingUp = points.map((p) => p.namingMasteredCumulative).toList();

    drawSeries(seriesFrom(compUp), Colors.blue.shade700);
    drawSeries(seriesFrom(namingUp), Colors.green.shade700);
    final int compCurrent = compUp.isNotEmpty ? compUp.last : 0;
    final int namingCurrent = namingUp.isNotEmpty ? namingUp.last : 0;
    double compY = bottom - chartH * (compCurrent / yMax);
    double namingY = bottom - chartH * (namingCurrent / yMax);
    if ((compY - namingY).abs() < 12) {
      compY -= 8;
      namingY += 8;
    }
    drawIconCountLabel(
      icon: Icons.hearing,
      count: compCurrent,
      y: compY.clamp(top, bottom),
      color: Colors.blue.shade700,
      dx: 10,
    );
    drawIconCountLabel(
      icon: Icons.record_voice_over,
      count: namingCurrent,
      y: namingY.clamp(top, bottom),
      color: Colors.green.shade700,
      dx: 10,
    );
  }

  @override
  bool shouldRepaint(covariant _SuccessPainter oldDelegate) =>
      oldDelegate.points != points;

  void _drawDashed(Canvas canvas, List<Offset> pts, Color color) {
    const double dash = 8;
    const double gap = 6;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < pts.length - 1; i++) {
      final start = pts[i];
      final end = pts[i + 1];
      final vec = end - start;
      final len = vec.distance;
      final dir = vec / len;
      double covered = 0;
      while (covered < len) {
        final dashStart = start + dir * covered;
        final dashEnd = start + dir * min(covered + dash, len);
        canvas.drawLine(dashStart, dashEnd, paint);
        covered += dash + gap;
      }
    }
  }
}

// Intentionally no hard `exit(0)`: iOS/macOS/web will ignore it.
// Dashboard exit is delegated to the host (RobuLingoApp) via `onExitToResumePanel`.
