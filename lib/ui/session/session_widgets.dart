// ------------------------------------------------------------
// Ziel (Laien): Zentrale Session-Widgets für 2AFC + Benennen + Splash/Dashboard-Trigger bündeln.
// Verbindung: Wird direkt von robulingo_app.dart verwendet; nutzt HexagonTrack, Dashboard, Mic-UI.
// Tücken: Erwartet Status/Callbacks aus dem App-State (Trials, Naming-Flow, Wins); kein eigener State.
// ------------------------------------------------------------
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:robulingo_flutter/data/hint_models.dart';
import 'package:robulingo_flutter/constants.dart';
import 'package:robulingo_flutter/flavor_config.dart';
import 'package:robulingo_flutter/logic/hexagon_controller.dart';
import 'package:robulingo_flutter/ui/dashboard/dashboard_screen.dart';
import 'package:robulingo_flutter/ui/dashboard_button.dart';
import 'package:robulingo_flutter/ui/hexagon_track.dart';
import 'package:robulingo_flutter/ui/supervisor_resume_panel.dart';
import 'package:robulingo_flutter/ui/training_calendar_panel.dart';
import 'package:url_launcher/url_launcher.dart';

const Map<String, Map<String, String>> _resumeTooltipTexts = {
  'choose_target_language': {
    'en': 'Choose target language',
    'de': 'Zielsprache wählen',
    'ar': 'اختر اللغة المستهدفة',
    'fr': 'Choisir la langue cible',
    'es': 'Elegir idioma objetivo',
    'it': 'Scegli la lingua obiettivo',
    'ru': 'Выбрать целевой язык',
    'hi': 'लक्ष्य भाषा चुनें',
    'el': 'Επιλέξτε γλώσσα-στόχο',
    'zh': '选择目标语言',
    'tr': 'Hedef dili seçin',
    'ja': '目標言語を選択',
  },
  'default_learning': {
    'en': 'Default learning',
    'de': 'Standardlernen',
    'ar': 'التعلم الافتراضي',
    'fr': 'Apprentissage standard',
    'es': 'Aprendizaje predeterminado',
    'it': 'Apprendimento predefinito',
    'ru': 'Обычное обучение',
    'hi': 'मानक सीखना',
    'el': 'Βασική εκμάθηση',
    'zh': '默认学习',
    'tr': 'Varsayılan öğrenme',
    'ja': '標準学習',
  },
  'deeper_learning': {
    'en': 'Deeper learning',
    'de': 'Vertieftes Lernen',
    'ar': 'تعلم أعمق',
    'fr': 'Apprentissage approfondi',
    'es': 'Aprendizaje profundo',
    'it': 'Apprendimento approfondito',
    'ru': 'Углубленное обучение',
    'hi': 'गहन सीखना',
    'el': 'Πιο βαθιά εκμάθηση',
    'zh': '深度学习',
    'tr': 'Derin öğrenme',
    'ja': 'より深い学習',
  },
  'change_module': {
    'en': 'Change module',
    'de': 'Modul wechseln',
    'ar': 'تغيير الوحدة',
    'fr': 'Changer de module',
    'es': 'Cambiar módulo',
    'it': 'Cambia modulo',
    'ru': 'Сменить модуль',
    'hi': 'मॉड्यूल बदलें',
    'el': 'Αλλαγή ενότητας',
    'zh': '更换模块',
    'tr': 'Modülü değiştir',
    'ja': 'モジュールを変更',
  },
  'start_learning': {
    'en': 'Start learning',
    'de': 'Lernen starten',
    'ar': 'ابدأ التعلم',
    'fr': 'Commencer à apprendre',
    'es': 'Empezar a aprender',
    'it': 'Inizia a imparare',
    'ru': 'Начать обучение',
    'hi': 'सीखना शुरू करें',
    'el': 'Έναρξη εκμάθησης',
    'zh': '开始学习',
    'tr': 'Öğrenmeye başla',
    'ja': '学習を開始',
  },
  'curriculum_covered': {
    'en': 'Curriculum covered',
    'de': 'Abgedeckter Lehrplan',
    'ar': 'المنهج المغطى',
    'fr': 'Programme couvert',
    'es': 'Currículo cubierto',
    'it': 'Curriculum coperto',
    'ru': 'Охват программы',
    'hi': 'पाठ्यक्रम प्रगति',
    'el': 'Καλυμμένο πρόγραμμα',
    'zh': '已覆盖课程',
    'tr': 'Kapsanan müfredat',
    'ja': 'カリキュラムの進捗',
  },
  'supervisor_info': {
    'en': 'Supervisor & progress info',
    'de': 'Supervisor- und Fortschrittsinfos',
  },
  'dailywords_home': {
    'en': 'DailyWords project',
    'de': 'DailyWords-Projekt',
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

const Map<String, Map<String, String>> _sessionMenuTooltipTexts = {
  'session_menu': {
    'en': 'Session menu',
    'de': 'Sitzungsmenü',
  },
  'open_dashboard': {
    'en': 'Open player dashboard',
    'de': 'Spieler-Dashboard öffnen',
  },
  'exit_to_resume_panel': {
    'en': 'Exit to resume panel',
    'de': 'Zum Resume-Panel',
  },
};

String _normalizedLangCode(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split(RegExp(r'[-_]'));
  return parts.isNotEmpty ? parts.first : trimmed;
}

String _tooltipLanguageCode({required String? l1, required String? l2}) {
  final l1Code = _normalizedLangCode(l1);
  if (l1Code.isNotEmpty) return l1Code;
  final l2Code = _normalizedLangCode(l2);
  if (l2Code.isNotEmpty) return l2Code;
  return 'en';
}

String _resumeTooltipText(String key, String langCode) {
  final values = _resumeTooltipTexts[key];
  if (values == null) return key;
  return values[langCode] ?? values['en'] ?? key;
}

String _sessionMenuTooltipText(String key, String langCode) {
  final values = _sessionMenuTooltipTexts[key];
  if (values == null) return key;
  return values[langCode] ?? values['en'] ?? key;
}

const String _startArrowDefaultAsset = 'assets/icons/start_arrow.webp';
const String _startArrowGreenAsset = 'assets/icons/start_arrow_green.webp';
const String _startArrowBlueAsset = 'assets/icons/start_arrow_blue.webp';
const String _startArrowYellowAsset = 'assets/icons/start_arrow_yellow.webp';
const String _startArrowRedAsset = 'assets/icons/start_arrow_red.webp';

String _startArrowAssetForLastTraining(List<DateTime>? datesUtc) {
  if (datesUtc == null || datesUtc.isEmpty) return _startArrowDefaultAsset;
  DateTime? lastTrainingUtc;
  for (final date in datesUtc) {
    final utc = date.toUtc();
    if (lastTrainingUtc == null || utc.isAfter(lastTrainingUtc)) {
      lastTrainingUtc = utc;
    }
  }
  if (lastTrainingUtc == null) return _startArrowDefaultAsset;
  var elapsed = DateTime.now().toUtc().difference(lastTrainingUtc);
  if (elapsed.isNegative) {
    elapsed = Duration.zero;
  }
  if (elapsed < const Duration(hours: 36)) return _startArrowGreenAsset;
  if (elapsed < const Duration(hours: 72)) return _startArrowBlueAsset;
  if (elapsed < const Duration(hours: 96)) return _startArrowDefaultAsset;
  if (elapsed < const Duration(hours: 120)) return _startArrowYellowAsset;
  return _startArrowRedAsset;
}

class RestartModuleProgress {
  const RestartModuleProgress({
    required this.iconAsset,
    required this.completed,
    required this.total,
  });

  final String iconAsset;
  final int completed;
  final int total;

  RestartModuleProgress copyWith({
    String? iconAsset,
    int? completed,
    int? total,
  }) {
    return RestartModuleProgress(
      iconAsset: iconAsset ?? this.iconAsset,
      completed: completed ?? this.completed,
      total: total ?? this.total,
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
    required this.onSelectModule,
    required this.onOpenHistory,
    required this.selectedTrainingDepth,
    required this.onSelectTrainingDepth,
    required this.moduleProgress,
    required this.historyHasSupervisorInfo,
    required this.userId,
    required this.workerHost,
    required this.apiPrefix,
    required this.targetLanguage,
    required this.nativeLanguage,
    this.fallbackDatesUtc,
    this.onResumeEmojiChanged,
    this.onResumeFeedbackIdsChanged,
  });

  final int wins;
  final int rivalWins;
  final int viewCount;
  final VoidCallback onRestart;
  final VoidCallback onStart;
  final VoidCallback onSelectModule;
  final VoidCallback onOpenHistory;
  final TrainingDepthMode selectedTrainingDepth;
  final ValueChanged<TrainingDepthMode> onSelectTrainingDepth;
  final RestartModuleProgress moduleProgress;
  final bool historyHasSupervisorInfo;
  final String? userId;
  final String workerHost;
  final String apiPrefix;
  final String targetLanguage;
  final String? nativeLanguage;
  final List<DateTime>? fallbackDatesUtc;
  final ValueChanged<String?>? onResumeEmojiChanged;
  final ValueChanged<List<String>>? onResumeFeedbackIdsChanged;

  @override
  State<RestartSplash> createState() => _RestartSplashState();
}

class _RestartSplashState extends State<RestartSplash> {
  bool _resumeFeedbackVisible = false;

  void _handleResumeFeedbackVisibilityChanged(bool visible) {
    if (_resumeFeedbackVisible == visible) return;
    setState(() {
      _resumeFeedbackVisible = visible;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tooltipLanguage = _tooltipLanguageCode(
      l1: widget.nativeLanguage,
      l2: widget.targetLanguage,
    );
    final tooltipChooseTargetLanguage =
        _resumeTooltipText('choose_target_language', tooltipLanguage);
    final tooltipDefaultLearning =
        _resumeTooltipText('default_learning', tooltipLanguage);
    final tooltipDeeperLearning =
        _resumeTooltipText('deeper_learning', tooltipLanguage);
    final tooltipChangeModule =
        _resumeTooltipText('change_module', tooltipLanguage);
    final tooltipStartLearning =
        _resumeTooltipText('start_learning', tooltipLanguage);
    final tooltipCurriculumCovered =
        _resumeTooltipText('curriculum_covered', tooltipLanguage);
    final tooltipSupervisorInfo =
        _resumeTooltipText('supervisor_info', tooltipLanguage);
    final tooltipDailyWordsHome =
        _resumeTooltipText('dailywords_home', tooltipLanguage);
    final tooltipYou = _resumeTooltipText('you', tooltipLanguage);
    final tooltipYourRival = _resumeTooltipText('your_rival', tooltipLanguage);
    final historyIconAsset = widget.historyHasSupervisorInfo
        ? 'assets/icons/eye_red.webp'
        : 'assets/icons/eye.webp';
    final startArrowAsset =
        _startArrowAssetForLastTraining(widget.fallbackDatesUtc);

    Widget buildCalendarSection() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wideLayout = constraints.maxWidth >= 780;
            final panelWidth = wideLayout
                ? (constraints.maxWidth * 0.24).clamp(160.0, 260.0).toDouble()
                : (constraints.maxWidth * 0.9).clamp(180.0, 320.0).toDouble();
            final calendar = TrainingCalendarPanel(
              userId: widget.userId,
              workerHost: widget.workerHost,
              apiPrefix: widget.apiPrefix,
              targetLanguage: widget.targetLanguage,
              nativeLanguage: widget.nativeLanguage,
              thresholdMinutes: 1,
              thresholdRuns: 10,
              fallbackDatesUtc: widget.fallbackDatesUtc,
            );
            final supervisorPanel = SupervisorResumePanel(
              userId: widget.userId,
              workerHost: widget.workerHost,
              apiPrefix: widget.apiPrefix,
              refreshInterval: const Duration(seconds: 15),
              onVisibilityChanged: _handleResumeFeedbackVisibilityChanged,
              onSelectedEmojiChanged: widget.onResumeEmojiChanged,
              onSelectedFeedbackIdsChanged: widget.onResumeFeedbackIdsChanged,
            );
            if (wideLayout) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: calendar),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: panelWidth,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: supervisorPanel,
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: calendar),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(top: _resumeFeedbackVisible ? 8 : 0),
                  child: Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: panelWidth,
                      child: supervisorPanel,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    Widget buildFooter() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool compact = constraints.maxWidth < 420;

            Widget trainingDepthButton({
              required String asset,
              required TrainingDepthMode mode,
              required double size,
              required String tooltipMessage,
              VoidCallback? onTap,
            }) {
              final bool selected = widget.selectedTrainingDepth == mode;
              return Tooltip(
                message: tooltipMessage,
                child: GestureDetector(
                  onTap: onTap ?? () => widget.onSelectTrainingDepth(mode),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0x223286E6)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            selected ? const Color(0xFF3286E6) : Colors.black12,
                        width: selected ? 1.6 : 1.0,
                      ),
                    ),
                    child: Image.asset(
                      asset,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              );
            }

            Future<void> openDailyWordsProject() async {
              final normalized = _normalizedLangCode(tooltipLanguage);
              final supported = <String>{
                'en',
                'de',
                'fr',
                'es',
                'it',
                'ru',
                'ar',
                'tr',
                'el',
                'hi',
                'ja',
                'zh',
              };
              final uri = (normalized.isNotEmpty &&
                      normalized != 'en' &&
                      supported.contains(normalized))
                  ? Uri.https('www.dailywords-project.org', '/', {
                      'lang': normalized,
                    })
                  : Uri.parse('https://www.dailywords-project.org/');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }

            Future<void> openResumeMenu({required bool compact}) async {
              final double iconSize = compact ? 52 : 56;
              final double moduleIconSize = compact ? 48 : 54;
              final double menuIconSize = compact ? 34 : 38;
              final double depthSize = compact ? 44 : 48;
              await showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (sheetContext) {
                  return SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Tooltip(
                                    message: tooltipChooseTargetLanguage,
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.of(sheetContext).pop();
                                        widget.onRestart();
                                      },
                                      child: Image.asset(
                                        'assets/icons/toolbox.webp',
                                        width: iconSize,
                                        height: iconSize,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.center,
                                  child: trainingDepthButton(
                                    asset: 'assets/icons/default.webp',
                                    mode: TrainingDepthMode.defaultMode,
                                    size: depthSize,
                                    tooltipMessage: tooltipDefaultLearning,
                                    onTap: () {
                                      Navigator.of(sheetContext).pop();
                                      widget.onSelectTrainingDepth(
                                          TrainingDepthMode.defaultMode);
                                    },
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Tooltip(
                                    message: tooltipChangeModule,
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.of(sheetContext).pop();
                                        widget.onSelectModule();
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: SizedBox(
                                        width: moduleIconSize + 6,
                                        height: moduleIconSize + 6,
                                        child: Image.asset(
                                          widget.moduleProgress.iconAsset,
                                          width: moduleIconSize,
                                          height: moduleIconSize,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Tooltip(
                                    message: tooltipSupervisorInfo,
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.of(sheetContext).pop();
                                        widget.onOpenHistory();
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: SizedBox(
                                        width: menuIconSize,
                                        height: menuIconSize,
                                        child: Image.asset(
                                          historyIconAsset,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.center,
                                  child: trainingDepthButton(
                                    asset: 'assets/icons/deep.webp',
                                    mode: TrainingDepthMode.deep,
                                    size: depthSize,
                                    tooltipMessage: tooltipDeeperLearning,
                                    onTap: () {
                                      Navigator.of(sheetContext).pop();
                                      widget.onSelectTrainingDepth(
                                          TrainingDepthMode.deep);
                                    },
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Tooltip(
                                    message: tooltipDailyWordsHome,
                                    child: GestureDetector(
                                      onTap: () async {
                                        Navigator.of(sheetContext).pop();
                                        await openDailyWordsProject();
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: SizedBox(
                                        width: menuIconSize,
                                        height: menuIconSize,
                                        child: Image.asset(
                                          'assets/icons/home.webp',
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }

            Widget burgerButton({required double size}) {
              return GestureDetector(
                onTap: () => openResumeMenu(compact: compact),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12, width: 1.2),
                  ),
                  child: Icon(
                    Icons.menu,
                    size: size * 0.58,
                    color: Colors.black87,
                  ),
                ),
              );
            }

            if (!compact) {
              return SizedBox(
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        burgerButton(size: 72),
                        Tooltip(
                          message: tooltipStartLearning,
                          child: GestureDetector(
                            onTap: widget.onStart,
                            child: Image.asset(startArrowAsset,
                                width: 88, height: 88),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 138,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Tooltip(
                            message: tooltipCurriculumCovered,
                            child: _RestartModuleProgressIndicator(
                                widget.moduleProgress),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: openDailyWordsProject,
                            child: Text(
                              'dailywords-project.org',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
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

            return SizedBox(
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      burgerButton(size: 64),
                      Tooltip(
                        message: tooltipStartLearning,
                        child: GestureDetector(
                          onTap: widget.onStart,
                          child: Image.asset(startArrowAsset,
                              width: 78, height: 78),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 122,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Tooltip(
                          message: tooltipCurriculumCovered,
                          child: _RestartModuleProgressIndicator(
                              widget.moduleProgress),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: openDailyWordsProject,
                          child: Text(
                            'dailywords-project.org',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1.0);
            final compactLayout = constraints.maxHeight < 860 ||
                constraints.maxWidth < 980 ||
                textScale > 1.15;
            final topSpacing = compactLayout ? 16.0 : 32.0;
            final logoHeight = compactLayout ? 100.0 : 120.0;
            final victoryHeight = compactLayout ? 170.0 : 200.0;
            final compactCalendarHeight =
                (constraints.maxHeight * 0.4).clamp(180.0, 280.0).toDouble();
            final compactCalendarSectionHeight =
                compactCalendarHeight + (_resumeFeedbackVisible ? 100.0 : 0.0);

            final headSection = Column(
              children: [
                SizedBox(height: topSpacing),
                Image.asset(activeFlavor.brandLogoAsset,
                    height: logoHeight, fit: BoxFit.contain),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    height: victoryHeight,
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
                      youTooltipMessage: tooltipYou,
                      rivalTooltipMessage: tooltipYourRival,
                      showPlayerBadge: false,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
              ],
            );

            if (!compactLayout) {
              return Column(
                children: [
                  headSection,
                  const SizedBox(height: 12),
                  Expanded(child: buildCalendarSection()),
                  buildFooter(),
                ],
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    headSection,
                    const SizedBox(height: 10),
                    SizedBox(
                      height: compactCalendarSectionHeight,
                      child: buildCalendarSection(),
                    ),
                    buildFooter(),
                  ],
                ),
              ),
            );
          },
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
    final double progressRatio =
        (progress.total > 0 ? (progress.completed / progress.total) : 0.0)
            .clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBar(
          context,
          ratio: progressRatio,
          color: Theme.of(context).colorScheme.primary,
        ),
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
    required this.showTinySpinner,
    required this.liveTranscript,
    required this.onStartNaming,
    required this.onOpenSettings,
    required this.onContinueWithoutMic,
    required this.onSkip,
    this.onEscapeToOpeningPanel,
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
  final bool showTinySpinner;
  final String liveTranscript;
  final VoidCallback onStartNaming;
  final VoidCallback onOpenSettings;
  final void Function(String reason) onContinueWithoutMic;
  final void Function(String reason) onSkip;
  final VoidCallback? onEscapeToOpeningPanel;

  @override
  Widget build(BuildContext context) {
    const bool isWeb = kIsWeb;
    final double gapHourglass = isWeb ? 1 : 4;
    final double cardMargin = isWeb ? 2 : 6;
    final double cardPadding = isWeb ? 6 : 10;
    final bool isCorrect = namingOutcome == true;
    final Color borderColor = namingOutcome == null
        ? Colors.grey.shade400
        : (isCorrect ? Colors.green : Colors.red);
    final Color? cardFill = namingOutcome == null
        ? null
        : (isCorrect ? Colors.green.shade200 : Colors.red.shade200);
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
        padding: const EdgeInsets.symmetric(horizontal: 3),
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
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: EdgeInsets.all(cardMargin),
          padding: EdgeInsets.all(cardPadding),
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
                      (maxWidth - 12).clamp(0.0, maxWidth).toDouble();
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
              if (showTinySpinner)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
        if (showHourglass && !isWeb)
          Padding(
            padding: EdgeInsets.only(top: gapHourglass),
            child: Icon(Icons.hourglass_top,
                size: 18, color: Colors.grey.shade700),
          ),
        if (liveTranscript.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(
                liveTranscript,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (namingStatus.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2C98A)),
              ),
              child: Text(
                namingStatus,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6A4A00),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (namingOutcome == null && !namingInProgress)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: namingInProgress ? null : onStartNaming,
                  icon: const Icon(Icons.mic, size: 16),
                  label: Text(!micPrimed ? 'Start naming' : 'Retry mic'),
                ),
                OutlinedButton.icon(
                  onPressed: namingInProgress ? null : onOpenSettings,
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Settings'),
                ),
                TextButton(
                  onPressed: namingInProgress
                      ? null
                      : () => onContinueWithoutMic('manual_button'),
                  child: const Text('Without mic'),
                ),
              ],
            ),
          ),
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
    this.onEscapeToOpeningPanel,
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
  final VoidCallback? onEscapeToOpeningPanel;

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
    required this.runsDone,
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
    required this.micOn,
    required this.showTinySpinner,
    required this.liveTranscript,
    required this.targetText,
    required this.targetPhonetic,
    required this.phoneticButtonVisible,
    required this.phoneticOverrideActive,
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
    required this.mountainTheme,
    required this.mountainYouWon,
    required this.mountainRivalWon,
    required this.onPrimeMic,
    required this.onOpenMicSettings,
    required this.onContinueWithoutMic,
    required this.onSkipNaming,
    required this.onSelect,
    required this.onOpenDashboard,
    required this.tooltipLanguageCode,
    this.onEscapeToOpeningPanel,
    this.onExitToResumePanel,
  });

  final HexagonState ladder;
  final int runsDone;
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
  final bool micOn;
  final bool showTinySpinner;
  final String liveTranscript;
  final String targetText;
  final String? targetPhonetic;
  final bool phoneticButtonVisible;
  final bool phoneticOverrideActive;
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
  final String mountainTheme;
  final bool mountainYouWon;
  final bool mountainRivalWon;
  final VoidCallback onPrimeMic;
  final VoidCallback onOpenMicSettings;
  final void Function(String reason) onContinueWithoutMic;
  final void Function(String reason) onSkipNaming;
  final void Function(bool choseLeft) onSelect;
  final VoidCallback onOpenDashboard;
  final String tooltipLanguageCode;
  final VoidCallback? onEscapeToOpeningPanel;
  final Future<void> Function()? onExitToResumePanel;

  @override
  Widget build(BuildContext context) {
    const bool isWeb = kIsWeb;
    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final bool compactNamingLayout = isNaming;
    final double panelGap = compactNamingLayout
        ? (isWeb ? 1 : 4)
        : (isWeb ? 4 : 12);
    final double infoPanelVerticalPadding = compactNamingLayout
        ? (isWeb ? 5 : 8)
        : (isWeb ? 8 : 14);
    final double trackTopPadding = compactNamingLayout
        ? (isWeb ? 0 : 4)
        : (isWeb ? 2 : 8);
    final double bottomBarHeight = namingInProgress ? 48.0 : 0.0;
    final double verticalInsets =
        MediaQuery.of(context).padding.vertical + 32 + bottomBarHeight;
    final double availableHeight = size.height - verticalInsets;

    final bool shrinkHexaWeb = kIsWeb && isNaming;
    final double namingHexaScale = shrinkHexaWeb ? 0.7 : 1.0;
    final baseTrackWidget = Padding(
      padding: EdgeInsets.only(top: trackTopPadding),
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
        runsDone: runsDone,
        tooltipLanguageCode: tooltipLanguageCode,
        uiScale: namingHexaScale,
        centerGrid: shrinkHexaWeb,
        mountainTheme: mountainTheme,
        mountainYouWon: mountainYouWon,
        mountainRivalWon: mountainRivalWon,
      ),
    );
    final Widget trackWidget = shrinkHexaWeb
        ? LayoutBuilder(
            builder: (context, constraints) {
              final double maxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : size.width;
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: maxWidth * 0.7,
                  child: baseTrackWidget,
                ),
              );
            },
          )
        : baseTrackWidget;
    final Widget displayTrackWidget = isNaming
        ? SizedBox(
            height: imageHeight * 0.95,
            child: Align(
              alignment: Alignment.topCenter,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: trackWidget,
              ),
            ),
          )
        : trackWidget;

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
            showTinySpinner: showTinySpinner,
            liveTranscript: liveTranscript,
            onStartNaming: onPrimeMic,
            onOpenSettings: onOpenMicSettings,
            onContinueWithoutMic: onContinueWithoutMic,
            onSkip: onSkipNaming,
            onEscapeToOpeningPanel: onEscapeToOpeningPanel,
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
            onEscapeToOpeningPanel: onEscapeToOpeningPanel,
          );

    final contentColumn = Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLandscape)
          SizedBox(height: compactNamingLayout ? 0 : (isWeb ? 2 : 4)),
        trialWidget,
        //const SizedBox(height: 32),
        Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 16, vertical: infoPanelVerticalPadding),
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
                        (targetPhonetic != null &&
                            targetPhonetic!.trim().isNotEmpty))
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text.rich(
                            TextSpan(
                              text: targetText,
                              children: [
                                if (targetPhonetic != null &&
                                    targetPhonetic!.isNotEmpty)
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
                        ],
                      ),
                    if (showNative &&
                        nativeText != null &&
                        nativeText!.isNotEmpty) ...[
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
                        hintButtonVisible) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
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
                                  const AssetImage(
                                      'assets/icons/phonetic.webp'),
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
                                  const AssetImage(
                                      'assets/icons/Magnifying_glass.webp'),
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
                      _HintPanel(
                          key: hintPanelKey,
                          label: hintLabel,
                          hints: hintEntries),
                    ] else if (hintMissingText != null &&
                        hintMissingText!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        hintMissingText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black45),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (panelGap > 0) SizedBox(height: panelGap),
        Column(
          children: [
            DashboardButtonRow(
              show: showDashboardButton || ladder.hasFlagAppeared,
              showHourglass: showGlobalHourglass,
              hourglassWiggle: showGlobalHourglass && (!isNaming || micOn),
              onTap: onOpenDashboard,
            ),
          ],
        ),
      ],
    );

    final Widget content = contentColumn;

    Widget layout;
    if (!isLandscape) {
      layout = SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            displayTrackWidget,
            content,
          ],
        ),
      );
    } else {
      if (shrinkHexaWeb) {
        layout = Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            displayTrackWidget,
            if (isWeb) const SizedBox(height: 2),
            content,
          ],
        );
      } else {
        final double trialHeight = imageHeight + 24;
        final double maxTrackHeight =
            (availableHeight - trialHeight - 12).clamp(0.0, availableHeight) *
                0.85;
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
        layout = Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              isNaming ? displayTrackWidget : landscapeTrackWidget,
              content,
            ],
          );
      }
    }

    final menuTooltip =
        _sessionMenuTooltipText('session_menu', tooltipLanguageCode);
    final dashboardTooltip =
        _sessionMenuTooltipText('open_dashboard', tooltipLanguageCode);
    final exitTooltip =
        _sessionMenuTooltipText('exit_to_resume_panel', tooltipLanguageCode);

    return Stack(
      children: [
        layout,
        Positioned(
          left: 8,
          bottom: 8,
          child: _SessionMenuButton(
            menuTooltip: menuTooltip,
            openDashboardTooltip: dashboardTooltip,
            exitToResumeTooltip: exitTooltip,
            onOpenDashboard: onOpenDashboard,
            onExitToResumePanel: onExitToResumePanel,
          ),
        ),
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
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black87),
                      ),
                    if (hint.examples.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Examples: ${hint.examples.join(', ')}',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black54),
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

class _SessionMenuButton extends StatefulWidget {
  const _SessionMenuButton({
    required this.menuTooltip,
    required this.openDashboardTooltip,
    required this.exitToResumeTooltip,
    required this.onOpenDashboard,
    this.onExitToResumePanel,
  });

  final String menuTooltip;
  final String openDashboardTooltip;
  final String exitToResumeTooltip;
  final VoidCallback onOpenDashboard;
  final Future<void> Function()? onExitToResumePanel;

  @override
  State<_SessionMenuButton> createState() => _SessionMenuButtonState();
}

class _SessionMenuButtonState extends State<_SessionMenuButton> {
  bool _busy = false;

  bool get _hasActions => true;

  void _showSnack(String message) {
    if (!mounted || message.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runAction(Future<void> Function() action,
      {required String label}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } catch (e) {
      debugPrint('[session-menu][$label][error] $e');
      _showSnack('$label failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openMenu() async {
    if (!_hasActions || _busy) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final List<Widget> entries = [];

        entries.add(
          _SessionMenuEntry(
            tooltip: widget.openDashboardTooltip,
            leading: Image.asset(
              'assets/icons/progress.webp',
              width: 26,
              height: 26,
              fit: BoxFit.contain,
            ),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await _runAction(
                () async => widget.onOpenDashboard(),
                label: 'Open dashboard',
              );
            },
          ),
        );

        if (widget.onExitToResumePanel != null) {
          entries.add(
            _SessionMenuEntry(
              tooltip: widget.exitToResumeTooltip,
              leading: Image.asset(
                'assets/icons/exit.webp',
                width: 26,
                height: 26,
                fit: BoxFit.contain,
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _runAction(
                  () => widget.onExitToResumePanel!.call(),
                  label: 'Exit to resume panel',
                );
              },
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: entries,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.menuTooltip,
      child: Semantics(
        button: true,
        label: widget.menuTooltip,
        child: GestureDetector(
          onTap: _hasActions && !_busy ? _openMenu : null,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.menu,
                    size: 18,
                    color: Colors.black87,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SessionMenuEntry extends StatelessWidget {
  const _SessionMenuEntry({
    required this.tooltip,
    required this.leading,
    required this.onTap,
  });

  final String tooltip;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(child: leading),
          ),
        ),
      ),
    );
  }
}
