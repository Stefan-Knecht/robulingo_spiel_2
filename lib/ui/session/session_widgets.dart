// ------------------------------------------------------------
// Ziel (Laien): Zentrale Session-Widgets für 2AFC + Benennen + Splash/Dashboard-Trigger bündeln.
// Verbindung: Wird direkt von robulingo_app.dart verwendet; nutzt HexagonTrack, Dashboard, Mic-UI.
// Tücken: Erwartet Status/Callbacks aus dem App-State (Trials, Naming-Flow, Wins); kein eigener State.
// ------------------------------------------------------------
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:robulingo_flutter/data/hint_models.dart';
import 'package:robulingo_flutter/constants.dart';
import 'package:robulingo_flutter/flavor_config.dart';
import 'package:robulingo_flutter/logic/competition_asset_resolver.dart';
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
  'return_to_module_selection': {
    'en': 'Return to module selection',
    'de': 'Zur Modulauswahl',
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
    required this.onStart,
    required this.onSelectModule,
    required this.selectedTrainingDepth,
    required this.onSelectTrainingDepth,
    required this.moduleProgress,
    required this.userId,
    required this.workerHost,
    required this.apiPrefix,
    required this.targetLanguage,
    required this.nativeLanguage,
    this.fallbackDatesUtc,
    this.onTargetLanguageChange,
    this.onNativeLanguageChange,
    this.onResumeEmojiChanged,
    this.onResumeFeedbackIdsChanged,
  });

  final int wins;
  final int rivalWins;
  final int viewCount;
  final VoidCallback onStart;
  final VoidCallback onSelectModule;
  final TrainingDepthMode selectedTrainingDepth;
  final ValueChanged<TrainingDepthMode> onSelectTrainingDepth;
  final RestartModuleProgress moduleProgress;
  final String? userId;
  final String workerHost;
  final String apiPrefix;
  final String targetLanguage;
  final String? nativeLanguage;
  final List<DateTime>? fallbackDatesUtc;
  final ValueChanged<String>? onTargetLanguageChange;
  final ValueChanged<String>? onNativeLanguageChange;
  final ValueChanged<String?>? onResumeEmojiChanged;
  final ValueChanged<List<String>>? onResumeFeedbackIdsChanged;

  @override
  State<RestartSplash> createState() => _RestartSplashState();
}

class _RestartSplashState extends State<RestartSplash> {
  static const Duration _autoProceedDelay = Duration(seconds: 6);

  bool _resumeFeedbackVisible = false;
  bool _menuOpen = false;
  Timer? _autoProceedTimer;
  bool _autoProceedCanceled = false;
  bool _startTriggered = false;

  @override
  void initState() {
    super.initState();
    _scheduleAutoProceed();
  }

  @override
  void dispose() {
    _autoProceedTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoProceed() {
    if (_autoProceedCanceled || _startTriggered) return;
    _autoProceedTimer?.cancel();
    _autoProceedTimer = Timer(_autoProceedDelay, () {
      if (!mounted || _autoProceedCanceled || _startTriggered) return;
      _triggerStart();
    });
  }

  void _cancelAutoProceed() {
    if (_autoProceedCanceled) return;
    _autoProceedCanceled = true;
    _autoProceedTimer?.cancel();
    _autoProceedTimer = null;
  }

  void _triggerStart() {
    if (_startTriggered) return;
    _startTriggered = true;
    _autoProceedTimer?.cancel();
    _autoProceedTimer = null;
    widget.onStart();
  }

  void _handleAnyPointerDown(PointerDownEvent event) {
    _cancelAutoProceed();
  }

  void _openMenu() {
    _cancelAutoProceed();
    setState(() {
      _menuOpen = true;
    });
  }

  void _closeMenu() {
    setState(() {
      _menuOpen = false;
    });
  }

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
    final tooltipChangeModule =
        _resumeTooltipText('change_module', tooltipLanguage);
    final tooltipStartLearning =
        _resumeTooltipText('start_learning', tooltipLanguage);
    final tooltipYou = _resumeTooltipText('you', tooltipLanguage);
    final tooltipYourRival = _resumeTooltipText('your_rival', tooltipLanguage);
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
              _cancelAutoProceed();
              await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                        _RestartMenuButton(size: 72, onPressed: _openMenu),
                        Tooltip(
                          message: tooltipStartLearning,
                          child: GestureDetector(
                            onTap: _triggerStart,
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
                      _RestartMenuButton(size: 64, onPressed: _openMenu),
                      Tooltip(
                        message: tooltipStartLearning,
                        child: GestureDetector(
                          onTap: _triggerStart,
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
      body: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleAnyPointerDown,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                  final compactLayout = constraints.maxHeight < 860 ||
                      constraints.maxWidth < 980 ||
                      textScale > 1.15;
                  final topSpacing = compactLayout ? 16.0 : 32.0;
                  final logoHeight = compactLayout ? 100.0 : 120.0;
                  final victoryHeight = compactLayout ? 170.0 : 200.0;
                  final compactCalendarHeight = (constraints.maxHeight * 0.4)
                      .clamp(180.0, 280.0)
                      .toDouble();
                  final compactCalendarSectionHeight = compactCalendarHeight +
                      (_resumeFeedbackVisible ? 100.0 : 0.0);

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
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
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
          ),
          if (_menuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeMenu,
                child: Container(color: const Color(0x33000000)),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: _RestartBurgerMenuPanel(
                targetLanguageCode: widget.targetLanguage,
                nativeLanguageCode: widget.nativeLanguage,
                selectedTrainingDepth: widget.selectedTrainingDepth,
                moduleIconAsset: widget.moduleProgress.iconAsset,
                changeModuleTooltip: tooltipChangeModule,
                onClose: _closeMenu,
                onOpenModuleSelection: () {
                  _closeMenu();
                  widget.onSelectModule();
                },
                onSelectTrainingDepth: widget.onSelectTrainingDepth,
                onTargetLanguageChange: widget.onTargetLanguageChange,
                onNativeLanguageChange: widget.onNativeLanguageChange,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RestartMenuButton extends StatelessWidget {
  const _RestartMenuButton({
    required this.size,
    required this.onPressed,
  });

  final double size;
  final VoidCallback onPressed;

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
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xffe5d7c4)),
          ),
          child: Icon(
            Icons.menu,
            size: size * 0.58,
            color: const Color(0xff4a2c12),
          ),
        ),
      ),
    );
  }
}

class _RestartBurgerMenuPanel extends StatefulWidget {
  const _RestartBurgerMenuPanel({
    required this.targetLanguageCode,
    this.nativeLanguageCode,
    required this.selectedTrainingDepth,
    required this.moduleIconAsset,
    required this.changeModuleTooltip,
    required this.onClose,
    required this.onOpenModuleSelection,
    required this.onSelectTrainingDepth,
    this.onTargetLanguageChange,
    this.onNativeLanguageChange,
  });

  final String targetLanguageCode;
  final String? nativeLanguageCode;
  final TrainingDepthMode selectedTrainingDepth;
  final String moduleIconAsset;
  final String changeModuleTooltip;
  final VoidCallback onClose;
  final VoidCallback onOpenModuleSelection;
  final ValueChanged<TrainingDepthMode> onSelectTrainingDepth;
  final ValueChanged<String>? onTargetLanguageChange;
  final ValueChanged<String>? onNativeLanguageChange;

  @override
  State<_RestartBurgerMenuPanel> createState() =>
      _RestartBurgerMenuPanelState();
}

class _RestartBurgerMenuPanelState extends State<_RestartBurgerMenuPanel> {
  double _speechRate = 1.0;

  @override
  Widget build(BuildContext context) {
    final l1 = _restartNormalizeLang(widget.nativeLanguageCode) ??
        _restartNormalizeLang(widget.targetLanguageCode) ??
        'en';
    final l2 = _restartNormalizeLang(widget.targetLanguageCode) ?? l1;
    final panelWidth =
        math.min(MediaQuery.of(context).size.width * 0.86, 360.0);
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
                        _restartT(l1, 'options'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'serif',
                          color: Color(0xff2b2117),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onClose,
                      child: Text(_restartT(l1, 'close')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _RestartMenuSectionTitle(_restartT(l1, 'module')),
                const Text('RealTalk', style: _restartMenuNoteStyle),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _RestartActionButton(
                        label: _restartT(l1, 'module_selection'),
                        onPressed: widget.onOpenModuleSelection,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: widget.changeModuleTooltip,
                      child: GestureDetector(
                        onTap: widget.onOpenModuleSelection,
                        child: Image.asset(
                          widget.moduleIconAsset,
                          width: 42,
                          height: 42,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _RestartMenuSectionTitle(_restartT(l1, 'languages')),
                const SizedBox(height: 8),
                const Text('L1 -> L2', style: _restartMenuLabelStyle),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _RestartLanguageDropdown(
                        value: l1,
                        onChanged: widget.onNativeLanguageChange,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('->',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    Expanded(
                      child: _RestartLanguageDropdown(
                        value: l2,
                        onChanged: widget.onTargetLanguageChange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _RestartMenuSectionTitle(_restartT(l1, 'training_depth')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _RestartImageChoiceButton(
                        label: _restartT(l1, 'default_learning'),
                        asset: 'assets/icons/default.webp',
                        selected: widget.selectedTrainingDepth ==
                            TrainingDepthMode.defaultMode,
                        onPressed: () => widget.onSelectTrainingDepth(
                          TrainingDepthMode.defaultMode,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RestartImageChoiceButton(
                        label: _restartT(l1, 'deeper_learning'),
                        asset: 'assets/icons/deep.webp',
                        selected: widget.selectedTrainingDepth ==
                            TrainingDepthMode.deep,
                        onPressed: () => widget.onSelectTrainingDepth(
                          TrainingDepthMode.deep,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _RestartMenuSectionTitle(_restartT(l1, 'tempo')),
                const SizedBox(height: 8),
                Text(_restartT(l1, 'speech_rate'),
                    style: _restartMenuLabelStyle),
                const SizedBox(height: 6),
                DropdownButtonFormField<double>(
                  initialValue: _speechRate,
                  decoration: _restartMenuInputDecoration(),
                  items: [
                    DropdownMenuItem(
                      value: 0.70,
                      child: Text('${_restartT(l1, 'rate_slow')} (0.70x)'),
                    ),
                    DropdownMenuItem(
                      value: 0.85,
                      child: Text(
                          '${_restartT(l1, 'rate_somewhat_slow')} (0.85x)'),
                    ),
                    DropdownMenuItem(
                      value: 0.95,
                      child: Text(
                          '${_restartT(l1, 'rate_almost_normal')} (0.95x)'),
                    ),
                    DropdownMenuItem(
                      value: 1.00,
                      child: Text('${_restartT(l1, 'rate_normal')} (1.00x)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _speechRate = value);
                  },
                ),
                const SizedBox(height: 20),
                _RestartMenuSectionTitle(_restartT(l1, 'fallback')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _RestartRuntimeBadge(label: _restartT(l1, 'controlled')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _restartT(l1, 'runtime_unavailable'),
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

class _RestartLanguageDropdown extends StatelessWidget {
  const _RestartLanguageDropdown(
      {required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: _restartMenuInputDecoration(),
      items: langChoices
          .map(
            (code) => DropdownMenuItem(
              value: code,
              child: Text(
                '${langFlags[code] ?? ''} ${_restartLanguageName(code)}',
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

class _RestartActionButton extends StatelessWidget {
  const _RestartActionButton({
    required this.label,
    required this.onPressed,
    this.leading,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black87,
        side: const BorderSide(color: Colors.black, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _RestartImageChoiceButton extends StatelessWidget {
  const _RestartImageChoiceButton({
    required this.label,
    required this.asset,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String asset;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? const Color(0x223286E6) : Colors.white,
          foregroundColor: Colors.black87,
          side: BorderSide(
            color: selected ? const Color(0xFF3286E6) : const Color(0xffe5d7c4),
            width: selected ? 1.6 : 1.0,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(asset, width: 34, height: 34, fit: BoxFit.contain),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestartMenuSectionTitle extends StatelessWidget {
  const _RestartMenuSectionTitle(this.text);

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

class _RestartRuntimeBadge extends StatelessWidget {
  const _RestartRuntimeBadge({required this.label});

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

InputDecoration _restartMenuInputDecoration() {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}

String? _restartNormalizeLang(String? value) {
  final raw = value?.trim().toLowerCase() ?? '';
  if (raw.isEmpty) return null;
  final candidate = raw.split(RegExp(r'[-_]')).first;
  return langChoices.contains(candidate) ? candidate : null;
}

String _restartLanguageName(String code) {
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

String _restartT(String languageCode, String key) {
  final lang = _restartNormalizeLang(languageCode) ?? 'en';
  final table = _restartLocalizedText[lang] ?? _restartLocalizedText['en']!;
  return table[key] ?? _restartLocalizedText['en']![key] ?? key;
}

const _restartMenuLabelStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w800,
  color: Color(0xff2b2117),
);

const _restartMenuNoteStyle = TextStyle(
  fontSize: 12,
  color: Color(0xff695b4d),
);

const Map<String, Map<String, String>> _restartLocalizedText = {
  'en': {
    'options': 'Options',
    'export_logs': 'Export logs',
    'export_failed': 'Export failed.',
    'export_debug': 'Export debug log',
    'export_dialog': 'Export dialog log',
    'close': 'Close',
    'module': 'Module',
    'module_selection': 'Module selection',
    'languages': 'Languages',
    'input': 'Input',
    'l2_direct': 'L2 direct',
    'l1_to_l2': 'Speak L1, transfer to L2',
    'training_depth': 'Training depth',
    'default_learning': 'Default learning',
    'deeper_learning': 'Deeper learning',
    'tempo': 'Tempo',
    'speech_rate': 'Speech rate',
    'rate_slow': 'Slow',
    'rate_somewhat_slow': 'Somewhat slow',
    'rate_almost_normal': 'Almost normal',
    'rate_normal': 'Normal',
    'session': 'Session',
    'history': 'History',
    'home': 'Home',
    'fallback': 'Fallback',
    'controlled': 'Controlled response',
    'runtime_unavailable': 'Current session uses the local training runtime.',
  },
  'de': {
    'options': 'Optionen',
    'export_logs': 'Logs exportieren',
    'export_failed': 'Export fehlgeschlagen.',
    'export_debug': 'Debug-Protokoll exportieren',
    'export_dialog': 'Dialog-Protokoll exportieren',
    'close': 'Schliessen',
    'module': 'Modul',
    'module_selection': 'Modulauswahl',
    'languages': 'Sprachen',
    'input': 'Eingabe',
    'l2_direct': 'L2 direkt',
    'l1_to_l2': 'L1 sprechen, nach L2 uebertragen',
    'training_depth': 'Trainingstiefe',
    'default_learning': 'Standardlernen',
    'deeper_learning': 'Vertieftes Lernen',
    'tempo': 'Tempo',
    'speech_rate': 'Sprechtempo',
    'rate_slow': 'Langsam',
    'rate_somewhat_slow': 'Etwas langsam',
    'rate_almost_normal': 'Fast normal',
    'rate_normal': 'Normal',
    'session': 'Sitzung',
    'history': 'Verlauf',
    'home': 'Home',
    'fallback': 'Fallback',
    'controlled': 'Kontrollierte Antwort',
    'runtime_unavailable': 'Diese Sitzung nutzt die lokale Trainings-Runtime.',
  },
  'fr': {
    'options': 'Options',
    'export_logs': 'Exporter les journaux',
    'export_failed': 'Export echoue.',
    'export_debug': 'Exporter le journal de debug',
    'export_dialog': 'Exporter le journal du dialogue',
    'close': 'Fermer',
    'module': 'Module',
    'module_selection': 'Choix du module',
    'languages': 'Langues',
    'training_depth': 'Profondeur d entrainement',
    'default_learning': 'Apprentissage standard',
    'deeper_learning': 'Apprentissage approfondi',
    'tempo': 'Rythme',
    'speech_rate': 'Vitesse de parole',
    'rate_slow': 'Lent',
    'rate_somewhat_slow': 'Un peu lent',
    'rate_almost_normal': 'Presque normal',
    'rate_normal': 'Normal',
    'fallback': 'Fallback',
    'controlled': 'Reponse controlee',
    'runtime_unavailable':
        'Cette session utilise le moteur local d entrainement.',
  },
  'es': {
    'options': 'Opciones',
    'export_logs': 'Exportar registros',
    'export_failed': 'Error al exportar.',
    'export_debug': 'Exportar registro de depuracion',
    'export_dialog': 'Exportar registro de dialogo',
    'close': 'Cerrar',
    'module': 'Modulo',
    'module_selection': 'Seleccion de modulo',
    'languages': 'Idiomas',
    'training_depth': 'Profundidad de entrenamiento',
    'default_learning': 'Aprendizaje estandar',
    'deeper_learning': 'Aprendizaje profundo',
    'tempo': 'Ritmo',
    'speech_rate': 'Velocidad de habla',
    'rate_slow': 'Lento',
    'rate_somewhat_slow': 'Algo lento',
    'rate_almost_normal': 'Casi normal',
    'rate_normal': 'Normal',
    'fallback': 'Fallback',
    'controlled': 'Respuesta controlada',
    'runtime_unavailable': 'Esta sesion usa el motor local de entrenamiento.',
  },
  'it': {
    'options': 'Opzioni',
    'export_logs': 'Esporta log',
    'export_failed': 'Esportazione non riuscita.',
    'export_debug': 'Esporta log di debug',
    'export_dialog': 'Esporta log dialogo',
    'close': 'Chiudi',
    'module': 'Modulo',
    'module_selection': 'Scelta modulo',
    'languages': 'Lingue',
    'training_depth': 'Profondita allenamento',
    'default_learning': 'Apprendimento standard',
    'deeper_learning': 'Apprendimento approfondito',
    'tempo': 'Tempo',
    'speech_rate': 'Velocita voce',
    'rate_slow': 'Lento',
    'rate_somewhat_slow': 'Abbastanza lento',
    'rate_almost_normal': 'Quasi normale',
    'rate_normal': 'Normale',
    'fallback': 'Fallback',
    'controlled': 'Risposta controllata',
    'runtime_unavailable':
        'Questa sessione usa il motore locale di allenamento.',
  },
  'el': {
    'options': 'Epiloges',
    'export_logs': 'Exagogi log',
    'export_failed': 'I exagogi apetyche.',
    'export_debug': 'Exagogi debug log',
    'export_dialog': 'Exagogi dialog log',
    'close': 'Kleisimo',
    'module': 'Module',
    'module_selection': 'Epilogi module',
    'languages': 'Glosses',
    'training_depth': 'Bathos ekpaidefsis',
    'default_learning': 'Vasiki ekmathisi',
    'deeper_learning': 'Pio vathia ekmathisi',
    'tempo': 'Tempo',
    'speech_rate': 'Tachytita omilias',
    'rate_slow': 'Arga',
    'rate_somewhat_slow': 'Ligo arga',
    'rate_almost_normal': 'Schedon kanonika',
    'rate_normal': 'Kanonika',
    'fallback': 'Fallback',
    'controlled': 'Elegchomeni apantisi',
    'runtime_unavailable':
        'Afti i synedria chrismopoiei tin topiki runtime ekpaidefsis.',
  },
  'ru': {
    'options': 'Nastroiki',
    'export_logs': 'Eksport zhurnalov',
    'export_failed': 'Eksport ne udalsya.',
    'export_debug': 'Eksport debug zhurnala',
    'export_dialog': 'Eksport dialoga',
    'close': 'Zakryt',
    'module': 'Modul',
    'module_selection': 'Vybor modula',
    'languages': 'Yazyki',
    'training_depth': 'Glubina trenirovki',
    'default_learning': 'Obychnoe obuchenie',
    'deeper_learning': 'Glubokoe obuchenie',
    'tempo': 'Temp',
    'speech_rate': 'Skorost rechi',
    'rate_slow': 'Medlenno',
    'rate_somewhat_slow': 'Nemnogo medlenno',
    'rate_almost_normal': 'Pochti normalno',
    'rate_normal': 'Normalno',
    'fallback': 'Fallback',
    'controlled': 'Kontroliruemyi otvet',
    'runtime_unavailable':
        'Eta sessiya ispolzuet lokalnuyu trenirovochnuyu sredu.',
  },
  'tr': {
    'options': 'Secenekler',
    'export_logs': 'Kayitlari disa aktar',
    'export_failed': 'Disa aktarma basarisiz.',
    'export_debug': 'Debug kaydini disa aktar',
    'export_dialog': 'Diyalog kaydini disa aktar',
    'close': 'Kapat',
    'module': 'Modul',
    'module_selection': 'Modul secimi',
    'languages': 'Diller',
    'training_depth': 'Alistirma derinligi',
    'default_learning': 'Standart ogrenme',
    'deeper_learning': 'Derin ogrenme',
    'tempo': 'Tempo',
    'speech_rate': 'Konusma hizi',
    'rate_slow': 'Yavas',
    'rate_somewhat_slow': 'Biraz yavas',
    'rate_almost_normal': 'Neredeyse normal',
    'rate_normal': 'Normal',
    'fallback': 'Fallback',
    'controlled': 'Kontrollu yanit',
    'runtime_unavailable':
        'Bu oturum yerel alistirma calisma zamanini kullanir.',
  },
  'ar': {
    'options': 'الخيارات',
    'export_logs': 'تصدير السجلات',
    'export_failed': 'فشل التصدير.',
    'export_debug': 'تصدير سجل التصحيح',
    'export_dialog': 'تصدير سجل الحوار',
    'close': 'إغلاق',
    'module': 'الوحدة',
    'module_selection': 'اختيار الوحدة',
    'languages': 'اللغات',
    'training_depth': 'عمق التدريب',
    'default_learning': 'تعلم عادي',
    'deeper_learning': 'تعلم أعمق',
    'tempo': 'السرعة',
    'speech_rate': 'سرعة الكلام',
    'rate_slow': 'بطيء',
    'rate_somewhat_slow': 'بطيء قليلا',
    'rate_almost_normal': 'شبه طبيعي',
    'rate_normal': 'طبيعي',
    'fallback': 'بديل',
    'controlled': 'رد مضبوط',
    'runtime_unavailable': 'تستخدم هذه الجلسة محرك التدريب المحلي.',
  },
  'zh': {
    'options': '选项',
    'export_logs': '导出日志',
    'export_failed': '导出失败。',
    'export_debug': '导出调试日志',
    'export_dialog': '导出对话日志',
    'close': '关闭',
    'module': '模块',
    'module_selection': '模块选择',
    'languages': '语言',
    'training_depth': '训练深度',
    'default_learning': '标准学习',
    'deeper_learning': '深入学习',
    'tempo': '速度',
    'speech_rate': '语速',
    'rate_slow': '慢',
    'rate_somewhat_slow': '稍慢',
    'rate_almost_normal': '接近正常',
    'rate_normal': '正常',
    'fallback': '备用',
    'controlled': '受控回答',
    'runtime_unavailable': '本次会话使用本地训练运行时。',
  },
  'ja': {
    'options': 'オプション',
    'export_logs': 'ログを書き出す',
    'export_failed': '書き出しに失敗しました。',
    'export_debug': 'デバッグログを書き出す',
    'export_dialog': '対話ログを書き出す',
    'close': '閉じる',
    'module': 'モジュール',
    'module_selection': 'モジュール選択',
    'languages': '言語',
    'training_depth': '練習の深さ',
    'default_learning': '標準学習',
    'deeper_learning': '深い学習',
    'tempo': 'テンポ',
    'speech_rate': '発話速度',
    'rate_slow': '遅い',
    'rate_somewhat_slow': '少し遅い',
    'rate_almost_normal': 'ほぼ普通',
    'rate_normal': '普通',
    'fallback': 'フォールバック',
    'controlled': '制御された応答',
    'runtime_unavailable': 'このセッションはローカル訓練ランタイムを使います。',
  },
  'hi': {
    'options': 'विकल्प',
    'export_logs': 'लॉग निर्यात करें',
    'export_failed': 'निर्यात विफल रहा।',
    'export_debug': 'डिबग लॉग निर्यात करें',
    'export_dialog': 'संवाद लॉग निर्यात करें',
    'close': 'बंद करें',
    'module': 'मॉड्यूल',
    'module_selection': 'मॉड्यूल चयन',
    'languages': 'भाषाएँ',
    'training_depth': 'अभ्यास की गहराई',
    'default_learning': 'सामान्य सीखना',
    'deeper_learning': 'गहरा सीखना',
    'tempo': 'गति',
    'speech_rate': 'बोलने की गति',
    'rate_slow': 'धीमा',
    'rate_somewhat_slow': 'थोड़ा धीमा',
    'rate_almost_normal': 'लगभग सामान्य',
    'rate_normal': 'सामान्य',
    'fallback': 'वैकल्पिक',
    'controlled': 'नियंत्रित उत्तर',
    'runtime_unavailable': 'यह सत्र स्थानीय प्रशिक्षण रनटाइम का उपयोग करता है।',
  },
};

class NamingView extends StatelessWidget {
  const NamingView({
    super.key,
    required this.leftImageBytes,
    required this.rightImageBytes,
    required this.targetOnLeft,
    required this.imageHeight,
    required this.namingCorrectDetected,
    required this.namingOutcome,
    required this.micPrimed,
    required this.micDenied,
    required this.micPermanentlyDenied,
    required this.speechPermanentlyDenied,
    required this.namingHold,
    required this.showHourglass,
    required this.namingInProgress,
    required this.namingStartPending,
    required this.showTinySpinner,
    required this.liveTranscript,
    required this.startNamingLabel,
    required this.retryMicLabel,
    required this.settingsLabel,
    required this.withoutMicLabel,
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
  final bool namingCorrectDetected;
  final bool? namingOutcome;
  final bool micPrimed;
  final bool micDenied;
  final bool micPermanentlyDenied;
  final bool speechPermanentlyDenied;
  final bool namingHold;
  final bool showHourglass;
  final bool namingInProgress;
  final bool namingStartPending;
  final bool showTinySpinner;
  final String liveTranscript;
  final String startNamingLabel;
  final String retryMicLabel;
  final String settingsLabel;
  final String withoutMicLabel;
  final VoidCallback onStartNaming;
  final VoidCallback onOpenSettings;
  final void Function(String reason) onContinueWithoutMic;
  final void Function(String reason) onSkip;
  final VoidCallback? onEscapeToOpeningPanel;

  @override
  Widget build(BuildContext context) {
    const bool isWeb = kIsWeb;
    const double gapHourglass = isWeb ? 1 : 4;
    const double cardMargin = isWeb ? 2 : 6;
    const double cardPadding = isWeb ? 6 : 10;
    final bool showCorrectState =
        namingCorrectDetected || namingOutcome == true;
    final bool showIncorrectState = namingOutcome == false;
    final Color borderColor = showCorrectState
        ? Colors.green
        : (showIncorrectState ? Colors.red : Colors.grey.shade400);
    final Color? cardFill = showCorrectState
        ? Colors.green.shade200
        : (showIncorrectState ? Colors.red.shade200 : null);
    final Uint8List targetImageBytes =
        targetOnLeft ? leftImageBytes : rightImageBytes;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(cardMargin),
          padding: const EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            color: cardFill,
            border: Border.all(
              color: borderColor,
              width: showCorrectState || showIncorrectState ? 4 : 3,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final double maxWidth = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : imageHeight;
                  final double frameDiameter =
                      math.min(imageHeight, maxWidth).clamp(0.0, imageHeight);

                  return SizedBox(
                    width: frameDiameter,
                    height: frameDiameter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: borderColor,
                          width: showCorrectState || showIncorrectState ? 4 : 3,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: ClipOval(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                targetImageBytes,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    _imageLoadFallback(),
                              ),
                              if (showCorrectState || showIncorrectState)
                                Container(
                                  color: showCorrectState
                                      ? Colors.green.withValues(alpha: 0.22)
                                      : Colors.red.withValues(alpha: 0.2),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
            padding: const EdgeInsets.only(top: gapHourglass),
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
        if (namingOutcome == null && !namingInProgress && !namingStartPending)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: (namingInProgress || namingStartPending)
                      ? null
                      : onStartNaming,
                  icon: const Icon(Icons.mic, size: 16),
                  label: Text(!micPrimed ? startNamingLabel : retryMicLabel),
                ),
                OutlinedButton.icon(
                  onPressed: (namingInProgress || namingStartPending)
                      ? null
                      : onOpenSettings,
                  icon: const Icon(Icons.settings, size: 16),
                  label: Text(settingsLabel),
                ),
                TextButton(
                  onPressed: (namingInProgress || namingStartPending)
                      ? null
                      : () => onContinueWithoutMic('manual_button'),
                  child: Text(withoutMicLabel),
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
                  errorBuilder: (context, error, stackTrace) =>
                      _imageLoadFallback(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TapPrimerPanel extends StatefulWidget {
  const TapPrimerPanel({
    super.key,
    required this.onProceed,
    this.autoProceedDelay = const Duration(seconds: 8),
    this.l1,
    this.l2,
  });

  final ValueChanged<bool> onProceed;
  final Duration autoProceedDelay;
  final String? l1;
  final String? l2;

  @override
  State<TapPrimerPanel> createState() => _TapPrimerPanelState();
}

class _TapPrimerPanelState extends State<TapPrimerPanel> {
  Timer? _autoProceedTimer;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _autoProceedTimer = Timer(widget.autoProceedDelay, () {
      _trigger(primeAudio: false);
    });
  }

  @override
  void dispose() {
    _autoProceedTimer?.cancel();
    super.dispose();
  }

  void _trigger({required bool primeAudio}) {
    if (_handled) return;
    _handled = true;
    _autoProceedTimer?.cancel();
    widget.onProceed(primeAudio);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double promptWidth =
        math.min(size.width * 0.94, 1180).clamp(320.0, 1180.0).toDouble();
    final double promptHeight =
        math.min(size.height * 0.76, 820).clamp(260.0, 820.0).toDouble();
    final String text = tapPromptTexts[widget.l1] ??
        tapPromptTexts[widget.l2] ??
        'Tap an image';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _trigger(primeAudio: true),
      child: SizedBox.expand(
        child: Container(
          color: Colors.white,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: promptWidth,
                  height: promptHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x11000000),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Image.asset(
                            'assets/icons/tap.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, error, stackTrace) =>
                                _tapPrimerIllustrationFallback(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Color(0xDD000000),
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

Widget _tapPrimerIllustrationFallback() {
  return DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
      ),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _tapPrimerCard(
                          icon: Icons.landscape_rounded,
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _tapPrimerCard(
                          icon: Icons.cookie_rounded,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD9E1EA)),
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Tap the picture',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(Icons.volume_up_rounded, color: Color(0xFF475569)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Positioned(
          left: 16,
          bottom: 36,
          child: Icon(
            Icons.touch_app_rounded,
            size: 92,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    ),
  );
}

Widget _imageLoadFallback() {
  return Container(
    width: 300,
    height: 300,
    color: const Color(0xFFF3F4F6),
    alignment: Alignment.center,
    child: const Icon(
      Icons.broken_image_outlined,
      size: 100,
      color: Color(0xFF9CA3AF),
    ),
  );
}

Widget _tapPrimerCard({
  required IconData icon,
  required Color color,
}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFD9E1EA), width: 2),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 82, color: color),
  );
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
    required this.namingCorrectDetected,
    required this.namingOutcome,
    required this.namingStatus,
    required this.micPrimed,
    required this.micDenied,
    required this.micPermanentlyDenied,
    required this.speechPermanentlyDenied,
    required this.micStatusDetails,
    required this.namingHold,
    required this.showHourglass,
    required this.namingInProgress,
    required this.namingStartPending,
    required this.micOn,
    required this.micStage,
    required this.namingPaused,
    required this.showTinySpinner,
    required this.liveTranscript,
    required this.startNamingLabel,
    required this.retryMicLabel,
    required this.settingsLabel,
    required this.withoutMicLabel,
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
    required this.onToggleNamingPauseResume,
    required this.onSelect,
    required this.onOpenDashboard,
    required this.tooltipLanguageCode,
    this.onEscapeToOpeningPanel,
    this.onExitToResumePanel,
    this.onReturnToModuleSelection,
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
  final bool namingCorrectDetected;
  final bool? namingOutcome;
  final String namingStatus;
  final bool micPrimed;
  final bool micDenied;
  final bool micPermanentlyDenied;
  final bool speechPermanentlyDenied;
  final String micStatusDetails;
  final bool namingHold;
  final bool showHourglass;
  final bool namingInProgress;
  final bool namingStartPending;
  final bool micOn;
  final int micStage;
  final bool namingPaused;
  final bool showTinySpinner;
  final String liveTranscript;
  final String startNamingLabel;
  final String retryMicLabel;
  final String settingsLabel;
  final String withoutMicLabel;
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
  final VoidCallback onToggleNamingPauseResume;
  final void Function(bool choseLeft) onSelect;
  final VoidCallback onOpenDashboard;
  final String tooltipLanguageCode;
  final VoidCallback? onEscapeToOpeningPanel;
  final Future<void> Function()? onExitToResumePanel;
  final Future<void> Function()? onReturnToModuleSelection;

  @override
  Widget build(BuildContext context) {
    const bool isWeb = kIsWeb;
    const double sessionMenuReservedHeight = 46.0;
    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final bool compactNamingLayout = isNaming;
    final double panelGap =
        compactNamingLayout ? (isWeb ? 1 : 4) : (isWeb ? 4 : 12);
    final double infoPanelVerticalPadding =
        compactNamingLayout ? (isWeb ? 5 : 8) : (isWeb ? 8 : 14);
    final double trackTopPadding =
        compactNamingLayout ? (isWeb ? 0 : 4) : (isWeb ? 2 : 8);
    final double bottomBarHeight = namingInProgress ? 48.0 : 0.0;
    final double verticalInsets = MediaQuery.of(context).padding.vertical +
        32 +
        bottomBarHeight +
        sessionMenuReservedHeight;
    final double availableHeight = size.height - verticalInsets;

    final bool shrinkHexaWeb = kIsWeb && isNaming;
    final double namingHexaScale = shrinkHexaWeb ? 0.9 : 1.0;
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
        centerGrid: false,
        mountainTheme: mountainTheme,
        mountainYouWon: mountainYouWon,
        mountainRivalWon: mountainRivalWon,
        wins: ladder.winsYou,
        rivalWins: ladder.winsRival,
      ),
    );
    final Widget trackWidget = baseTrackWidget;
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
            namingCorrectDetected: namingCorrectDetected,
            namingOutcome: namingOutcome,
            micPrimed: micPrimed,
            micDenied: micDenied,
            micPermanentlyDenied: micPermanentlyDenied,
            speechPermanentlyDenied: speechPermanentlyDenied,
            namingHold: namingHold,
            showHourglass: showHourglass,
            namingInProgress: namingInProgress,
            namingStartPending: namingStartPending,
            showTinySpinner: showTinySpinner,
            liveTranscript: liveTranscript,
            startNamingLabel: startNamingLabel,
            retryMicLabel: retryMicLabel,
            settingsLabel: settingsLabel,
            withoutMicLabel: withoutMicLabel,
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
              showHourglass: isNaming && namingInProgress,
              hourglassWiggle:
                  isNaming && namingInProgress && micOn && !namingPaused,
              hourglassMicStage: micStage,
              hourglassMicOn: micOn,
              hourglassMicPaused: namingPaused,
              onHourglassTap: onToggleNamingPauseResume,
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
        padding: const EdgeInsets.only(bottom: sessionMenuReservedHeight),
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

    final moduleSelectionTooltip = _sessionMenuTooltipText(
        'return_to_module_selection', tooltipLanguageCode);

    return Stack(
      children: [
        layout,
        if (onReturnToModuleSelection != null)
          Positioned(
            right: 8,
            bottom: 8,
            child: _ModuleSelectionReturnButton(
              tooltip: moduleSelectionTooltip,
              onTap: onReturnToModuleSelection!,
            ),
          ),
      ],
    );
  }
}

class _ModuleSelectionReturnButton extends StatefulWidget {
  const _ModuleSelectionReturnButton({
    required this.tooltip,
    required this.onTap,
  });

  final String tooltip;
  final Future<void> Function() onTap;

  @override
  State<_ModuleSelectionReturnButton> createState() =>
      _ModuleSelectionReturnButtonState();
}

class _ModuleSelectionReturnButtonState
    extends State<_ModuleSelectionReturnButton> {
  bool _busy = false;

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      await widget.onTap();
    } catch (e) {
      debugPrint('[module-selection-return][error] $e');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('${widget.tooltip}: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          onTap: _busy ? null : _handleTap,
          child: Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Image.asset(
                    'assets/icons/finish.webp',
                    fit: BoxFit.contain,
                  ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
String buildSessionInfoText({
  required bool isNaming,
  required String namingStatus,
  required String micStatusDetails,
}) {
  if (!isNaming) return '';
  final parts = <String>[];
  final trimmedStatus = namingStatus.trim();
  if (trimmedStatus.isNotEmpty) {
    parts.add(trimmedStatus);
  }
  final trimmedMic = micStatusDetails.trim();
  if (trimmedMic.isNotEmpty) {
    parts.add(trimmedMic);
  }
  return parts.join('\n\n');
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
