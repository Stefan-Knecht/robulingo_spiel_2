import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import 'package:robulingo_flutter/constants.dart';
import 'package:robulingo_flutter/data/api_client.dart';
import 'package:robulingo_flutter/data/app_update_service.dart';
import 'package:robulingo_flutter/data/pick_manifest_service.dart';
import 'package:robulingo_flutter/data/hint_models.dart';
import 'package:robulingo_flutter/data/hints_service.dart';
import 'package:robulingo_flutter/data/models.dart';
import 'package:robulingo_flutter/data/resume_state_service.dart';
import 'package:robulingo_flutter/data/supervisor_dashboard_service.dart';
import 'package:robulingo_flutter/data/supervisor_link_service.dart';
import 'package:robulingo_flutter/data/user_curriculum_delta.dart';
import 'package:robulingo_flutter/data/user_curriculum_service.dart';
import 'package:robulingo_flutter/event_logger.dart';
import 'package:robulingo_flutter/flavor_config.dart';
import 'package:robulingo_flutter/logic/item_stats.dart';
import 'package:robulingo_flutter/logic/hexagon_controller.dart';
import 'package:robulingo_flutter/logic/ladder_controller.dart'
    show MoveEvent, MoveKind;
import 'package:robulingo_flutter/logic/log_storage.dart';
import 'package:robulingo_flutter/logic/naming_controller.dart';
import 'package:robulingo_flutter/logic/onboarding_store.dart';
import 'package:robulingo_flutter/logic/cursor_resolver.dart';
import 'package:robulingo_flutter/logic/curriculum_loader.dart';
import 'package:robulingo_flutter/logic/history_hint_loader.dart';
import 'package:robulingo_flutter/logic/naming_flow_runner.dart';
import 'package:robulingo_flutter/logic/presentation_protocol_log.dart';
import 'package:robulingo_flutter/logic/playback/playback_engine.dart';
import 'package:robulingo_flutter/logic/playback/playback_engine_factory.dart';
import 'package:robulingo_flutter/logic/resume_state_controller.dart';
import 'package:robulingo_flutter/logic/session_cache_restorer.dart';
import 'package:robulingo_flutter/logic/session_reset.dart';
import 'package:robulingo_flutter/logic/session_init_data.dart';
import 'package:robulingo_flutter/logic/initial_item_loader.dart';
import 'package:robulingo_flutter/logic/inactivity_badge.dart';
import 'package:robulingo_flutter/logic/session_initializer.dart';
import 'package:robulingo_flutter/logic/session_preparer.dart';
import 'package:robulingo_flutter/logic/session_cache.dart';
import 'package:robulingo_flutter/logic/trial_buffer.dart';
import 'package:robulingo_flutter/logic/refiller_store.dart';
import 'package:robulingo_flutter/logic/user_delta_store.dart';
import 'package:robulingo_flutter/logic/user_identity.dart';
import 'package:robulingo_flutter/logic/item_presentation_policy.dart';
import 'package:robulingo_flutter/logic/voice_state.dart';
import 'package:robulingo_flutter/logic/naming_locale_helper.dart';
import 'package:robulingo_flutter/logic/mountain_background_cycle.dart';
import 'package:robulingo_flutter/ui/dashboard/dashboard_screen.dart';
import 'package:robulingo_flutter/ui/dailywords_module_selector.dart';
import 'package:robulingo_flutter/ui/history_panel.dart';
import 'package:robulingo_flutter/ui/lang_selector.dart';
import 'package:robulingo_flutter/ui/mic_progress_bar.dart';
import 'package:robulingo_flutter/ui/native_lang_selector.dart';
import 'package:robulingo_flutter/ui/realtalk_screen.dart';
import 'package:robulingo_flutter/ui/session/session_widgets.dart';
import 'package:robulingo_flutter/ui/start_curriculum_selector.dart';
import 'package:robulingo_flutter/ui/training_calendar_panel.dart';
import 'package:robulingo_flutter/utils/platform_info.dart';
import 'package:robulingo_flutter/utils/text_utils.dart';

// Languages where we *expect* a separate phonetic/reading aid to be useful.
// Note: compare against normalized base codes (e.g. "ja-JP" -> "ja").
const Set<String> _phoneticEligibleLangs = {'el', 'ar', 'ru', 'zh', 'hi', 'ja'};
const int _phoneticGlobalOverrideRuns = 40;
const Map<String, Map<String, String>> _namingInstructionTexts = {
  'naming_auto_start_prompt': {
    'en':
        'Microphone check starts now. Recording starts automatically 3 seconds after the image appears.',
    'de':
        'Die Mikrofonprüfung startet jetzt. Die Aufnahme beginnt automatisch 3 Sekunden nach der Bildpräsentation.',
    'el':
        'Ο έλεγχος μικροφώνου ξεκινά τώρα. Η εγγραφή αρχίζει αυτόματα 3 δευτερόλεπτα μετά την παρουσίαση της εικόνας.',
  },
  'start_naming': {
    'en': 'Start naming',
    'de': 'Benennen starten',
    'el': 'Έναρξη ονομασίας',
  },
  'retry_mic': {
    'en': 'Retry mic',
    'de': 'Mikrofon erneut',
    'el': 'Δοκιμή μικροφώνου ξανά',
  },
  'settings': {
    'en': 'Settings',
    'de': 'Einstellungen',
    'el': 'Ρυθμίσεις',
  },
  'without_mic': {
    'en': 'Without mic',
    'de': 'Ohne Mikrofon',
    'el': 'Χωρίς μικρόφωνο',
  },
  'naming_interrupted': {
    'en': 'Naming was interrupted. Tap "Retry mic" or continue without mic.',
    'de':
        'Das Benennen wurde unterbrochen. Tippe auf „Mikrofon erneut“ oder fahre ohne Mikrofon fort.',
    'el':
        'Η ονομασία διακόπηκε. Πατήστε «Δοκιμή μικροφώνου ξανά» ή συνεχίστε χωρίς μικρόφωνο.',
  },
  'browser_no_speech': {
    'en':
        'Browser speech recognition did not recognize any speech. Check browser microphone permission and the selected input device.',
    'de':
        'Die Browser-Spracherkennung hat keine Sprache erkannt. Prüfe die Mikrofonfreigabe im Browser und das ausgewählte Eingabegerät.',
    'el':
        'Η αναγνώριση ομιλίας του προγράμματος περιήγησης δεν αναγνώρισε ομιλία. Ελέγξτε την άδεια μικροφώνου του browser και τη συσκευή εισόδου.',
  },
  'no_microphone_signal': {
    'en': 'No microphone signal detected. Please speak closer.',
    'de': 'Kein Mikrofonsignal erkannt. Bitte sprich näher am Mikrofon.',
    'el': 'Δεν εντοπίστηκε σήμα μικροφώνου. Μιλήστε πιο κοντά.',
  },
  'speech_not_recognized': {
    'en': 'Microphone heard sound, but speech was not recognized.',
    'de': 'Das Mikrofon hat Ton erkannt, aber keine Sprache verstanden.',
    'el': 'Το μικρόφωνο άκουσε ήχο, αλλά δεν αναγνώρισε ομιλία.',
  },
  'no_transcript': {
    'en': 'No transcript captured. Please try again.',
    'de': 'Kein Transkript erfasst. Bitte versuche es erneut.',
    'el': 'Δεν καταγράφηκε κείμενο. Παρακαλώ δοκιμάστε ξανά.',
  },
};
const Map<String, Map<String, String>> _noMicNamingTexts = {
  'continue_without_recording': {
    'en': 'No microphone access. Naming continues without recording.',
    'de': 'Kein Mikrofonzugriff. Benennen läuft ohne Aufnahme weiter.',
    'ar': 'لا يوجد وصول إلى الميكروفون. تستمر مهمة التسمية بدون تسجيل.',
    'fr':
        'Pas d\'accès au microphone. La dénomination continue sans enregistrement.',
    'es': 'Sin acceso al micrófono. La denominación continúa sin grabación.',
    'it':
        'Nessun accesso al microfono. La denominazione continua senza registrazione.',
    'ru': 'Нет доступа к микрофону. Называние продолжается без записи.',
    'hi': 'माइक्रोफोन उपलब्ध नहीं है। नामकरण बिना रिकॉर्डिंग जारी रहेगा।',
    'el': 'Χωρίς πρόσβαση στο μικρόφωνο. Η ονομασία συνεχίζεται χωρίς εγγραφή.',
    'zh': '无法访问麦克风。命名将在不录音的情况下继续。',
    'tr': 'Mikrofon erişimi yok. Adlandırma kayıt olmadan devam ediyor.',
    'ja': 'マイクにアクセスできません。録音なしでネーミングを続行します。',
  },
  'scored_false': {
    'en': 'No microphone access. Naming was scored as false in fallback mode.',
    'de':
        'Kein Mikrofonzugriff. Benennen wurde im Fallback-Modus als falsch gewertet.',
    'ar':
        'لا يوجد وصول إلى الميكروفون. تم احتساب التسمية كخاطئة في وضع الطوارئ.',
    'fr':
        'Pas d\'accès au microphone. La dénomination a été notée fausse en mode de secours.',
    'es':
        'Sin acceso al micrófono. La denominación se evaluó como incorrecta en modo de respaldo.',
    'it':
        'Nessun accesso al microfono. La denominazione è stata valutata come errata in modalità fallback.',
    'ru':
        'Нет доступа к микрофону. В режиме fallback называние засчитано как неверное.',
    'hi': 'माइक्रोफोन उपलब्ध नहीं है। फॉलबैक मोड में नामकरण को गलत माना गया।',
    'el':
        'Χωρίς πρόσβαση στο μικρόφωνο. Η ονομασία αξιολογήθηκε ως λανθασμένη σε λειτουργία fallback.',
    'zh': '无法访问麦克风。在回退模式下，命名被判定为错误。',
    'tr':
        'Mikrofon erişimi yok. Adlandırma geri dönüş modunda yanlış olarak değerlendirildi.',
    'ja': 'マイクにアクセスできません。フォールバックモードではネーミングが不正解として判定されました。',
  },
};

@visibleForTesting
bool shouldSkipComprehensionAutoAdvance({
  required bool namingHold,
  required bool namingInProgress,
  required bool inNamingSlot,
}) {
  return namingHold || namingInProgress || inNamingSlot;
}

@visibleForTesting
bool shouldDisableNamingTransitions({
  required bool namingDisabled,
  required int namingBlockRemaining,
}) {
  return namingDisabled || namingBlockRemaining > 0;
}

@visibleForTesting
bool shouldRenderNamingView({
  required PresentationMode slotMode,
  required bool namingInProgress,
  required bool hasNamingOutcome,
  required bool policyNamingActive,
  required bool namingTransition,
}) {
  // Rendering is driven by the phase/slot, not by whether the Trial is already built.
  // This prevents a "comprehension-looking" frame during naming-slot loading.
  return slotMode == PresentationMode.naming ||
      namingInProgress ||
      hasNamingOutcome ||
      policyNamingActive ||
      namingTransition;
}

@visibleForTesting
ItemPresentationConfig presentationConfigForDepth(TrainingDepthMode mode) {
  switch (mode) {
    case TrainingDepthMode.defaultMode:
      return const ItemPresentationConfig();
    case TrainingDepthMode.deep:
      return const ItemPresentationConfig(
        // Keep comprehension-down unchanged from baseline.
        comprehensionDownMaxAttempts: 15,
        // Deep mode: require a full 6/6 correct window for comprehension-up.
        compWindowSize: 6,
        compWindowCorrectNeeded: 6,
        // Deep mode naming thresholds:
        // naming-up when correct > 2, naming-down when attempts > 7.
        namingMasteryCorrectThreshold: 2,
        namingDownFromNamingMaxAttempts: 7,
      );
  }
}

// ------------------------------------------------------------
// RobuLingo Viewer – Überblick für Laien
// ------------------------------------------------------------
// Ziel: Bild + Audio zeigen, Antworten prüfen, Fortschritt als Rennen/Leiter und Dashboard darstellen.
// Ablauf: Sprache wählen -> Curriculum laden -> Items mit Assets ziehen -> Trials bauen -> Audio/Naming spielen -> Logging.
// Bausteine:
//   - Daten: API-Client lädt Curriculum/JSON/Bilder/Audio; Varianten-Bilder zufällig.
//   - State/Logik: Trials/Ready-to-name, Ladder-Rennen, Audio, Logging.
//   - UI: Bildwahl, Benennen mit Mikro (Gate + Flow), Ladder-Track, Dashboard.
//   - Dashboard: Panels in ui/dashboard/* (Victory mit Rival/Therapist, Calendar mit Logs, Success mit Item-Stats).
//   - Stats: pro Item in logic/item_stats.dart; Dashboard liest Logs + Live-Daten.
// Wichtige Tücken:
//   - Async mit Tokens/Epoch entwerten (Trialwechsel, Rival-Move, Benennen).
//   - Naming-Gate: erst nach Zustimmung; bei Ablehnung/Timeout Fallback auf No-Mic-Naming.
//   - Rückwärtszüge im Rennen: nicht zweimal hintereinander auf derselben Kante, sonst Seitenwechsel.
//   - Seeds/Curriculum können fehlen (z.B. zh-Audio); Fehlermeldung prüfen.
// Willkürliche Parameter (Stand jetzt):
//   1) Muttersprache: Anzeige nur beim ersten Durchlauf pro Item (nativeSeenCounts < 1).
//   2) Rival-Startprognose: erste 10 Züge maxProb=0.9, danach skaliert mit letzter Accuracy.
//   3) Benennen: Item qualifiziert nach 4/4 korrekten Comprehension-Antworten; Naming startet erst, wenn >=5 Items qualifiziert sind.
//   4) Naming-Zeitfenster: 4s erste Aufnahme, 3s Wiederholung.
//   5) No-Mic-Naming: bei fehlendem Mikro läuft Naming ohne ASR weiter (wird als falsch gewertet).
// ------------------------------------------------------------
class RobuLingoApp extends StatefulWidget {
  const RobuLingoApp({super.key});
  @override
  State<RobuLingoApp> createState() => _RobuLingoAppState();
}

class _RestartCurriculumMetadata {
  const _RestartCurriculumMetadata({required this.totalItems});

  final int totalItems;
}

enum _MountainCelebrationResumeAction {
  none,
  nextTrial,
  advanceNaming,
}

class _RobuLingoAppState extends State<RobuLingoApp>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _disposed = false;
  static const int cachedItemCount = 12; // TODO: 500 im Zielzustand
  static const int namingMinUniqueItems = 5;
  static const int namingFirstWindowSec = 4;
  static const int namingRepeatWindowSec = 3;
  static const int namingHintWindowSec = 3;
  static const int namingStartAutoDelayMs = 3000;
  static const int namingProgressFirstRatio = 3;
  static const int namingProgressHintRatio = 2;
  static const int namingProgressRepeatRatio = 2;
  static const bool debugMountainFastFinishEnabled = false;
  static const int debugMountainStartRun = 190;
  static const Duration mountainWinCelebrationDelay = Duration(seconds: 5);
  static const double moveSoundVolume = 0.5;
  static const double namingBeepVolume = 0.5;
  static final AudioContext speechAudioContext = AudioContextConfig(
    focus: AudioContextConfigFocus.gain,
  ).build();
  static final AudioContext sfxAudioContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();
  // Tunable: spacing between naming reward steps/beeps.
  // (bigger = slower + clearer double beep)
  int namingRewardStepSpacingMs = 320;
  late ApiClient api;
  late PickManifestService pickManifestService;
  late UserCurriculumService userCurriculumService;
  late HintsService hintsService;
  late ResumeStateService resumeStateService;
  late SupervisorDashboardService supervisorDashboardService;
  late SupervisorLinkService supervisorLinkService;
  late AppUpdateService appUpdateService;
  late ResumeStateController resumeStateController;
  String workerHost = defaultWorkerHost;
  String fileHost = defaultFileHost;
  String apiPrefix = defaultApiPrefix;
  late final PlaybackEngine playbackEngine;
  final AudioPlayer fanfarePlayer = AudioPlayer();
  final AudioPlayer moveYouPlayer = AudioPlayer();
  final AudioPlayer moveRivalPlayer = AudioPlayer();
  final AudioPlayer namingBeepPlayer = AudioPlayer();
  final AudioPlayer namingBeepPlayer2 = AudioPlayer();
  final OnboardingStore onboardingStore = OnboardingStore();
  final SessionCacheStore sessionCacheStore = SessionCacheStore();
  final MountainThemeCycleStore mountainThemeCycleStore =
      MountainThemeCycleStore();
  final UserDeltaStore userDeltaStore = UserDeltaStore();
  final UserIdentity userIdentity = UserIdentity();
  UserCurriculumDelta? userDelta;
  bool resetCursorOnNextLoad = false;
  String? userId;
  final HistoryHintLoader historyHintLoader = HistoryHintLoader();
  bool awaitingLang = true;
  bool awaitingStart = false;
  bool awaitingNative = false;
  String? activeStartCurriculumKey;
  String? nativeLang; // Muttersprache; null = keine zweite Anzeige
  bool pickFlowActive = false;
  bool awaitingPickNative = false;
  bool pickListLoading = false;
  String? pickListError;
  String? lastModuleRowId;
  DailywordsModuleMode? lastModuleMode;
  List<String> pickManifestKeys = [];
  final Map<String, Future<List<CurriculumEntry>>> pickMappingFutures = {};
  final Map<String, Future<String>> pickManifestLabelFutures = {};
  final stt.SpeechToText speech = stt.SpeechToText();
  late NamingController namingController;
  final VoiceState voiceState = VoiceState();
  late VoiceController voiceController;
  bool get micReady => voiceState.micReady;
  set micReady(bool value) => voiceState.micReady = value;
  bool get micPrimed => voiceState.micPrimed;
  set micPrimed(bool value) => voiceState.micPrimed = value;
  bool get micPromptActive => voiceState.micPromptActive;
  set micPromptActive(bool value) => voiceState.micPromptActive = value;
  bool get micDenied => voiceState.micDenied;
  set micDenied(bool value) => voiceState.micDenied = value;
  bool get micPermanentlyDenied => voiceState.micPermanentlyDenied;
  set micPermanentlyDenied(bool value) =>
      voiceState.micPermanentlyDenied = value;
  bool get speechPermanentlyDenied => voiceState.speechPermanentlyDenied;
  set speechPermanentlyDenied(bool value) =>
      voiceState.speechPermanentlyDenied = value;
  bool get namingInProgress => voiceState.namingInProgress;
  set namingInProgress(bool value) => voiceState.namingInProgress = value;
  bool get namingHold => voiceState.namingHold;
  set namingHold(bool value) => voiceState.namingHold = value;
  String get namingStatus => voiceState.namingStatus;
  set namingStatus(String value) => voiceState.namingStatus = value;
  String get _liveTranscript => voiceState.liveTranscript;
  set _liveTranscript(String value) => voiceState.liveTranscript = value;
  bool? get namingOutcome => voiceState.namingOutcome;
  set namingOutcome(bool? value) => voiceState.namingOutcome = value;
  bool get namingCorrectDetected => voiceState.namingCorrectDetected;
  set namingCorrectDetected(bool value) =>
      voiceState.namingCorrectDetected = value;
  bool get namingDisabled => voiceState.namingDisabled;
  set namingDisabled(bool value) => voiceState.namingDisabled = value;
  int get namingBlockRemaining => voiceState.namingBlockRemaining;
  set namingBlockRemaining(int value) =>
      voiceState.namingBlockRemaining = value;
  bool get namingNoMicMode => voiceState.namingNoMicMode;
  set namingNoMicMode(bool value) => voiceState.namingNoMicMode = value;
  bool get micOn => voiceState.micOn;
  set micOn(bool value) => voiceState.micOn = value;
  int get micStage => voiceState.micStage;
  set micStage(int value) => voiceState.micStage = value;
  bool get namingPaused => voiceState.namingPaused;
  set namingPaused(bool value) => voiceState.namingPaused = value;
  late AnimationController micController;
  final List<bool> lastTenResults =
      []; // letzte 10 Spieler-Ergebnisse (true = korrekt)

  String lang = 'de';
  HintPack? hintPack;
  int hintLoadToken = 0;
  String? hintRevealedUuid;
  final GlobalKey _hintPanelKey = GlobalKey();
  List<CurriculumEntry> curriculum = [];
  int curriculumStartOffset = 0; // Delta-Cursor aus user_curriculum
  final TrialBuffer trialBuffer = TrialBuffer();
  final Map<String, ItemData> itemByUuid = {};
  late HexagonController ladderController;
  HexagonState get ladder => ladderController.state;
  List<ItemData> get items => trialBuffer.items;
  List<Trial> get trials => trialBuffer.trials;
  Set<String> get loadedUuids => trialBuffer.loadedUuids;
  Trial? currentTrial;
  Trial? _lastDisplayTrial;
  bool _namingTransition = false;
  bool _namingStartPending = false;
  Timer? _namingStartAutoTimer;
  PresentationSlot currentSlot = const PresentationSlot(
      mode: PresentationMode.comprehension, targetUuid: '');
  PresentationSlot? pendingNextSlot;
  String? _lastAnsweredCursorUuid;
  String? _lastNonRefillerCursorUuid;
  final RefillerStore refillerStore = RefillerStore();
  final List<String> loadErrors = [];
  int trialIndex = 0;
  bool loading = true;
  bool batchLoading = false;
  String? error;
  bool hasAnswered = false;
  bool? lastCorrect;
  bool? lastSelectionIsLeft;
  Timer? nativeSelectTimer;
  static const Duration _openingPanelAutoProceedDelay = Duration(seconds: 8);
  bool _showTapPrimerPanel = false;
  bool _tapPrimerConsumed = false;
  final Map<String, int> correctCounts = {};
  final Map<String, int> audioPlayCounts = {};
  final Map<String, int> audioMaxSequenceIndex = {};
  final Map<String, int> audioMinSequenceIndex = {};
  final Map<String, bool> audioUrlOkCache = {};
  final Map<String, int> _imageVariantCursorByUuid = {};

  bool get _namingSessionBusy => namingInProgress || _namingStartPending;

  int currentTrialAudioToken = -1;
  String? currentTrialAudioUuid;
  Uri? currentTrialAudioUri;
  final ItemPresentationPolicy presentationPolicy = ItemPresentationPolicy(
    config: presentationConfigForDepth(manualTrainingDepthMode),
  );
  TrainingDepthMode trainingDepthMode = manualTrainingDepthMode;
  final ItemStatsTracker itemStats = ItemStatsTracker();
  final List<bool> comprehensionHistory = [];
  final List<bool> namingHistory = [];
  final Set<String> comprehensionSeen = {};
  int selectionEpoch = 0; // bleibt für 2AFC erhalten
  int currentTrialToken =
      0; // entwertet alle asynchronen Tasks beim Trialwechsel/Hold
  bool sessionReady = false;
  late final EventLogger logger;
  late final PresentationProtocolLog protocolLog;
  bool loggerReady = false;
  DateTime? sessionStart;
  int dashboardViewCount =
      0; // zählt Dashboard-Opens, steuert Rival-Variante (alle 100 Wechsel)
  bool showRestartSplash =
      false; // Startbildschirm nur beim Wiederstart, nicht beim ersten Start
  bool sessionEnded = false;
  bool _mountainCelebrationActive = false;
  _MountainCelebrationResumeAction _mountainCelebrationResumeAction =
      _MountainCelebrationResumeAction.none;
  String _mountainThemeDayKey = '';
  int _mountainThemeIndex = 0;
  bool? _mountainWinnerIsYou;
  Timer? _mountainThemeAdvanceTimer;
  Timer? _mountainCelebrationTimer;
  final Map<String, int> nativeSeenCounts =
      {}; // wie oft Ziel-Item angezeigt wurde
  final Map<String, int> phoneticSeenCounts =
      {}; // wie oft Items mit Lautschrift gezeigt wurden
  int phoneticGlobalOverrideRemaining = 0; // aktive Phonetik-Zeichen global
  bool phoneticForceHiddenByToggle = false;
  int lastCloudLoadToken = 0;
  final NamingLocaleHelper namingLocaleHelper = NamingLocaleHelper();
  RestartModuleProgress restartModuleProgress = RestartModuleProgress(
    iconAsset: startCurriculumIcons[defaultStartCurriculum] ??
        'assets/icons/cross.webp',
    completed: 0,
    total: 0,
  );
  int _restartPanelInfoRequest = 0;
  bool _lifecyclePersisting = false;
  bool _historyPanelHasSupervisorInfo = false;
  bool _historyPanelOpenFromQuery = false;
  bool _historyPanelOpenScheduledFromQuery = false;
  bool _historyPanelQueryDialogClosed = false;
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'AppKeyboard');
  bool _micControllerDisposed = false;
  bool _updateCheckStarted = false;
  bool _updateDialogShown = false;
  AppUpdateInfo? _availableAppUpdate;
  String _installedVersionLabel = '';
  bool _resumeMicRecheckInFlight = false;
  List<String> _resumeSelectedFeedbackIds = const [];
  bool _resumeEmojiAckInFlight = false;
  bool _resumeEmojiAckPending = false;
  Timer? _resumeEmojiAckRetryTimer;
  DateTime? _resumeEmojiAckRetryNotBeforeUtc;
  int _resumeEmojiAckRetryAttempt = 0;

  List<String> _preferredInstructionLanguageCodes() {
    final codes = <String>[];
    final l1 = nativeLang?.trim() ?? '';
    final l2 = lang.trim();
    if (l1.isNotEmpty) {
      codes.add(HintsService.normalizeLangCode(l1));
    }
    if (l2.isNotEmpty) {
      final normalizedL2 = HintsService.normalizeLangCode(l2);
      if (!codes.contains(normalizedL2)) {
        codes.add(normalizedL2);
      }
    }
    return codes;
  }

  String _resolveLocalizedText(
    Map<String, Map<String, String>> catalog,
    String key, {
    required String missingFallback,
  }) {
    final values = catalog[key];
    if (values == null) return missingFallback;
    for (final code in _preferredInstructionLanguageCodes()) {
      final match = values[code];
      if (match != null && match.isNotEmpty) {
        return match;
      }
    }
    return values['en'] ?? missingFallback;
  }

  String _noMicNamingText(String key) {
    return _resolveLocalizedText(
      _noMicNamingTexts,
      key,
      missingFallback: '',
    );
  }

  String _instructionText(String key) {
    return _resolveLocalizedText(
      _namingInstructionTexts,
      key,
      missingFallback: key,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(handleInactivityBadgeOnAppResumed());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
    logger = EventLogger();
    protocolLog = PresentationProtocolLog();
    namingController = NamingController(
      speech: speech,
      onError: _handleSpeechError,
      onStatus: (s) => debugPrint('[asr][status] $s'),
    );
    playbackEngine = createPlaybackEngine(
      speechContext: speechAudioContext,
      hintContext: speechAudioContext,
      onLog: (message) => debugPrint(message),
    );
    unawaited(playbackEngine.init());
    unawaited(fanfarePlayer.setAudioContext(sfxAudioContext));
    moveYouPlayer.setReleaseMode(ReleaseMode.stop);
    moveRivalPlayer.setReleaseMode(ReleaseMode.stop);
    unawaited(moveYouPlayer.setAudioContext(sfxAudioContext));
    unawaited(moveRivalPlayer.setAudioContext(sfxAudioContext));
    unawaited(moveYouPlayer.setPlayerMode(PlayerMode.lowLatency));
    unawaited(moveRivalPlayer.setPlayerMode(PlayerMode.lowLatency));
    unawaited(moveYouPlayer.setVolume(moveSoundVolume));
    unawaited(moveRivalPlayer.setVolume(moveSoundVolume));
    namingBeepPlayer.setReleaseMode(ReleaseMode.stop);
    namingBeepPlayer2.setReleaseMode(ReleaseMode.stop);
    unawaited(namingBeepPlayer.setAudioContext(sfxAudioContext));
    unawaited(namingBeepPlayer2.setAudioContext(sfxAudioContext));
    unawaited(namingBeepPlayer.setPlayerMode(PlayerMode.lowLatency));
    unawaited(namingBeepPlayer2.setPlayerMode(PlayerMode.lowLatency));
    unawaited(namingBeepPlayer.setVolume(namingBeepVolume));
    unawaited(namingBeepPlayer2.setVolume(namingBeepVolume));
    micController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    voiceController = VoiceController(
      speech: speech,
      namingController: namingController,
      micController: micController,
      state: voiceState,
      onStateChanged: () {
        if (_disposed || !mounted) return;
        // Avoid setState during build/async mic callbacks.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_disposed || !mounted) return;
          setState(() {});
        });
      },
    );
    final int mountainStartIndex =
        (kDebugMode && debugMountainFastFinishEnabled)
            ? debugMountainStartRun
            : 0;
    ladderController = HexagonController(
      onChanged: _onLadderChanged,
      onYouWin: _handleWinYou,
      onRivalWin: _handleWinRival,
      onMove: _handleLadderMove,
      accuracyProvider: () => lastTenResults,
      startIndex: mountainStartIndex,
      winHoldDuration: mountainWinCelebrationDelay,
    );
    api = ApiClient(
      workerHost: workerHost,
      fileHost: fileHost,
      apiPrefix: apiPrefix,
    );
    pickManifestService = PickManifestService(api: api);
    userCurriculumService =
        UserCurriculumService(workerHost: workerHost, apiPrefix: apiPrefix);
    hintsService = HintsService(workerHost: workerHost, apiPrefix: apiPrefix);
    resumeStateService =
        ResumeStateService(workerHost: workerHost, apiPrefix: apiPrefix);
    supervisorDashboardService = SupervisorDashboardService(
        workerHost: workerHost, apiPrefix: apiPrefix);
    supervisorLinkService =
        SupervisorLinkService(workerHost: workerHost, apiPrefix: apiPrefix);
    appUpdateService =
        AppUpdateService(workerHost: workerHost, apiPrefix: apiPrefix);
    resumeStateController = ResumeStateController(service: resumeStateService);
    _initLogger();
    _initUserId();
    _historyPanelHasSupervisorInfo = historyPanelHasSupervisorInfo();
    unawaited(_restoreHistoryPanelDraft());
    if (!_startDirectTrainingFromQuery()) {
      _loadSavedOnboarding();
    }
    unawaited(_loadMountainThemeCycle());
    unawaited(_checkForAppUpdateAtStartup());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistProgressSnapshot());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(handleInactivityBadgeOnAppResumed());
      unawaited(_recheckMicPermissionAfterResume());
      unawaited(_loadMountainThemeCycle());
    }
  }

  Future<void> _recheckMicPermissionAfterResume() async {
    if (_resumeMicRecheckInFlight || !mounted) return;
    final shouldCheck = namingNoMicMode ||
        micDenied ||
        micPermanentlyDenied ||
        speechPermanentlyDenied;
    if (!shouldCheck) return;
    _resumeMicRecheckInFlight = true;
    try {
      final wasNoMicMode = namingNoMicMode;
      final ready = await voiceController.ensureMicReady(forceRecheck: true);
      if (!mounted) return;
      if (ready && wasNoMicMode) {
        protocolLog.addNote(
            'Naming no-mic mode disabled: token=$currentTrialToken reason=app_resumed_mic_ready');
      }
      setState(() {
        micDenied = !ready;
        micPermanentlyDenied = voiceState.micPermanentlyDenied;
        speechPermanentlyDenied = voiceState.speechPermanentlyDenied;
        if (ready) {
          namingNoMicMode = false;
          namingHold = false;
          namingStatus = '';
        }
      });
    } finally {
      _resumeMicRecheckInFlight = false;
    }
  }

  Future<void> _initLogger() async {
    try {
      await logger.init();
      loggerReady = true;
      _configureLoggerRemote();
    } catch (_) {
      loggerReady = false;
    }
  }

  Future<void> _initUserId() async {
    try {
      final requestedId = _userIdFromQuery();
      final id = requestedId ?? await userIdentity.loadOrCreate();
      if (requestedId != null) {
        await userIdentity.save(requestedId);
      }
      if (!mounted) return;
      setState(() {
        userId = id;
      });
      await preloadHistoryPanelDraft(userId: id);
      await refreshHistoryPanelConsentFromServer(
        userId: id,
        supervisorDashboardService: supervisorDashboardService,
      );
      _refreshHistoryPanelIndicator();
      if (!enableRemoteUserDelta) {
        unawaited(userDeltaStore.delete(id));
      }
      unawaited(protocolLog.setUserId(id));
      _configureLoggerRemote();
      if (showRestartSplash) {
        unawaited(_updateRestartModuleProgress());
      }
      unawaited(_loadResumeStateFallback());
    } catch (e) {
      debugPrint('[user-identity][init][error] $e');
    }
  }

  String? _userIdFromQuery() {
    final params = _launchQueryParameters();
    final raw = (params['user_id'] ??
            params['learner_id'] ??
            params['uid'] ??
            params['participant_id'] ??
            '')
        .trim();
    if (raw.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9._:-]{6,96}$').hasMatch(raw)) return null;
    return raw;
  }

  Future<void> _restoreHistoryPanelDraft() async {
    final uid = userId?.trim() ?? '';
    if (uid.isEmpty) return;
    await preloadHistoryPanelDraft(userId: uid);
    await refreshHistoryPanelConsentFromServer(
      userId: uid,
      supervisorDashboardService: supervisorDashboardService,
    );
    _refreshHistoryPanelIndicator();
  }

  void _refreshHistoryPanelIndicator() {
    final hasInfo = historyPanelHasSupervisorInfo();
    if (!mounted) {
      _historyPanelHasSupervisorInfo = hasInfo;
      return;
    }
    if (_historyPanelHasSupervisorInfo == hasInfo) return;
    setState(() {
      _historyPanelHasSupervisorInfo = hasInfo;
    });
  }

  void _configureLoggerRemote() {
    if (!loggerReady) return;
    if (!enableRemoteLogUpload) return;
    if (userId == null || userId!.isEmpty) return;
    logger.configureRemote(
      userId: userId!,
      workerHost: workerHost,
      apiPrefix: apiPrefix,
    );
    logger.setSessionContext(
      startKey: activeStartCurriculumKey,
      lang: lang,
      nativeLang: nativeLang,
    );
  }

  Future<void> _checkForAppUpdateAtStartup() async {
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;
    if (kIsWeb || operatingSystem != 'android') return;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(packageInfo.buildNumber.trim());
      _installedVersionLabel =
          '${packageInfo.version.trim()} (${packageInfo.buildNumber.trim()})';
      final info = await appUpdateService.checkForAndroidUpdate(
        localVersionCode: localCode,
        localVersionName: packageInfo.version,
      );
      if (!mounted || info == null) return;
      setState(() {
        _availableAppUpdate = info;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_showUpdateDialogIfNeeded());
      });
    } catch (e) {
      debugPrint('[update][check-error] $e');
    }
  }

  Future<void> _showUpdateDialogIfNeeded() async {
    final info = _availableAppUpdate;
    if (info == null || _updateDialogShown || !mounted) return;
    _updateDialogShown = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update verfügbar'),
        content: Text(
          'Installiert: ${_installedVersionLabel.isEmpty ? "-" : _installedVersionLabel}\n'
          'Neu: ${info.versionLabel}\n\n'
          'Möchtest du die neue APK herunterladen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Später'),
          ),
          ElevatedButton(
            onPressed: () async {
              final uri = Uri.tryParse(info.downloadUrl);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.platformDefault);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Herunterladen'),
          ),
        ],
      ),
    );
  }

  void _onLadderChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String get _activeMountainTheme {
    if (kMountainThemeOrder.isEmpty) return 'default';
    final safe = _mountainThemeIndex % kMountainThemeOrder.length;
    final idx = safe < 0 ? safe + kMountainThemeOrder.length : safe;
    return kMountainThemeOrder[idx];
  }

  Future<void> _loadMountainThemeCycle() async {
    final snapshot = await mountainThemeCycleStore.loadForToday();
    if (!mounted) return;
    setState(() {
      _mountainThemeDayKey = snapshot.dayKey;
      _mountainThemeIndex = snapshot.themeIndex;
      _mountainWinnerIsYou = null;
    });
  }

  void _queueMountainThemeAdvance({required bool winnerIsYou}) {
    final todayKey = mountainDayKey(DateTime.now());
    if (_mountainThemeDayKey != todayKey) {
      _mountainThemeDayKey = todayKey;
      _mountainThemeIndex = 0;
    }
    _mountainThemeAdvanceTimer?.cancel();
    setState(() {
      _mountainWinnerIsYou = winnerIsYou;
    });
    _mountainThemeAdvanceTimer = Timer(mountainWinCelebrationDelay, () {
      if (!mounted) return;
      final today = mountainDayKey(DateTime.now());
      final next = (_mountainThemeIndex + 1) % kMountainThemeOrder.length;
      setState(() {
        _mountainThemeDayKey = today;
        _mountainThemeIndex = next;
        _mountainWinnerIsYou = null;
      });
      unawaited(
        mountainThemeCycleStore.saveForToday(dayKey: today, themeIndex: next),
      );
    });
  }

  void _handleWinYou() {
    _startMountainCelebration(winnerIsYou: true);
  }

  void _handleWinRival() {
    _startMountainCelebration(winnerIsYou: false);
  }

  void _startMountainCelebration({required bool winnerIsYou}) {
    if (loggerReady) {
      unawaited(logger
          .log('win', {'side': winnerIsYou ? 'you' : 'rival', 'lang': lang}));
    }
    _mountainCelebrationTimer?.cancel();
    setState(() {
      _mountainCelebrationActive = true;
    });
    unawaited(_playFanfare());
    _saveOnboardingSnapshot();
    _queueMountainThemeAdvance(winnerIsYou: winnerIsYou);
    _mountainCelebrationTimer = Timer(mountainWinCelebrationDelay, () {
      if (!mounted) return;
      final resumeAction = _mountainCelebrationResumeAction;
      setState(() {
        _mountainCelebrationActive = false;
        _mountainCelebrationResumeAction =
            _MountainCelebrationResumeAction.none;
      });
      switch (resumeAction) {
        case _MountainCelebrationResumeAction.none:
          break;
        case _MountainCelebrationResumeAction.nextTrial:
          _gotoNextTrial();
          break;
        case _MountainCelebrationResumeAction.advanceNaming:
          _advanceAfterNamingAttempt();
          break;
      }
    });
  }

  void _queueResumeAfterMountainCelebration(
      _MountainCelebrationResumeAction action) {
    if (!_mountainCelebrationActive) return;
    if (action == _MountainCelebrationResumeAction.advanceNaming ||
        _mountainCelebrationResumeAction ==
            _MountainCelebrationResumeAction.none) {
      _mountainCelebrationResumeAction = action;
    }
  }

  void _clearMountainCelebrationState() {
    _mountainCelebrationTimer?.cancel();
    _mountainCelebrationTimer = null;
    _mountainCelebrationResumeAction = _MountainCelebrationResumeAction.none;
    _mountainCelebrationActive = false;
    _mountainWinnerIsYou = null;
  }

  Map<String, String> _launchQueryParameters() {
    final out = Map<String, String>.from(Uri.base.queryParameters);
    final fragment = Uri.base.fragment.trim();
    if (fragment.isEmpty) return out;
    final normalized = fragment.startsWith('/') ? fragment : '/$fragment';
    final parsed = Uri.tryParse(normalized);
    if (parsed == null) return out;
    out.addAll(parsed.queryParameters);
    return out;
  }

  bool _historyPanelRequestedByQuery() {
    final params = _launchQueryParameters();
    final open = params['open']?.trim().toLowerCase();
    final panel = params['panel']?.trim().toLowerCase();
    final target = open?.isNotEmpty == true ? open : panel;
    const supervisorRegistrationTargets = {
      'consent',
      'history',
      'learner-consent',
      'learner_consent',
      'progress',
      'supervision',
      'supervisor-registration',
      'supervisor_registration',
      'supervisor-register',
      'supervisor_register',
      'supervisor',
    };
    return supervisorRegistrationTargets.contains(target);
  }

  void _scheduleOpenHistoryPanelFromQueryIfRequested() {
    if (_historyPanelOpenFromQuery || _historyPanelOpenScheduledFromQuery) {
      return;
    }
    if (!_historyPanelRequestedByQuery()) return;
    _historyPanelOpenScheduledFromQuery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyPanelOpenScheduledFromQuery = false;
      if (!mounted || _disposed || _historyPanelOpenFromQuery) return;
      _historyPanelOpenFromQuery = true;
      unawaited(() async {
        await _openHistoryPanel();
        if (!mounted || _disposed) return;
        setState(() {
          _historyPanelQueryDialogClosed = true;
        });
      }());
    });
  }

  Future<void> _openHistoryPanel() async {
    await showHistoryPanel(
      context: context,
      userId: userId,
      targetLang: lang,
      nativeLang: nativeLang,
      resumeState: resumeStateController.state,
      resumeStateService: resumeStateService,
      supervisorDashboardService: supervisorDashboardService,
      supervisorLinkService: supervisorLinkService,
      hintLoader: historyHintLoader,
      onApplyUserId: (id, state) async {
        await userIdentity.save(id);
        setState(() {
          userId = id;
          resumeStateController.setState(
              (state != null && state.entries.isNotEmpty) ? state : null);
        });
        unawaited(protocolLog.setUserId(id));
        _configureLoggerRemote();
      },
      onRemoveUserId: () async {
        await userIdentity.clear();
        final newId = await userIdentity.loadOrCreate();
        if (!mounted) return;
        setState(() {
          userId = newId;
          resumeStateController.setState(null);
        });
        unawaited(protocolLog.setUserId(newId));
        _configureLoggerRemote();
        await onboardingStore.clear();
        await sessionCacheStore.clear();
        _exitToOpeningPanel();
      },
    );
    await refreshHistoryPanelConsentFromServer(
      userId: userId,
      supervisorDashboardService: supervisorDashboardService,
    );
    _refreshHistoryPanelIndicator();
  }

  Future<void> _loadSavedOnboarding() async {
    final saved = await onboardingStore.load();
    if (!mounted || saved == null) return;
    setState(() {
      lang = saved.lang;
      activeStartCurriculumKey = sanitizeStartCurriculum(saved.startKey);
      nativeLang = saved.nativeLang;
      lastModuleRowId = saved.lastModuleRowId;
      lastModuleMode = _dailywordsModuleModeFromName(saved.lastModuleMode);
      _tapPrimerConsumed = saved.tapPrimerSeen;
      awaitingLang = false;
      awaitingStart = false;
      awaitingNative = false;
      showRestartSplash = true;
      loading = false;
      error = null;
    });
    unawaited(_loadHintPack());
    ladderController.setWins(you: saved.winsYou, rival: saved.winsRival);
    await _loadLastSessionWins();
    unawaited(_updateRestartModuleProgress());
  }

  DailywordsModuleMode? _dailywordsModuleModeFromName(String? value) {
    if (value == DailywordsModuleMode.training.name) {
      return DailywordsModuleMode.training;
    }
    if (value == DailywordsModuleMode.dialog.name) {
      return DailywordsModuleMode.dialog;
    }
    return null;
  }

  Future<void> _loadResumeStateFallback() async {
    final uid = userId;
    if (uid == null || uid.isEmpty) return;
    final state = await resumeStateController.fetchAndSet(uid);
    if (state == null || state.entries.isEmpty) return;
    final latest = state.mostRecentEntry();
    if (latest == null) return;
    if (!mounted) return;
    if (!awaitingLang || showRestartSplash) return;
    final cache = await sessionCacheStore.load();
    if (cache != null) return;
    if (!mounted) return;
    final fallbackWinsYou = latest.winsYou ?? 0;
    final fallbackWinsRival = latest.winsRival ?? 0;
    setState(() {
      lang = latest.lang;
      nativeLang = latest.nativeLang;
      activeStartCurriculumKey = sanitizeStartCurriculum(latest.startKey);
      awaitingLang = false;
      awaitingStart = false;
      awaitingNative = false;
      showRestartSplash = true;
      loading = false;
      error = null;
    });
    unawaited(_loadHintPack());
    ladderController.setWins(you: fallbackWinsYou, rival: fallbackWinsRival);
    _saveOnboardingSnapshot(startKey: sanitizeStartCurriculum(latest.startKey));
    await _loadLastSessionWins();
    unawaited(_updateRestartModuleProgress());
  }

  bool _startDirectTrainingFromQuery() {
    final params = _launchQueryParameters();
    final directRequested = params['direct'] == '1' ||
        params['skip_resume'] == '1' ||
        params['resume'] == '0' ||
        params['mode']?.trim().toLowerCase() == '2afc';
    if (!directRequested) return false;

    final requestedStart = _directStartCurriculumFromQuery(params);
    if (requestedStart == null) return false;

    final requestedLang = _normalizeSupportedLanguageCode(params['l2']) ??
        _normalizeSupportedLanguageCode(params['lang']) ??
        _normalizeSupportedLanguageCode(params['locale']) ??
        lang;
    final requestedNativeLang =
        _normalizeSupportedLanguageCode(params['l1']) ?? requestedLang;
    final requestedTrainingDepth = _trainingDepthModeFromQuery(params);

    lang = requestedLang;
    nativeLang = requestedNativeLang;
    if (requestedTrainingDepth != null) {
      trainingDepthMode = requestedTrainingDepth;
      presentationPolicy.updateConfig(
        presentationConfigForDepth(requestedTrainingDepth),
      );
    }
    activeStartCurriculumKey = requestedStart;
    awaitingLang = false;
    awaitingStart = false;
    awaitingNative = false;
    showRestartSplash = false;
    loading = true;
    error = null;
    lastModuleMode = DailywordsModuleMode.training;
    lastModuleRowId ??= _moduleRowIdForStart(requestedStart);
    unawaited(_loadInitial(
      startKey: requestedStart,
      showTapPrimer: false,
      preferLanguageSpecificStart: false,
      initialDownloadLimit: 2,
      ignoreSavedCursor: true,
    ));
    return true;
  }

  TrainingDepthMode? _trainingDepthModeFromQuery(Map<String, String> params) {
    final raw = (params['intensity'] ??
            params['training_depth'] ??
            params['depth'] ??
            '')
        .trim()
        .toLowerCase();
    switch (raw) {
      case 'default':
      case 'defaultmode':
      case 'default_mode':
        return TrainingDepthMode.defaultMode;
      case 'deep':
      case 'deeper':
        return TrainingDepthMode.deep;
    }
    return null;
  }

  String? _directStartCurriculumFromQuery(Map<String, String> params) {
    for (final key in const ['start', 'module', 'curriculum']) {
      final raw = params[key]?.trim();
      if (raw == null || raw.isEmpty || raw.toLowerCase() == '2afc') {
        continue;
      }
      return sanitizeStartCurriculum(raw);
    }
    switch (params['pack']?.trim().toLowerCase()) {
      case 'cafe':
        return sanitizeStartCurriculum('start_curriculum_realtalk_cafe.json');
      case 'toddler':
      case 'first_words':
        return sanitizeStartCurriculum('start_curriculum_b.json');
      case 'bergstube':
      case 'bergstube_peter':
      case 'peter':
        return sanitizeStartCurriculum('start_curriculum_t.json');
      case 'taverna':
      case 'taverna_lara':
      case 'lara':
        return sanitizeStartCurriculum('start_curriculum_l.json');
      case 'therapeutin':
      case 'dailywords':
      case 'daily_words':
        return sanitizeStartCurriculum('start_curriculum_a.json');
    }
    return null;
  }

  String _moduleRowIdForStart(String startKey) {
    switch (sanitizeStartCurriculum(startKey).trim().toLowerCase()) {
      case 'start_curriculum_realtalk_cafe.json':
        return 'cafe';
      case 'start_curriculum_t.json':
        return 'peter';
      case 'start_curriculum_l.json':
        return 'lara';
      case 'start_curriculum_b.json':
        return 'first_words';
      case 'start_curriculum_a.json':
      default:
        return 'dailywords';
    }
  }

  Future<void> _persistProgressSnapshot({bool skipRemoteFetch = false}) async {
    if (_lifecyclePersisting) return;
    _lifecyclePersisting = true;
    try {
      await _pushResumeState(fetchExistingResume: !skipRemoteFetch);
      await _persistUserCursor();
      await _persistRefillerQueue();
    } finally {
      _lifecyclePersisting = false;
    }
  }

  Future<void> _loadHintPack({bool forceRefresh = false}) async {
    final l1 = nativeLang;
    if (l1 == null || l1.isEmpty) {
      if (hintPack != null) {
        setState(() {
          hintPack = null;
        });
      }
      return;
    }
    final token = ++hintLoadToken;
    final pack = await hintsService.loadPack(
      l1: l1,
      l2: lang,
      forceRefresh: forceRefresh,
    );
    if (!mounted || token != hintLoadToken) return;
    setState(() {
      hintPack = pack;
    });
    if (pack != null &&
        currentTrial != null &&
        hintRevealedUuid == currentTrial!.target.uuid) {
      final normL2 = HintsService.normalizeLangCode(lang);
      final hintIds =
          currentTrial!.target.hintRefsByLang[normL2] ?? const <String>[];
      if (hintIds.isNotEmpty && pack.hintsForIds(hintIds).isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollHintPanelIntoView();
        });
      }
    }
  }

  void _toggleHintsForCurrent() {
    if (currentTrial == null) return;
    final uuid = currentTrial!.target.uuid;
    final bool shouldReveal = hintRevealedUuid != uuid;
    setState(() {
      hintRevealedUuid = shouldReveal ? uuid : null;
    });
    if (shouldReveal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollHintPanelIntoView();
      });
    }
    if (hintPack != null) {
      final l1 = HintsService.normalizeLangCode(nativeLang);
      final l2 = HintsService.normalizeLangCode(lang);
      final hintIds =
          currentTrial!.target.hintRefsByLang[l2] ?? const <String>[];
      final resolved = hintPack!.hintsForIds(hintIds).length;
      debugPrint(
          '[hints][item] uuid=$uuid l1=$l1 l2=$l2 ids=${hintIds.length} resolved=$resolved');
    }
  }

  void _selectTrainingDepthMode(TrainingDepthMode mode) {
    if (trainingDepthMode == mode) return;
    setState(() {
      trainingDepthMode = mode;
    });
    presentationPolicy.updateConfig(presentationConfigForDepth(mode));
  }

  void _scrollHintPanelIntoView() {
    final ctx = _hintPanelKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0.2,
    );
  }

  Future<void> _restartOnboarding() async {
    await onboardingStore.clear();
    await sessionCacheStore.clear();
    if (userId != null && userId!.isNotEmpty) {
      if (enableRemoteUserDelta) {
        final resetDelta = UserCurriculumDelta(cursor: -1);
        unawaited(userDeltaStore.save(userId!, resetDelta));
        unawaited(userCurriculumService.pushDelta(
            userId: userId!,
            startKey: activeStartCurriculumKey ?? defaultStartCurriculum,
            delta: resetDelta));
      } else {
        unawaited(userDeltaStore.delete(userId!));
      }
    }
    setState(() {
      _tapPrimerConsumed = false;
      awaitingLang = true;
      awaitingStart = false;
      awaitingNative = false;
      showRestartSplash = false;
      loading = false;
      error = null;
      resetCursorOnNextLoad = true;
      userDelta = null;
      curriculumStartOffset = 0;
      curriculum.clear();
      trialBuffer.reset();
      itemByUuid.clear();
      trialIndex = 0;
      currentTrial = null;
      _lastDisplayTrial = null;
      _namingTransition = false;
      currentSlot = const PresentationSlot(
          mode: PresentationMode.comprehension, targetUuid: '');
      pendingNextSlot = null;
      presentationPolicy.reset();
    });
  }

  Future<void> _startFromSplash() async {
    final restored = await _restoreFromCache();
    if (restored) {
      return;
    }
    setState(() {
      showRestartSplash = false;
    });
    await _loadInitial();
  }

  void _openModuleSelectorFromResume() {
    setState(() {
      showRestartSplash = false;
      awaitingLang = false;
      awaitingStart = true;
      awaitingNative = false;
      awaitingPickNative = false;
      pickFlowActive = false;
      pickListLoading = false;
      pickListError = null;
    });
  }

  Future<void> _updateRestartModuleProgress() async {
    if (!showRestartSplash) return;
    final int requestId = ++_restartPanelInfoRequest;
    final startKey = activeStartCurriculumKey ?? defaultStartCurriculum;
    final iconAsset = _moduleIconForStart(startKey);
    final metadata = await _fetchRestartCurriculumMetadata(startKey);
    final cursor = await _loadRestartCursor();
    final int completed = metadata.totalItems > 0
        ? (cursor ?? 0).clamp(0, metadata.totalItems)
        : 0;
    final int total = metadata.totalItems;
    if (!mounted ||
        requestId != _restartPanelInfoRequest ||
        !showRestartSplash) {
      return;
    }
    setState(() {
      restartModuleProgress = RestartModuleProgress(
        iconAsset: iconAsset,
        completed: completed,
        total: total,
      );
    });
  }

  Future<int?> _loadRestartCursor() async {
    final uid = userId;
    if (uid == null || uid.isEmpty) return null;
    final startKey = activeStartCurriculumKey ?? defaultStartCurriculum;
    var entry = resumeStateController.entryForStartKey(startKey);
    if (entry == null || entry.cursor < 0) {
      final fetched = await resumeStateController.fetchAndSet(uid);
      entry = fetched?.entryForStartKey(startKey);
    }
    if (entry == null || entry.cursor < 0) return null;
    return entry.cursor;
  }

  Future<void> _initializePresentationPolicy({
    int? fallbackCursorIndex,
    bool showTapPrimer = false,
    bool ignoreSavedCursor = false,
  }) async {
    final startKey = activeStartCurriculumKey ?? defaultStartCurriculum;
    final List<String> curriculumUuids = (curriculum.isNotEmpty)
        ? curriculum.map((e) => e.uuid).toList(growable: false)
        : items.map((e) => e.uuid).toList(growable: false);
    if (curriculumUuids.isEmpty) return;

    final uid = userId;
    final refiller = (uid != null && uid.isNotEmpty)
        ? await refillerStore.load(userId: uid, startKey: startKey, lang: lang)
        : RefillerState(queue: const []);

    final cursorIndex = ignoreSavedCursor
        ? (fallbackCursorIndex ?? 0)
        : await resolveCursorIndex(
              startKey: startKey,
              lang: lang,
              curriculumUuids: curriculumUuids,
              userId: userId,
              nativeLang: nativeLang,
              deltaCursor: userDelta?.cursor,
              resumeStateController: resumeStateController,
            ) ??
            fallbackCursorIndex ??
            0;

    final startIndex = max(0, cursorIndex - 5);
    presentationPolicy.initializeComprehensionBlock(
      curriculumUuids: curriculumUuids,
      startIndex: startIndex,
      refillerQueue: refiller.queue,
    );
    final int idxInBlock = (cursorIndex - startIndex).clamp(
        0, max(0, presentationPolicy.comprehensionBlockUuids.length - 1));
    presentationPolicy.setComprehensionIndex(idxInBlock);

    final slot = presentationPolicy.currentSlot;
    if (slot.targetUuid.isEmpty) return;
    _showTapPrimerPanel = showTapPrimer && !_tapPrimerConsumed;
    await _applySlot(slot, advanceToken: false);
  }

  Future<void> _dismissTapPrimer({required bool primeAudio}) async {
    if (!_showTapPrimerPanel) return;
    final token = currentTrialToken;
    if (primeAudio) {
      await _primeAudioForUserGestureAsync('tap-primer');
    }
    if (!mounted || token != currentTrialToken) return;
    setState(() {
      _showTapPrimerPanel = false;
      _tapPrimerConsumed = true;
    });
    _saveOnboardingSnapshot();
    await _startTrial(token);
  }

  Future<_RestartCurriculumMetadata> _fetchRestartCurriculumMetadata(
      String startKey) async {
    try {
      final data = await api.loadStartCurriculumJson(
        startKey,
        allowDefaultFallback: true,
      );
      List items = (data['items'] as List?) ?? [];
      if (items.isEmpty && data['item_order'] is List) {
        items = data['item_order'] as List;
      }
      final total = items.length;
      return _RestartCurriculumMetadata(totalItems: total);
    } catch (e) {
      debugPrint('[restart][curriculum-info] $e');
      return const _RestartCurriculumMetadata(totalItems: 0);
    }
  }

  String _moduleIconForStart(String startKey) {
    return startCurriculumIcons[startKey] ??
        startCurriculumIcons[defaultStartCurriculum] ??
        'assets/icons/cross.webp';
  }

  Future<bool> _restoreFromCache() async {
    final restored = await readSessionCache(sessionCacheStore);
    if (restored == null) return false;
    try {
      itemByUuid.clear();
      trialBuffer.replaceAll(restored.items);
      for (final it in restored.items) {
        itemByUuid[it.uuid] = it;
      }
      ladderController.reset(clearWins: false);
      setState(() {
        lang = restored.lang;
        activeStartCurriculumKey = sanitizeStartCurriculum(restored.startKey);
        nativeLang = restored.nativeLang;
        currentTrial = null;
        _lastDisplayTrial = null;
        _namingTransition = false;
        currentSlot = const PresentationSlot(
            mode: PresentationMode.comprehension, targetUuid: '');
        pendingNextSlot = null;
        showRestartSplash = false;
        awaitingLang = false;
        awaitingStart = false;
        awaitingNative = false;
        loading = false;
        error = null;
        sessionEnded = false;
        currentTrialToken++;
        hasAnswered = false;
        lastCorrect = null;
        lastSelectionIsLeft = null;
        presentationPolicy.reset();
        _lastAnsweredCursorUuid = restored.savedUuid;
        _lastNonRefillerCursorUuid = restored.savedUuid;
        namingInProgress = false;
        namingHold = false;
        namingNoMicMode = false;
        micOn = false;
        micStage = -1;
        _imageVariantCursorByUuid.clear();
      });
      sessionStart = DateTime.now().toUtc();
      unawaited(protocolLog.startSession(sessionStart!,
          userId: userId, nativeLang: nativeLang));
      logger.setSessionContext(
          startKey: activeStartCurriculumKey,
          lang: lang,
          nativeLang: nativeLang);
      _configureLoggerRemote();
      if (loggerReady) {
        unawaited(logger.startSession(lang: lang));
      }
      await _updateRivalIdleDays();
      await _ensureCurriculumLoaded();
      int? fallbackCursorIndex;
      if (restored.savedUuid != null && curriculum.isNotEmpty) {
        final idx = curriculum.indexWhere((e) => e.uuid == restored.savedUuid);
        if (idx >= 0) fallbackCursorIndex = idx;
      }
      fallbackCursorIndex ??= restored.savedIndex;
      await _initializePresentationPolicy(
          fallbackCursorIndex: fallbackCursorIndex);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureCurriculumLoaded() async {
    if (curriculum.isNotEmpty) return;
    try {
      curriculum = await api.loadStartCurriculum(
          activeStartCurriculumKey ?? defaultStartCurriculum,
          requireCompleteForLang: lang);
      await _maybeApplyUserCurriculumDelta(
          activeStartCurriculumKey ?? defaultStartCurriculum);
    } catch (e) {
      loadErrors.add('Curriculum-Load nach Cache: $e');
    }
  }

  Future<void> _loadLastSessionWins() async {
    if (sessionStart != null) return; // already in a live session
    try {
      final storage = LogStorage();
      final lines = await storage.readLines();
      if (lines.isEmpty) return;
      final Map<String, _SessionWinSnapshot> sessions = {};
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        Map<String, dynamic> data;
        try {
          data = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        if (data['type'] != 'win') continue;
        final session = data['session'] as String? ?? 'unknown';
        final tsStr = data['ts'] as String?;
        final ts = tsStr == null ? null : DateTime.tryParse(tsStr)?.toUtc();
        if (ts == null) continue;
        final side = data['side'] as String?;
        final snap = sessions.putIfAbsent(session, () => _SessionWinSnapshot());
        snap.lastTs =
            snap.lastTs == null || ts.isAfter(snap.lastTs!) ? ts : snap.lastTs;
        if (side == 'you') snap.you++;
        if (side == 'rival') snap.rival++;
      }
      if (sessions.isEmpty) return;
      final latest = sessions.entries.reduce((a, b) {
        final aTs =
            a.value.lastTs ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc();
        final bTs =
            b.value.lastTs ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc();
        return bTs.isAfter(aTs) ? b : a;
      });
      if (!mounted) return;
      final int mergedYou = max(ladder.winsYou, latest.value.you);
      final int mergedRival = max(ladder.winsRival, latest.value.rival);
      ladderController.setWins(you: mergedYou, rival: mergedRival);
      _saveOnboardingSnapshot();
    } catch (_) {
      // ignore log errors
    }
  }

  Future<void> _updateRivalIdleDays() async {
    try {
      final data = await TrainingCalendarLoader.load(
        thresholdMinutes: 5,
        idleCapSeconds: 20,
        fallbackDatesUtc: _resumeFallbackDatesUtc(),
        userId: userId,
        workerHost: workerHost,
        apiPrefix: apiPrefix,
      );
      final idleDays = data.idleDaysSince(DateTime.now().toUtc());
      ladderController.setRivalIdleDays(idleDays);
    } catch (_) {
      // ignore log errors
    }
  }

  List<DateTime>? _resumeFallbackDatesUtc() {
    final entries = resumeStateController.state?.entries;
    if (entries == null || entries.isEmpty) return null;
    return entries.map((e) => e.date).toList(growable: false);
  }

  Future<void> _openSettings() async {
    final hostCtrl = TextEditingController(text: workerHost);
    final prefixCtrl = TextEditingController(text: apiPrefix);
    try {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Worker-URL anpassen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hostCtrl,
                decoration: const InputDecoration(
                    labelText: 'Host (ohne Schema)', hintText: 'example.com'),
              ),
              TextField(
                controller: prefixCtrl,
                decoration: const InputDecoration(
                    labelText: 'API-Prefix', hintText: '/api'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, {
                'host': hostCtrl.text.trim(),
                'prefix': prefixCtrl.text.trim(),
              }),
              child: const Text('Übernehmen'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (result != null &&
          result['host'] != null &&
          result['host']!.isNotEmpty) {
        final newHost = result['host']!;
        final newPrefix =
            result['prefix']?.isNotEmpty == true ? result['prefix']! : '/api';
        final normalizedPrefix =
            newPrefix.startsWith('/') ? newPrefix : '/$newPrefix';
        setState(() {
          workerHost = newHost;
          apiPrefix = normalizedPrefix;
          api = ApiClient(
            workerHost: workerHost,
            fileHost: fileHost,
            apiPrefix: apiPrefix,
          );
          pickManifestService = PickManifestService(api: api);
          userCurriculumService = UserCurriculumService(
              workerHost: workerHost, apiPrefix: apiPrefix);
          hintsService =
              HintsService(workerHost: workerHost, apiPrefix: apiPrefix);
          resumeStateService =
              ResumeStateService(workerHost: workerHost, apiPrefix: apiPrefix);
          supervisorDashboardService = SupervisorDashboardService(
              workerHost: workerHost, apiPrefix: apiPrefix);
          resumeStateController =
              ResumeStateController(service: resumeStateService)
                ..setState(resumeStateController.state);
          supervisorLinkService = SupervisorLinkService(
              workerHost: workerHost, apiPrefix: apiPrefix);
          appUpdateService =
              AppUpdateService(workerHost: workerHost, apiPrefix: apiPrefix);
        });
        _configureLoggerRemote();
        _updateCheckStarted = false;
        _updateDialogShown = false;
        _availableAppUpdate = null;
        unawaited(_checkForAppUpdateAtStartup());
        unawaited(_loadHintPack(forceRefresh: true));
        _loadInitial();
      }
    } finally {
      hostCtrl.dispose();
      prefixCtrl.dispose();
    }
  }

  void _handleSpeechError(String code) {
    final lower = code.toLowerCase();
    if (lower.contains('no_match') ||
        lower.contains('no-match') ||
        lower.contains('speech timeout') ||
        lower.contains('speech_timeout')) {
      debugPrint('[asr][error-ignored] $code');
      return;
    }
    debugPrint('[asr][error] $code');
    if (!mounted) return;
    setState(() {
      namingStatus = 'ASR-Fehler: $code';
      _liveTranscript = 'ASR-Fehler: $code';
    });
  }

  void _primeAudioForUserGesture(String source) {
    unawaited(playbackEngine.primeForUserGesture(source: source));
  }

  Future<void> _primeAudioForUserGestureAsync(String source) async {
    try {
      await playbackEngine
          .primeForUserGesture(source: source)
          .timeout(const Duration(milliseconds: 900));
    } on TimeoutException {
      debugPrint('[audio][web-prime-timeout] source=$source');
    } catch (e) {
      debugPrint('[audio][web-prime-error] source=$source err=$e');
    }
  }

  void _handleResumeSelectedEmojiChanged(String? emojiId) {
    final normalized =
        (emojiId != null && emojiId.trim().isNotEmpty) ? emojiId.trim() : null;
    _handleResumeSelectedFeedbackIdsChanged(
      normalized == null ? const [] : [normalized],
    );
  }

  void _handleResumeSelectedFeedbackIdsChanged(List<String> feedbackIds) {
    final normalized = feedbackIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final changed = normalized.length != _resumeSelectedFeedbackIds.length ||
        !_resumeSelectedFeedbackIds.every(normalized.contains);
    if (changed) {
      _resumeEmojiAckRetryAttempt = 0;
      _resumeEmojiAckRetryNotBeforeUtc = null;
      _resumeEmojiAckRetryTimer?.cancel();
      _resumeEmojiAckRetryTimer = null;
    }
    _resumeSelectedFeedbackIds = normalized;
  }

  Duration _resumeEmojiAckBackoffDelay(int attempt) {
    final capped = attempt.clamp(0, 7);
    final seconds = 2 * (1 << capped);
    final bounded = seconds > 120 ? 120 : seconds;
    return Duration(seconds: bounded);
  }

  void _scheduleResumeEmojiAckRetry() {
    if (!_resumeEmojiAckPending || _resumeEmojiAckInFlight) return;
    _resumeEmojiAckRetryTimer?.cancel();
    final delay = _resumeEmojiAckBackoffDelay(_resumeEmojiAckRetryAttempt);
    _resumeEmojiAckRetryNotBeforeUtc = DateTime.now().toUtc().add(delay);
    _resumeEmojiAckRetryTimer = Timer(delay, () {
      _resumeEmojiAckRetryTimer = null;
      if (!mounted || !_resumeEmojiAckPending) return;
      unawaited(_ackResumeEmojiAfterFirstTrial(fromRetryTimer: true));
    });
    _resumeEmojiAckRetryAttempt += 1;
    debugPrint(
        '[supervisor-resume] ack-on-start retry scheduled attempt=$_resumeEmojiAckRetryAttempt delay=${delay.inSeconds}s');
  }

  void _resetResumeEmojiAckRetryState() {
    _resumeEmojiAckRetryTimer?.cancel();
    _resumeEmojiAckRetryTimer = null;
    _resumeEmojiAckRetryAttempt = 0;
    _resumeEmojiAckRetryNotBeforeUtc = null;
  }

  Future<void> _ackResumeEmojiAfterFirstTrial({
    bool fromRetryTimer = false,
  }) async {
    if (!_resumeEmojiAckPending || _resumeEmojiAckInFlight) return;
    final now = DateTime.now().toUtc();
    final notBefore = _resumeEmojiAckRetryNotBeforeUtc;
    if (!fromRetryTimer && notBefore != null && now.isBefore(notBefore)) {
      return;
    }
    if (!fromRetryTimer && _resumeEmojiAckRetryTimer != null) {
      _resumeEmojiAckRetryTimer?.cancel();
      _resumeEmojiAckRetryTimer = null;
    }
    final uid = (userId ?? '').trim();
    final feedbackIds = _resumeSelectedFeedbackIds
        .where((id) => id.trim().isNotEmpty)
        .toList(growable: false);
    if (uid.isEmpty || feedbackIds.isEmpty) {
      _resumeEmojiAckPending = false;
      _resetResumeEmojiAckRetryState();
      return;
    }
    _resumeEmojiAckInFlight = true;
    try {
      final ok = await supervisorDashboardService.ackEmojiQueue(
        userId: uid,
        ids: feedbackIds,
        status: 'delivered',
        remove: false,
      );
      if (ok) {
        _resumeSelectedFeedbackIds = const [];
        _resumeEmojiAckPending = false;
        _resetResumeEmojiAckRetryState();
      } else {
        debugPrint(
            '[supervisor-resume] ack-on-start failed ids=${feedbackIds.join(",")} uid=$uid');
        _scheduleResumeEmojiAckRetry();
      }
    } catch (e) {
      debugPrint(
          '[supervisor-resume] ack-on-start error ids=${feedbackIds.join(",")} uid=$uid: $e');
      _scheduleResumeEmojiAckRetry();
    } finally {
      _resumeEmojiAckInFlight = false;
    }
  }

  void _handleResumeStartGesture(String source) {
    _primeAudioForUserGesture(source);
    _resumeEmojiAckPending = true;
    _resetResumeEmojiAckRetryState();
    if (activeFlavor.id == 'dailywords') {
      _openModuleSelectorFromResume();
      return;
    }
    unawaited(_startFromSplash());
  }

  void _onSelectLang(String l) {
    _primeAudioForUserGesture('target-language-flag');
    setState(() {
      lang = l;
      awaitingLang = false;
      awaitingStart = true;
      activeStartCurriculumKey = null;
      nativeLang = activeFlavor.id == 'dailywords' ? l : null;
      lastModuleRowId ??= 'dailywords';
      lastModuleMode ??= DailywordsModuleMode.training;
      hintPack = null;
      hintRevealedUuid = null;
    });
  }

  Future<void> _onSelectDailywordsModule(DailywordsModuleChoice choice) async {
    setState(() {
      lastModuleRowId = choice.rowId;
      lastModuleMode = choice.mode;
    });

    if (choice.mode == DailywordsModuleMode.training) {
      final startKey = choice.startKey;
      if (startKey == null || startKey.trim().isEmpty) return;
      await _onSelectStart(startKey);
      return;
    }

    final uri = _buildDailywordsRealTalkUri(choice);
    if (uri != null) {
      _saveOnboardingSnapshot();
      await _openRealTalk(uri);
    }
  }

  Uri? _buildDailywordsRealTalkUri(DailywordsModuleChoice choice) {
    final rawUrl = activeFlavor.realTalkUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final base = Uri.tryParse(rawUrl);
    if (base == null) return null;

    var path = base.path.isEmpty ? '/' : base.path;
    final dialogPath = choice.dialogPath?.trim();
    if (dialogPath != null && dialogPath.isNotEmpty) {
      final cleanBase =
          path.endsWith('/') ? path.substring(0, path.length - 1) : path;
      final cleanDialog =
          dialogPath.startsWith('/') ? dialogPath.substring(1) : dialogPath;
      if (cleanBase.split('/').last == cleanDialog.split('/').first) {
        path = cleanBase.isEmpty ? '/$cleanDialog' : cleanBase;
      } else {
        path = '$cleanBase/$cleanDialog';
      }
    }

    final queryParameters = Map<String, String>.from(base.queryParameters);
    final l2 = lang.trim().toLowerCase();
    final l1 = (nativeLang?.trim().isNotEmpty == true
            ? nativeLang!.trim()
            : Localizations.localeOf(context).languageCode)
        .toLowerCase();
    if (l1.isNotEmpty) {
      queryParameters['l1'] = l1;
    }
    if (l2.isNotEmpty) {
      queryParameters['l2'] = l2;
      final localeId = speechLocaleOverrides[l2];
      if (localeId != null && localeId.isNotEmpty) {
        queryParameters['locale'] = localeId;
      }
    }
    final sceneId = choice.dialogSceneId?.trim();
    if (sceneId != null && sceneId.isNotEmpty) {
      queryParameters['module'] = sceneId;
    }
    queryParameters['topic'] = choice.rowId;
    if (choice.startKey?.trim().isNotEmpty == true) {
      queryParameters['start'] = choice.startKey!.trim();
    }
    queryParameters['return_to'] = activeFlavor.dashboardLandingUrl;
    return base.replace(
      path: path,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  Future<void> _onSelectStart(String fileName) async {
    final selectedStart = sanitizeStartCurriculum(fileName);
    if (activeFlavor.id == 'dailywords') {
      nativeSelectTimer?.cancel();
      final selectedNativeLang =
          nativeLang?.trim().isNotEmpty == true ? nativeLang : lang;
      setState(() {
        nativeLang = selectedNativeLang;
        awaitingStart = false;
        awaitingNative = false;
        activeStartCurriculumKey = selectedStart;
      });
      unawaited(_loadHintPack(forceRefresh: true));
      await _loadInitial(
        startKey: selectedStart,
        showTapPrimer: true,
        preferLanguageSpecificStart: false,
        initialDownloadLimit: 2,
      );
      return;
    }
    nativeSelectTimer?.cancel();
    nativeSelectTimer = Timer(_openingPanelAutoProceedDelay, () {
      if (!mounted || !awaitingNative) return;
      _onSelectNative(null, selectedStart);
    });
    setState(() {
      awaitingStart = false;
      awaitingNative = true;
      activeStartCurriculumKey = selectedStart;
    });
  }

  void _onModuleTargetLanguageChange(String languageCode) {
    final normalized = languageCode.trim().toLowerCase();
    if (!langChoices.contains(normalized)) return;
    setState(() {
      lang = normalized;
      hintPack = null;
      hintRevealedUuid = null;
    });
  }

  void _onModuleNativeLanguageChange(String languageCode) {
    final normalized = languageCode.trim().toLowerCase();
    if (!langChoices.contains(normalized)) return;
    setState(() {
      nativeLang = normalized;
      hintPack = null;
      hintRevealedUuid = null;
    });
  }

  void _enterPickFlow() {
    if (!activeFlavor.allowPickManifest) return;
    setState(() {
      pickFlowActive = true;
      awaitingStart = false;
      awaitingNative = false;
      awaitingPickNative = true;
      pickListLoading = false;
      pickListError = null;
      pickManifestKeys = [];
      pickMappingFutures.clear();
      nativeLang = null;
      pickManifestLabelFutures.clear();
    });
  }

  void _cancelPickFlow() {
    _resetPickSelection(showStart: true);
  }

  void _onSelectPickNative(String? motherLang) {
    setState(() {
      nativeLang = motherLang;
      awaitingPickNative = false;
      pickListError = null;
      pickManifestKeys = [];
      pickMappingFutures.clear();
      pickListLoading = true;
    });
    _loadPickManifestKeys();
  }

  Future<void> _loadPickManifestKeys() async {
    try {
      final keys = await pickManifestService.fetchManifestKeys();
      if (!mounted) return;
      final labelFutures = <String, Future<String>>{};
      for (final key in keys) {
        labelFutures[key] = pickManifestService.previewLabel(
          key,
          l1Lang: nativeLang ?? lang,
          l2Lang: lang,
        );
      }
      setState(() {
        pickManifestKeys = keys;
        pickListLoading = false;
        pickManifestLabelFutures
          ..clear()
          ..addAll(labelFutures);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pickListLoading = false;
        pickListError = e.toString();
      });
    }
  }

  void _openPickMapping(String key) {
    final future = pickMappingFutures[key] ??
        pickManifestService.loadFullManifestEntries(key);
    pickMappingFutures[key] = future;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PickMappingScreen(
          manifestName: _friendlyPickTitle(key),
          entriesFuture: future,
          manifestService: pickManifestService,
          l1Lang: nativeLang ?? lang,
          l2Lang: lang,
          onBack: () => Navigator.of(context).pop(),
          onStart: () async {
            await _startPickGame(key);
          },
        ),
      ),
    );
  }

  Future<void> _startPickGame(String key) async {
    if (!activeFlavor.allowPickManifest) return;
    _resetPickSelection();
    await _loadInitial(startKey: key, showTapPrimer: true);
  }

  void _resetPickSelection({bool showStart = false}) {
    if (!mounted) return;
    setState(() {
      pickFlowActive = false;
      awaitingPickNative = false;
      pickListLoading = false;
      pickListError = null;
      pickManifestKeys = [];
      pickMappingFutures.clear();
      pickManifestLabelFutures.clear();
      if (showStart) {
        awaitingStart = true;
        nativeLang = null;
      }
    });
  }

  String _friendlyPickTitle(String key) {
    final base = key.toLowerCase().startsWith('pick_') ? key.substring(5) : key;
    final slug = base.split('.').first;
    final parts = slug.split('_').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return key;
    final formattedParts = parts
        .map((part) =>
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .toList();
    return formattedParts.join(' ');
  }

  Widget _buildPickMenu() {
    if (pickListLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pickListError != null) {
      return Center(child: Text('Fehler: $pickListError'));
    }
    if (pickManifestKeys.isEmpty) {
      return const Center(child: Text('Keine Pick-Module gefunden.'));
    }
    final flavourText =
        'L1: ${nativeLang ?? '–'}  ·  L2: ${lang.toUpperCase()}';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                iconSize: 44,
                onPressed: _cancelPickFlow,
                icon: Image.asset(
                  'assets/icons/pick.webp',
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Pick-Module',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            flavourText,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemBuilder: (context, index) =>
                  _buildPickMenuEntry(pickManifestKeys[index]),
              separatorBuilder: (context, index) =>
                  const Divider(height: 8, thickness: 1),
              itemCount: pickManifestKeys.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickMenuEntry(String key) {
    final labelFuture =
        pickManifestLabelFutures[key] ?? Future.value(_friendlyPickTitle(key));
    return FutureBuilder<String>(
      future: labelFuture,
      builder: (context, snapshot) {
        final label = snapshot.data ?? _friendlyPickTitle(key);
        final subtitleText = snapshot.connectionState != ConnectionState.done
            ? 'Titel lädt…'
            : null;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            tooltip: 'Pick-Modul starten',
            icon: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 32,
            ),
            onPressed: () => _startPickGame(key),
          ),
          title: Text(label),
          subtitle: subtitleText != null ? Text(subtitleText) : null,
          trailing: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'Mapping anzeigen',
            icon: Image.asset(
              'assets/icons/Magnifying_glass.webp',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
            onPressed: () => _openPickMapping(key),
          ),
          onTap: () => _startPickGame(key),
        );
      },
    );
  }

  Future<void> _onSelectNative(String? motherLang, String startKey) async {
    nativeSelectTimer?.cancel();
    setState(() {
      nativeLang = motherLang;
      awaitingNative = false;
      hintPack = null;
      hintRevealedUuid = null;
    });
    unawaited(_loadHintPack(forceRefresh: true));
    await _loadInitial(
      startKey: sanitizeStartCurriculum(startKey),
      showTapPrimer: true,
    );
  }

  String? _landingLanguageFromQuery() {
    final raw = _launchQueryParameters()['lang']?.trim();
    final queryCandidate = _normalizeSupportedLanguageCode(raw);
    if (queryCandidate != null) return queryCandidate;
    for (final locale in PlatformDispatcher.instance.locales) {
      final candidate = _normalizeSupportedLanguageCode(locale.languageCode);
      if (candidate != null) return candidate;
    }
    return _normalizeSupportedLanguageCode(
        PlatformDispatcher.instance.locale.languageCode);
  }

  String? _normalizeSupportedLanguageCode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final candidate = raw.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    return langChoices.contains(candidate) ? candidate : null;
  }

  Future<void> _loadInitial({
    String? startKey,
    bool showTapPrimer = false,
    bool preferLanguageSpecificStart = true,
    int initialDownloadLimit = initialItemDownloadLimit,
    bool ignoreSavedCursor = false,
  }) async {
    // Initialer Ladepfad: UI zurücksetzen, Curriculum holen,
    // dann so viele Batches laden, bis mindestens 1 valides Item da ist
    // oder nichts Brauchbares gefunden wird.
    lastCloudLoadToken++;
    final previousStartKey = activeStartCurriculumKey == null
        ? null
        : sanitizeStartCurriculum(activeStartCurriculumKey);
    final requestedStartKey =
        startKey == null ? null : sanitizeStartCurriculum(startKey);
    final initData = buildSessionInitData(DateTime.now().toUtc());
    final prep = await prepareForInitialLoad(
      startKey: requestedStartKey,
      previousStartKey: previousStartKey,
      defaultStartCurriculum: activeFlavor.defaultStartCurriculum,
      resolveStartKeyForLang: preferLanguageSpecificStart
          ? _startCurriculumKeyForLanguage
          : (startKey) async => sanitizeStartCurriculum(startKey),
      resetCursorOnNextLoad: resetCursorOnNextLoad,
      persistUserCursor: () async {},
      loggerReady: loggerReady,
      sessionStart: sessionStart,
      endLoggerSession: () async {
        await logger.endSession();
      },
      onResolvedStart: (resolvedStart) {
        activeStartCurriculumKey = resolvedStart;
        _saveOnboardingSnapshot(startKey: resolvedStart);
      },
      resetLadder: () async {
        ladderController.reset(clearWins: true);
      },
    );
    var resolvedStart = prep.resolvedStart;
    final baseStart = prep.baseStart;
    final bool explicitStartRequested = prep.explicitStartRequested;
    final resetDeps = SessionResetDeps(
      trialBuffer: trialBuffer,
      itemByUuid: itemByUuid,
      presentationPolicy: presentationPolicy,
      itemStats: itemStats,
      comprehensionHistory: comprehensionHistory,
      namingHistory: namingHistory,
      comprehensionSeen: comprehensionSeen,
      loadErrors: loadErrors,
      correctCounts: correctCounts,
      audioPlayCounts: audioPlayCounts,
      audioMaxSequenceIndex: audioMaxSequenceIndex,
      audioMinSequenceIndex: audioMinSequenceIndex,
      audioUrlOkCache: audioUrlOkCache,
      imageVariantCursorByUuid: _imageVariantCursorByUuid,
    );
    resetSessionState(
      deps: resetDeps,
      cancelNativeSelectTimer: () => nativeSelectTimer?.cancel(),
      clearHintRevealed: () => hintRevealedUuid = null,
    );
    setState(() {
      awaitingLang = initData.awaitingLang;
      awaitingStart = initData.awaitingStart;
      awaitingNative = initData.awaitingNative;
      loading = initData.loading;
      error = initData.error;
      trialIndex = initData.trialIndex;
      currentTrial = initData.currentTrial;
      currentSlot = initData.currentSlot;
      pendingNextSlot = initData.pendingNextSlot;
      _lastAnsweredCursorUuid = initData.lastAnsweredCursorUuid;
      _lastNonRefillerCursorUuid = initData.lastAnsweredCursorUuid;
      hasAnswered = initData.hasAnswered;
      lastCorrect = initData.lastCorrect;
      lastSelectionIsLeft = initData.lastSelectionIsLeft;
      micPromptActive = initData.micPromptActive;
      micDenied = initData.micDenied;
      currentTrialAudioToken = initData.currentTrialAudioToken;
      currentTrialAudioUuid = initData.currentTrialAudioUuid;
      currentTrialAudioUri = initData.currentTrialAudioUri;
      namingInProgress = initData.namingInProgress;
      namingStatus = initData.namingStatus;
      namingDisabled = initData.namingDisabled;
      namingNoMicMode = false;
      _liveTranscript = initData.liveTranscript;
      currentTrialToken = initData.currentTrialToken;
      sessionStart = initData.sessionStart;
      unawaited(protocolLog.startSession(sessionStart!,
          userId: userId, nativeLang: nativeLang));
      sessionEnded = initData.sessionEnded;
      nativeSeenCounts.clear();
      curriculumStartOffset = initData.curriculumStartOffset;
      _showTapPrimerPanel = false;
    });
    logger.setSessionContext(
        startKey: resolvedStart, lang: lang, nativeLang: nativeLang);
    protocolLog.setSessionContext(nativeLang: nativeLang);
    _configureLoggerRemote();
    if (loggerReady) {
      unawaited(logger.startSession(lang: lang));
    }
    await _updateRivalIdleDays();
    try {
      curriculum.clear();
      final allowDefaultFallback = startKey == null &&
          (baseStart == defaultStartCurriculum || previousStartKey == null);
      debugPrint(
          '[curriculum][resolve] resolved=$resolvedStart base=$baseStart explicit=$explicitStartRequested');
      final result = await initializeSession(
        api: api,
        resolvedStart: resolvedStart,
        baseStart: baseStart,
        explicitStartRequested: explicitStartRequested,
        allowDefaultFallback: allowDefaultFallback,
        lang: lang,
        onStartKeyChanged: (nextStart) {
          resolvedStart = nextStart;
          activeStartCurriculumKey = nextStart;
          _saveOnboardingSnapshot(startKey: nextStart);
          logger.setSessionContext(
              startKey: nextStart, lang: lang, nativeLang: nativeLang);
        },
      );
      resolvedStart = result.resolvedStart;
      curriculum = result.curriculum;
      loadErrors.addAll(result.errors);
      await _maybeApplyUserCurriculumDelta(resolvedStart);
      if (curriculum.isEmpty) {
        setState(() {
          loading = false;
          error =
              'Kein Curriculum gefunden. Prüfe Start-Curriculum ($resolvedStart) in R2 oder Worker-Host.';
        });
        return;
      }

      await loadSeedsAndInitialBatches(
        loadSeeds: _loadSeeds,
        initialItemDownloadLimit: initialDownloadLimit,
        batchSize: batchSize,
        itemsLength: () => items.length,
        curriculumLength: () => curriculum.length,
        nextOffset: _nextCurriculumOffset,
        loadBatch: (offset, limit) => _loadBatch(offset, maxEntries: limit),
      );

      if (items.isEmpty) {
        setState(() {
          loading = false;
          error =
              'Kein Item mit vollständigen Assets (JSON/PNG/MP3 für $lang) gefunden.';
        });
      } else {
        setState(() {
          loading = false;
        });
        if (mounted) {
          await _initializePresentationPolicy(
            showTapPrimer: showTapPrimer,
            ignoreSavedCursor: ignoreSavedCursor,
          );
        }
      }
    } catch (e) {
      setState(() {
        error = 'Start-Curriculum fehlgeschlagen ($resolvedStart): $e';
        loading = false;
      });
    }
  }

  Future<String> _startCurriculumKeyForLanguage(String startKey) async {
    final sanitized = sanitizeStartCurriculum(startKey);
    if (isPickManifestKey(sanitized)) {
      return startKey;
    }
    final candidate = _startCurriculumKeyWithLangSuffix(sanitized, lang);
    return candidate == sanitized ? sanitized : candidate;
  }

  String _startCurriculumKeyWithLangSuffix(String startKey, String language) {
    final normalizedLang = language.trim().toLowerCase();
    if (normalizedLang.isEmpty || !startKey.toLowerCase().endsWith('.json')) {
      return startKey;
    }
    final base = startKey.substring(0, startKey.length - 5);
    if (base.toLowerCase().endsWith('_$normalizedLang')) {
      return startKey;
    }
    return '${base}_${normalizedLang}.json';
  }

  Future<void> _maybeApplyUserCurriculumDelta(String startKey) async {
    if (!enableRemoteUserDelta) {
      userDelta = null;
      curriculumStartOffset = _offsetAfterResumeCursor(startKey);
      resetCursorOnNextLoad = false;
      return;
    }
    if (userId == null || userId!.isEmpty) {
      userDelta = null;
      curriculumStartOffset = 0;
      resetCursorOnNextLoad = false;
      return;
    }
    UserCurriculumDelta? delta = await userCurriculumService.fetchDelta(
        userId: userId!, startKey: startKey);
    delta ??= await userDeltaStore.load(userId!);
    if (resetCursorOnNextLoad) {
      final resetDelta = (delta ?? UserCurriculumDelta()).withCursor(-1);
      userDelta = resetDelta;
      curriculum = resetDelta.applyTo(curriculum);
      curriculumStartOffset = resetDelta.offsetForNext(curriculum);
      resetCursorOnNextLoad = false;
      unawaited(userDeltaStore.save(userId!, resetDelta));
      unawaited(userCurriculumService.pushDelta(
          userId: userId!, startKey: startKey, delta: resetDelta));
      return;
    }
    if (delta != null) {
      userDelta = delta;
      curriculum = delta.applyTo(curriculum);
      curriculumStartOffset = delta.offsetForNext(curriculum);
      unawaited(userDeltaStore.save(userId!, delta));
    } else {
      curriculumStartOffset = 0;
    }
  }

  int _offsetAfterResumeCursor(String startKey) {
    if (curriculum.isEmpty) return 0;
    final cursor = resumeStateController.cursorForStartKey(
      startKey: startKey,
      lang: lang,
      nativeLang: nativeLang,
    );
    if (cursor == null) return 0;
    final cursorPos = cursor.clamp(-1, curriculum.length - 1);
    final next = cursorPos + 1;
    if (next >= curriculum.length) return 0;
    return next;
  }

  Future<void> _loadSeeds() async {
    int loaded = 0;
    List<CurriculumEntry> seedEntries = [];
    final List<ItemData> newItems = [];
    try {
      seedEntries = await api.loadStartCurriculum('start_curriculum_a.json');
    } catch (e) {
      debugPrint('[seed][load-start-a-error] $e');
    }
    for (final entry in seedEntries.take(seedCount)) {
      if (loaded >= seedCount) break;
      if (loadedUuids.contains(entry.uuid)) continue;
      bool hasLangAudio = false;
      try {
        hasLangAudio = await api.hasAudioForLang(entry.uuid, lang);
      } catch (e) {
        debugPrint('[seed][check-error] ${entry.uuid}: $e');
      }
      if (!hasLangAudio) continue;
      try {
        final item = await api.loadItem(entry, lang, nativeLang: nativeLang);
        newItems.add(item);
        loaded++;
      } catch (e) {
        loadErrors.add('seed ${entry.uuid}: $e');
      }
    }
    trialBuffer.addNewItems(newItems);
    if (newItems.isNotEmpty) {
      debugPrint(
          '[seed][loaded] added=${newItems.length} total_items=${items.length} uuids=${newItems.map((e) => e.uuid).join(",")}');
    } else {
      debugPrint('[seed][loaded] added=0 (all skipped)');
    }
  }

  int _nextCurriculumOffset() {
    if (curriculum.isEmpty) return 0;
    return (curriculumStartOffset + items.length) % curriculum.length;
  }

  Future<void> _persistUserCursor() async {
    if (userId == null || userId!.isEmpty) return;
    if (curriculum.isEmpty) return;
    final startKey = activeStartCurriculumKey ?? defaultStartCurriculum;
    String? uuid = _lastNonRefillerCursorUuid;
    if (uuid == null || uuid.isEmpty) {
      if (presentationPolicy.isCurrentSlotFromRefiller) return;
      uuid = currentTrial?.target.uuid ?? currentSlot.targetUuid;
    }
    if (uuid == null || uuid.isEmpty) return;
    final cursor = curriculum.indexWhere((e) => e.uuid == uuid);
    if (cursor < 0) return;
    protocolLog.addNote('Cursor: startKey=$startKey cursor=$cursor uuid=$uuid');
    if (!enableRemoteUserDelta) return;
    final nextDelta = (userDelta ?? UserCurriculumDelta()).withCursor(cursor);
    userDelta = nextDelta;
    unawaited(userDeltaStore.save(userId!, nextDelta));
    unawaited(userCurriculumService.pushDelta(
        userId: userId!, startKey: startKey, delta: nextDelta));
  }

  Future<void> _persistRefillerQueue() async {
    final uid = userId;
    if (uid == null || uid.isEmpty) return;
    final startKey = activeStartCurriculumKey ?? defaultStartCurriculum;
    await refillerStore.save(
      userId: uid,
      startKey: startKey,
      lang: lang,
      state: RefillerState(queue: presentationPolicy.refillerQueueSnapshot),
    );
  }

  int? _currentCursorIndexForResume(String startKey) {
    if (curriculum.isEmpty) return null;
    String? uuid = _lastNonRefillerCursorUuid;
    if (uuid == null || uuid.isEmpty) {
      if (presentationPolicy.isCurrentSlotFromRefiller) return null;
      uuid = currentTrial?.target.uuid ?? currentSlot.targetUuid;
    }
    if (uuid == null || uuid.isEmpty) return null;
    final idx = curriculum.indexWhere((e) => e.uuid == uuid);
    if (idx < 0) return null;
    return idx;
  }

  Future<void> _pushResumeState({bool fetchExistingResume = true}) async {
    final uid = userId;
    if (uid == null || uid.isEmpty) return;
    final startKey = activeStartCurriculumKey ?? defaultStartCurriculum;
    final cursor = _currentCursorIndexForResume(startKey);
    if (cursor == null) return;
    String? native = nativeLang;
    if (native == null || native.trim().isEmpty) {
      try {
        final saved = await onboardingStore.load();
        if (saved != null &&
            saved.startKey == startKey &&
            saved.lang == lang &&
            saved.nativeLang != null &&
            saved.nativeLang!.trim().isNotEmpty) {
          native = saved.nativeLang;
        }
      } catch (_) {
        // ignore fallback errors
      }
    }
    final entry = ResumeStateEntry(
      startKey: startKey,
      lang: lang,
      nativeLang: native,
      cursor: cursor,
      date: DateTime.now().toUtc(),
      winsYou: ladder.winsYou,
      winsRival: ladder.winsRival,
    );
    await resumeStateController.pushEntry(
      userId: uid,
      entry: entry,
      fetchExisting: fetchExistingResume,
    );
  }

  Future<bool> _loadBatch(int offset, {int? maxEntries}) async {
    if (batchLoading) return false;
    batchLoading = true;
    // Lade einen Teilbereich des Curriculums, wrap-around wenn wir am Ende sind.
    final List<CurriculumEntry> slice = [];
    final int limit =
        (maxEntries != null && maxEntries > 0) ? maxEntries : batchSize;
    for (int i = 0; i < limit; i++) {
      if (curriculum.isEmpty) break;
      slice.add(curriculum[(offset + i) % curriculum.length]);
    }
    if (slice.isEmpty) {
      batchLoading = false;
      return false;
    }
    final List<String> batchErrors = [];
    final List<ItemData> newItems = [];
    try {
      for (final entry in slice) {
        if (loadedUuids.contains(entry.uuid)) {
          continue; // bereits geladen (Seed oder vorheriger Batch)
        }
        try {
          final item = await api.loadItem(entry, lang, nativeLang: nativeLang);
          newItems.add(item);
        } catch (e) {
          batchErrors.add('${entry.uuid}: $e');
        }
      }
    } finally {
      batchLoading = false;
      if (mounted) {
        setState(() {
          loadErrors.addAll(batchErrors);
          trialBuffer.addNewItems(newItems);
          for (final it in newItems) {
            itemByUuid[it.uuid] = it;
          }
        });
        if (newItems.isNotEmpty) {
          debugPrint(
              '[batch][loaded] offset=$offset added=${newItems.length} total_items=${items.length} uuids=${newItems.map((e) => e.uuid).join(",")}');
        } else {
          debugPrint(
              '[batch][loaded] offset=$offset added=0 errors=${batchErrors.length}');
        }
        // Einmaliger Dump der aktuell geladenen UUIDs zur Fehlersuche.
        debugPrint(
            '[items][loaded] total=${items.length} all=${items.map((e) => e.uuid).join(",")}');
      }
    }
    return newItems.isNotEmpty;
  }

  Future<ItemData?> _ensureItemLoaded(String uuid) async {
    if (uuid.isEmpty) return null;
    final cached = itemByUuid[uuid];
    if (cached != null) return cached;
    final entry = curriculum.firstWhere(
      (e) => e.uuid == uuid,
      orElse: () => CurriculumEntry(uuid: uuid, index: uuid),
    );
    try {
      final item = await api.loadItem(entry, lang, nativeLang: nativeLang);
      if (!mounted) return item;
      setState(() {
        trialBuffer.addNewItems([item]);
        itemByUuid[item.uuid] = item;
      });
      return item;
    } catch (e) {
      if (mounted) {
        setState(() {
          loadErrors.add('$uuid: $e');
        });
      }
      return null;
    }
  }

  Uint8List _pickVariantBytes(ItemData item) {
    final variants =
        item.imageVariants.isNotEmpty ? item.imageVariants : [item.imageBytes];
    final cursor = _imageVariantCursorByUuid[item.uuid] ?? 0;
    final idx = cursor % variants.length;
    _imageVariantCursorByUuid[item.uuid] = (cursor + 1) % variants.length;
    return variants[idx];
  }

  Future<Trial?> _buildTrialForTarget(String targetUuid) async {
    final targetItem = await _ensureItemLoaded(targetUuid);
    if (targetItem == null) return null;
    final distractorUuid = presentationPolicy
        .pickDistractorUuid(targetUuid, exclude: {targetUuid});
    final distractorItem = await _ensureItemLoaded(
        distractorUuid ?? _fallbackDistractorUuid(targetUuid));
    if (distractorItem == null) return null;
    return Trial(
      target: targetItem,
      distractor: distractorItem,
      targetOnLeft: Random().nextBool(),
      targetImageBytes: _pickVariantBytes(targetItem),
      distractorImageBytes: _pickVariantBytes(distractorItem),
      isReview: false,
    );
  }

  String _fallbackDistractorUuid(String targetUuid) {
    // As a last resort, pick any other loaded uuid.
    for (final u in loadedUuids) {
      if (u != targetUuid) return u;
    }
    // Fall back to any other curriculum item.
    for (final e in curriculum) {
      if (e.uuid != targetUuid) return e.uuid;
    }
    return targetUuid;
  }

  Future<void> _prefetchUuids(Set<String> uuids,
      {int maxConcurrent = 4}) async {
    if (uuids.isEmpty) return;
    final pending = Queue<String>.from(uuids.where((u) => u.isNotEmpty));
    Future<void> runOne(String uuid) async {
      if (loadedUuids.contains(uuid)) return;
      await _ensureItemLoaded(uuid);
    }

    while (pending.isNotEmpty) {
      final batch = <Future<void>>[];
      while (pending.isNotEmpty && batch.length < maxConcurrent) {
        batch.add(runOne(pending.removeFirst()));
      }
      await Future.wait(batch);
    }
  }

  void _schedulePrefetchForSlot(PresentationSlot slot) {
    final uuids = slot.mode == PresentationMode.comprehension
        ? presentationPolicy.prefetchSetForComprehensionBlock()
        : presentationPolicy.prefetchSetForTarget(slot.targetUuid);
    unawaited(_prefetchUuids(uuids));
  }

  Future<void> _applySlot(
    PresentationSlot slot, {
    bool resetUi = true,
    bool advanceToken = true,
  }) async {
    if (!mounted) return;
    if (advanceToken) {
      currentTrialToken++;
    }
    final token = currentTrialToken;
    setState(() {
      currentSlot = slot;
      trialIndex = slot.mode == PresentationMode.comprehension
          ? presentationPolicy.comprehensionIndex
          : -1;
      currentTrial = null;
      if (resetUi) {
        hasAnswered = false;
        lastCorrect = null;
        lastSelectionIsLeft = null;
        namingOutcome = null;
        namingCorrectDetected = false;
        namingHold = false;
        namingStatus = '';
        _liveTranscript = '';
        _namingStartPending = false;
      }
      _namingStartAutoTimer?.cancel();
      _namingStartAutoTimer = null;
    });
    _schedulePrefetchForSlot(slot);
    final trial = await _buildTrialForTarget(slot.targetUuid);
    if (!mounted || token != currentTrialToken) return;
    setState(() {
      currentTrial = trial;
      _namingTransition = false;
      if (trial != null) {
        _lastDisplayTrial = trial;
      }
    });
    if (trial != null && loggerReady) {
      unawaited(logger.log('trial_presented', {
        'mode':
            slot.mode == PresentationMode.naming ? 'naming' : 'comprehension',
        'uuid': trial.target.uuid,
        'distractor_uuid': trial.distractor.uuid,
        'target_on_left': trial.targetOnLeft,
        'trial_index': trialIndex,
        'is_refiller': presentationPolicy.isCurrentSlotFromRefiller,
        'is_review': trial.isReview,
      }));
    }
    if (trial != null) {
      unawaited(_ackResumeEmojiAfterFirstTrial());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTrial(token);
    });
  }

  Future<void> _persistSessionCache() async {
    if (items.isEmpty) return;
    final current = currentTrial?.target;
    if (current == null) return;
    final itemIdx = items.indexWhere((e) => e.uuid == current.uuid);
    if (itemIdx < 0) return;
    final before = (cachedItemCount * 0.6).floor();
    int start = itemIdx - before;
    if (start < 0) start = 0;
    int end = start + cachedItemCount;
    if (end > items.length) {
      end = items.length;
      start = (end - cachedItemCount)
          .clamp(0, items.isEmpty ? 0 : items.length - 1)
          .toInt();
    }
    final window = items.sublist(start, end);
    final lastIndex = itemIdx - start;
    final cachedItems = window
        .map((i) => CachedItem(
              uuid: i.uuid,
              index: i.index,
              position: i.position,
              text: i.text,
              nativeText: i.nativeText,
              phonetic: i.phonetic,
              hintRefsByLang: i.hintRefsByLang,
              imageSignature: i.imageSignature,
              audioUri: i.audioUri.toString(),
              audioVariants: i.audioVariants.map((u) => u.toString()).toList(),
              imageBytes: i.imageBytes,
              imageVariants: i.imageVariants,
            ))
        .toList();
    final cache = SessionCache(
      lang: lang,
      startKey: activeStartCurriculumKey ?? defaultStartCurriculum,
      nativeLang: nativeLang,
      lastIndex: lastIndex,
      items: cachedItems,
    );
    unawaited(sessionCacheStore.save(cache));
  }

  List<Uri> _audioSequenceForItem(ItemData item) {
    final variants =
        item.audioVariants.isNotEmpty ? item.audioVariants : [item.audioUri];
    if (variants.isEmpty) return [item.audioUri, item.audioUri];
    final sequence = <Uri>[];
    for (final uri in variants) {
      sequence
        ..add(uri)
        ..add(uri);
    }
    return sequence;
  }

  int? _previousVariantIndex(List<Uri> sequence, int index) {
    if (sequence.isEmpty || index <= 0) return null;
    final current = sequence[index];
    for (int i = index - 1; i >= 0; i--) {
      if (sequence[i] != current) return i;
    }
    return null;
  }

  int? _nextVariantIndex(List<Uri> sequence, int index) {
    if (sequence.isEmpty || index < 0) return null;
    final current = sequence[index];
    for (int i = index + 1; i < sequence.length; i++) {
      if (sequence[i] != current) return i;
    }
    return null;
  }

  Future<int?> _nextPlayableIndex(List<Uri> sequence, int startIndex) async {
    var index = _nextVariantIndex(sequence, startIndex);
    while (index != null) {
      if (await _audioUrlOkCached(sequence[index])) return index;
      index = _nextVariantIndex(sequence, index);
    }
    index = _previousVariantIndex(sequence, startIndex);
    while (index != null) {
      if (await _audioUrlOkCached(sequence[index])) return index;
      index = _previousVariantIndex(sequence, index);
    }
    return null;
  }

  Future<bool> _audioUrlOkCached(Uri uri) async {
    final key = uri.toString();
    final cached = audioUrlOkCache[key];
    if (cached == true) return true;
    if (cached == false) {
      // Don't keep temporary network failures sticky for the whole session.
      audioUrlOkCache.remove(key);
    }
    final ok = await api.audioUrlOk(uri);
    if (ok) {
      audioUrlOkCache[key] = true;
    } else {
      audioUrlOkCache.remove(key);
    }
    return ok;
  }

  Uri _audioUriForItem(ItemData item, {required bool advance}) {
    final bool alreadyAssigned = currentTrialAudioToken == currentTrialToken &&
        currentTrialAudioUuid == item.uuid &&
        currentTrialAudioUri != null;
    if (alreadyAssigned) return currentTrialAudioUri!;
    final sequence = _audioSequenceForItem(item);
    // Keep comprehension autoplay on a stable base variant. Fallback selection
    // is resolved per playback attempt and should not persist across trials.
    int index = 0;
    final chosen = sequence[index];
    if (advance) {
      audioPlayCounts[item.uuid] = (audioPlayCounts[item.uuid] ?? 0) + 1;
      currentTrialAudioToken = currentTrialToken;
      currentTrialAudioUuid = item.uuid;
      currentTrialAudioUri = chosen;
    }
    return chosen;
  }

  Future<bool> _playAudioUri(Uri uri) async {
    final PlaybackResult result = await playbackEngine.playSpeech(uri);
    if (!result.ok) {
      debugPrint('[audio][error] url=$uri err=${result.error ?? "unknown"}');
    }
    return result.ok;
  }

  Future<bool> _playAudioUriWithRetry(Uri uri, {int retries = 1}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      final ok = await _playAudioUri(uri);
      if (ok) return true;
      if (attempt < retries) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
    return false;
  }

  Future<void> _playAudioForItem(ItemData item, {bool advance = false}) async {
    final sequence = _audioSequenceForItem(item);
    var uri = _audioUriForItem(item, advance: advance);
    final initialIndex = sequence.lastIndexOf(uri);
    // Mobile web can report false negatives on URL prechecks (HEAD/range).
    // Prefer playback-first fallback there.
    final bool shouldPrecheck = !kIsWeb;
    if (shouldPrecheck && initialIndex >= 0) {
      final ok = await _audioUrlOkCached(uri);
      if (!ok) {
        final fallbackIndex = await _nextPlayableIndex(sequence, initialIndex);
        if (fallbackIndex != null) {
          final fallbackUri = sequence[fallbackIndex];
          final bool updateCache = advance ||
              (currentTrialAudioToken == currentTrialToken &&
                  currentTrialAudioUuid == item.uuid);
          if (updateCache) {
            currentTrialAudioToken = currentTrialToken;
            currentTrialAudioUuid = item.uuid;
            currentTrialAudioUri = fallbackUri;
          }
          debugPrint(
              '[audio][missing] uuid=${item.uuid} from=$uri to=$fallbackUri');
          uri = fallbackUri;
        } else {
          debugPrint('[audio][missing] uuid=${item.uuid} url=$uri');
          return;
        }
      }
    }
    if (advance) {
      debugPrint(
          '[audio][play] idx=$trialIndex token=$currentTrialToken url=$uri');
    }
    final playedIndex = sequence.lastIndexOf(uri);
    final ok = await _playAudioUriWithRetry(uri);
    if (ok) return;
    if (playedIndex < 0) return;
    final candidateIndices = <int>[];
    for (var i = _nextVariantIndex(sequence, playedIndex);
        i != null;
        i = _nextVariantIndex(sequence, i)) {
      candidateIndices.add(i);
    }
    for (var i = _previousVariantIndex(sequence, playedIndex);
        i != null;
        i = _previousVariantIndex(sequence, i)) {
      candidateIndices.add(i);
    }
    for (final fallbackIndex in candidateIndices) {
      final fallbackUri = sequence[fallbackIndex];
      final bool updateCache = advance ||
          (currentTrialAudioToken == currentTrialToken &&
              currentTrialAudioUuid == item.uuid);
      if (updateCache) {
        currentTrialAudioToken = currentTrialToken;
        currentTrialAudioUuid = item.uuid;
        currentTrialAudioUri = fallbackUri;
      }
      debugPrint(
          '[audio][fallback] uuid=${item.uuid} from=$uri to=$fallbackUri');
      final fallbackOk = await _playAudioUriWithRetry(fallbackUri);
      if (fallbackOk) return;
    }
    debugPrint('[audio][silent] uuid=${item.uuid} no playable fallback');
  }

  Future<void> _playHintAudioForItem(ItemData item) async {
    final sequence = _audioSequenceForItem(item);
    final primaryUri = sequence.isNotEmpty ? sequence.first : item.audioUri;
    final primaryIndex = sequence.lastIndexOf(primaryUri);
    final primaryOk = await _playHintUriWithRetry(primaryUri);
    if (primaryOk) return;
    if (primaryIndex < 0) {
      debugPrint(
          '[audio][hint-silent] uuid=${item.uuid} no playable primary variant');
      return;
    }

    final candidateIndices = <int>[];
    for (var i = _nextVariantIndex(sequence, primaryIndex);
        i != null;
        i = _nextVariantIndex(sequence, i)) {
      candidateIndices.add(i);
    }
    for (var i = _previousVariantIndex(sequence, primaryIndex);
        i != null;
        i = _previousVariantIndex(sequence, i)) {
      candidateIndices.add(i);
    }

    for (final fallbackIndex in candidateIndices) {
      final fallbackUri = sequence[fallbackIndex];
      debugPrint(
          '[audio][hint-fallback] uuid=${item.uuid} from=$primaryUri to=$fallbackUri');
      final ok = await _playHintUriWithRetry(fallbackUri);
      if (ok) return;
    }
    debugPrint('[audio][hint-silent] uuid=${item.uuid} no playable fallback');
  }

  Future<bool> _playHintUri(Uri uri) async {
    final result = await playbackEngine.playHint(uri);
    if (result.ok) return true;
    debugPrint('[audio][hint-error] url=$uri err=${result.error ?? "unknown"}');
    final speechFallback = await playbackEngine.playSpeech(uri);
    if (speechFallback.ok) {
      debugPrint('[audio][hint-fallback-speech] url=$uri');
      return true;
    }
    debugPrint(
        '[audio][hint-fallback-speech-failed] url=$uri err=${speechFallback.error ?? "unknown"}');
    return false;
  }

  Future<bool> _playHintUriWithRetry(Uri uri, {int retries = 1}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      final ok = await _playHintUri(uri);
      if (ok) return true;
      if (attempt < retries) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
    return false;
  }

  Future<void> _playNextTrialAudio(int token) async {
    if (!mounted || token != currentTrialToken) return;
    final t = currentTrial;
    if (t == null) return;
    final item = t.target;
    await _playAudioForItem(item, advance: true);
  }

  bool _isNamingTrial() {
    if (namingDisabled) return false;
    if (namingBlockRemaining > 0) return false;
    // Keep 2AFC feedback visible even if the item just became "ready to name".
    if (hasAnswered && !namingInProgress && namingOutcome == null) return false;
    final int uniqueNeeded = min(namingMinUniqueItems, max(1, items.length));
    if (comprehensionSeen.length < uniqueNeeded) return false;
    if (currentTrial == null) return false;
    if (currentSlot.mode != PresentationMode.naming) return false;
    return currentSlot.targetUuid == currentTrial!.target.uuid;
  }

  bool _shouldShowNative(ItemData item) {
    if (nativeLang == null) return false;
    if (item.nativeText == null || item.nativeText!.isEmpty) return false;
    final seen = nativeSeenCounts[item.uuid] ?? 0;
    // Spec: show on 1st and 5th presentation; with a 0-based counter that's 0 and 4.
    return seen == 0 || seen == 4;
  }

  Future<void> _startTrial(int token) async {
    if (!mounted || token != currentTrialToken) return;
    if (namingHold) return; // Benennen wartet auf Button (nur für 2AFC)
    if (!_isNamingTrial() && _showTapPrimerPanel) {
      debugPrint(
          '[trial][start-blocked] idx=$trialIndex token=$token tap_primer=true');
      return;
    }
    unawaited(_persistSessionCache());
    if (_isNamingTrial()) {
      debugPrint('[trial][start] idx=$trialIndex token=$token naming=true');
      return _scheduleNamingAutoStart(token);
    } else {
      debugPrint('[trial][start] idx=$trialIndex token=$token naming=false');
      return _playNextTrialAudio(token);
    }
  }

  Future<void> _prepareMicForNamingSession(int token) async {
    if (!mounted || token != currentTrialToken || !_isNamingTrial()) return;
    protocolLog.addNote(
        'Naming mic preflight requested: token=$token action=ensure_mic_ready_at_session_start');
    final ready = await voiceController.ensureMicReady(
      forceRecheck: true,
      onPermanentDisable: () {
        if (!mounted || token != currentTrialToken) return;
        setState(() {
          micDenied = true;
        });
      },
    );
    if (!mounted || token != currentTrialToken || !_isNamingTrial()) return;
    setState(() {
      micDenied = !ready;
      micPermanentlyDenied = voiceState.micPermanentlyDenied;
      speechPermanentlyDenied = voiceState.speechPermanentlyDenied;
      if (ready) {
        micPrimed = true;
        micPromptActive = false;
        namingNoMicMode = false;
      }
    });
    protocolLog.addNote(
        'Naming mic preflight result: token=$token ready=$ready micPermanentDenied=$micPermanentlyDenied speechPermanentDenied=$speechPermanentlyDenied');
  }

  Future<void> _scheduleNamingAutoStart(int token) async {
    if (!mounted || token != currentTrialToken || !_isNamingTrial()) return;
    _namingStartAutoTimer?.cancel();
    setState(() {
      _namingStartPending = true;
      namingStatus = _instructionText('naming_auto_start_prompt');
    });
    protocolLog.addNote(
        'Naming auto-start armed: token=$token delay_ms=$namingStartAutoDelayMs');
    unawaited(_prepareMicForNamingSession(token));
    _namingStartAutoTimer =
        Timer(const Duration(milliseconds: namingStartAutoDelayMs), () {
      if (!mounted || token != currentTrialToken || !_isNamingTrial()) return;
      protocolLog.addNote(
          'Naming auto-start timeout reached: token=$token action=prime_and_start_after_3s');
      setState(() {
        _namingStartPending = false;
        if (namingStatus == _instructionText('naming_auto_start_prompt')) {
          namingStatus = '';
        }
      });
      unawaited(_primeMicAndStart(skipGate: true));
    });
  }

  Future<void> _openMicSettings() async {
    setState(() {
      namingStatus = '';
    });
    if (isMacOS) {
      var opened = false;
      for (final uri in const [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
        'x-apple.systempreferences:com.apple.preference.security',
      ]) {
        try {
          opened = await launchUrl(
            Uri.parse(uri),
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {
          opened = false;
        }
        if (opened) break;
      }
      if (!opened && mounted) {
        setState(() {
          namingStatus =
              'Open macOS System Settings > Privacy & Security > Microphone.';
        });
      }
    } else {
      try {
        await openAppSettings();
      } catch (_) {
        if (mounted) {
          setState(() {
            namingStatus = 'Open system microphone settings manually.';
          });
        }
      }
    }
    if (!mounted) return;
    final wasNoMicMode = namingNoMicMode;
    final ready = await voiceController.ensureMicReady(forceRecheck: true);
    if (!mounted) return;
    if (ready && wasNoMicMode) {
      protocolLog.addNote(
          'Naming no-mic mode disabled: token=$currentTrialToken reason=mic_settings_ready');
    }
    setState(() {
      micDenied = !ready;
      namingHold = !ready;
      micPermanentlyDenied = voiceState.micPermanentlyDenied;
      speechPermanentlyDenied = voiceState.speechPermanentlyDenied;
      if (ready) {
        namingNoMicMode = false;
        namingStatus = '';
      } else if (micPermanentlyDenied || speechPermanentlyDenied) {
        namingStatus = '';
      } else {
        namingStatus = '';
      }
    });
  }

  Future<void> _primeMicAndStart({bool skipGate = false}) async {
    if (_namingSessionBusy) return;
    final token = currentTrialToken;
    await _primeAudioForUserGestureAsync(
      skipGate ? 'naming-start-skip-gate' : 'naming-start',
    );
    debugPrint(
        '[naming][prime] token=$token skipGate=$skipGate primed=$micPrimed');
    protocolLog
        .addNote('Naming mic prime requested: token=$token skipGate=$skipGate');
    setState(() {
      micDenied = false;
    });
    Future<bool> ensureReadyOnce() async {
      return await voiceController.ensureMicReady(
          forceRecheck: true,
          onPermanentDisable: () {
            if (!mounted) return;
            setState(() {
              micDenied = true;
            });
          });
    }

    var ready = await ensureReadyOnce();
    // Windows can briefly report "not ready" right after permission was granted.
    // Retry a couple of times after explicit gate allow before aborting naming.
    if (!ready &&
        skipGate &&
        !micPermanentlyDenied &&
        !speechPermanentlyDenied) {
      for (final delay in const [
        Duration(milliseconds: 220),
        Duration(milliseconds: 520),
      ]) {
        await Future<void>.delayed(delay);
        if (!mounted || token != currentTrialToken) return;
        ready = await ensureReadyOnce();
        if (ready || micPermanentlyDenied || speechPermanentlyDenied) {
          break;
        }
      }
    }
    protocolLog.addNote(
        'Naming mic prime readiness: token=$token ready=$ready skipGate=$skipGate micPermanentDenied=$micPermanentlyDenied speechPermanentDenied=$speechPermanentlyDenied');

    if (!ready) {
      final bool transientAfterGateAllow = skipGate &&
          !micPermanentlyDenied &&
          !speechPermanentlyDenied &&
          currentSlot.mode == PresentationMode.naming;
      final bool permanentDeny =
          micPermanentlyDenied || speechPermanentlyDenied;
      if (transientAfterGateAllow) {
        protocolLog.addNote(
            'Naming mic prime transient-not-ready after gate allow: token=$token action=hold_for_retry');
      } else if (permanentDeny) {
        protocolLog.addNote(
            'Naming mic prime blocked-permanent: token=$token action=hold_with_recovery_options');
      } else {
        protocolLog.addNote(
            'Naming mic prime not-ready: token=$token action=hold_with_recovery_options');
      }
      setState(() {
        micDenied = true;
        namingStatus = permanentDeny
            ? 'Microphone permission is blocked by system settings.'
            : '';
        micPrimed = false;
        micPromptActive = true;
        namingHold = true;
      });
      return;
    }
    if (namingNoMicMode) {
      protocolLog.addNote(
          'Naming no-mic mode disabled: token=$token reason=mic_prime_ready');
    }
    protocolLog.addNote(
        'Naming mic prime succeeded: token=$token skipGate=$skipGate action=start_naming_flow');
    setState(() {
      micPrimed = true;
      micPromptActive = false;
      namingHold = false;
      namingNoMicMode = false;
      namingStatus = '';
    });
    await _startNamingFlow(token, skipGate: skipGate, userInitiated: true);
  }

  Future<NamingFlowOutcome?> _runNoMicNamingFlow(
    int token, {
    required Trial trial,
  }) async {
    if (!mounted || token != currentTrialToken) return null;
    protocolLog.addNote(
        'Naming no-mic run: token=$token uuid=${trial.target.uuid} action=simulate_without_asr');
    setState(() {
      namingInProgress = true;
      micPromptActive = false;
      namingHold = false;
      namingOutcome = null;
      namingCorrectDetected = false;
      namingStatus = _noMicNamingText('continue_without_recording');
      _liveTranscript = '';
      micStage = 0;
      micOn = true;
    });

    await Future<void>.delayed(const Duration(seconds: namingFirstWindowSec));
    if (!mounted || token != currentTrialToken) return null;

    setState(() {
      micStage = 1;
      micOn = false;
    });
    await _playHintAudioForItem(trial.target);
    if (!mounted || token != currentTrialToken) return null;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || token != currentTrialToken) return null;
    await _playHintAudioForItem(trial.target);
    if (!mounted || token != currentTrialToken) return null;

    setState(() {
      micStage = 2;
      micOn = true;
    });
    await Future<void>.delayed(const Duration(seconds: namingRepeatWindowSec));
    if (!mounted || token != currentTrialToken) return null;

    return NamingFlowOutcome(
      correct: false,
      moves: 0,
      transcript: '',
      attempts: 1,
      correctCount: 0,
      usedHint: true,
    );
  }

  void _completeNamingSession(
      {required int token, required bool wasCorrect, required int moves}) {
    if (!mounted || token != currentTrialToken) return;
    namingInProgress = false;
    micOn = false;
    micStage = -1;
    if (!_micControllerDisposed) {
      try {
        micController.stop();
      } catch (_) {}
    }
    setState(() {
      if (wasCorrect) {
        namingStatus = '';
      }
      namingOutcome = wasCorrect;
      namingCorrectDetected = wasCorrect;
      _liveTranscript = _liveTranscript;
      hasAnswered = false;
    });
    debugPrint(
        '[naming][flow-end] token=$token correct=$wasCorrect moves=$moves');
    final rewardExtraMs = max(0, moves - 1) * namingRewardStepSpacingMs;
    final totalDelayMs = max(1200, 900 + rewardExtraMs);
    Future.delayed(Duration(milliseconds: totalDelayMs), () {
      if (!mounted) return;
      if (token != currentTrialToken) return;
      _advanceAfterNamingAttempt();
    });
  }

  void _handleNamingCorrectDetected({required int token, required int steps}) {
    if (!mounted || token != currentTrialToken || steps <= 0) return;
    if (!namingCorrectDetected) {
      setState(() {
        namingCorrectDetected = true;
      });
    }
    unawaited(_runNamingRewardSteps(token: token, steps: steps));
  }

  String _buildMicStatusDetails() {
    final lines = <String>[];
    final micChecked = voiceState.micCheckRan;
    final bool macosSpeechManaged =
        voiceState.micPlatform.toLowerCase() == 'macos';
    if (!micChecked) {
      lines.add('Mic permission: not checked yet');
      lines.add('Speech recognition: not checked yet');
    } else {
      final micPermissionText = macosSpeechManaged
          ? (voiceState.lastMicGranted
              ? 'granted via macOS speech dialog'
              : 'not granted in macOS speech dialog')
          : (micPermanentlyDenied
              ? 'blocked in system settings'
              : (voiceState.lastMicGranted ? 'granted' : 'not granted'));
      lines.add('Mic permission: $micPermissionText');

      final String speechText;
      if (speechPermanentlyDenied) {
        speechText = 'blocked in system settings';
      } else if (macosSpeechManaged && voiceState.lastSpeechGranted) {
        speechText = 'granted';
      } else if (macosSpeechManaged && !voiceState.lastSpeechGranted) {
        speechText = 'not granted';
      } else if (!voiceState.lastSpeechGranted &&
          (isIOS ||
              isMacOS ||
              operatingSystem == 'ios' ||
              operatingSystem == 'macos')) {
        speechText = 'permission not granted';
      } else if (!voiceState.lastInitOk) {
        speechText = 'initialization failed';
      } else if (!voiceState.lastSpeechAvailable) {
        speechText = 'service unavailable on this device';
      } else if (!voiceState.lastSpeechHasPermission &&
          (isIOS ||
              isMacOS ||
              operatingSystem == 'ios' ||
              operatingSystem == 'macos')) {
        speechText = 'permission missing';
      } else {
        speechText = 'ready';
      }
      lines.add('Speech recognition: $speechText');
    }

    if (!voiceState.listenCheckRan) {
      lines.add(kIsWeb
          ? 'Browser ASR: not checked yet'
          : 'Mic input: not checked yet');
    } else if (kIsWeb) {
      if (voiceState.lastListenGotResultEvent) {
        lines.add('Browser ASR: speech result received');
      } else {
        lines.add(
            'Browser ASR: no recognition result during last naming attempt');
      }
    } else if (voiceState.lastListenGotSoundLevel) {
      lines.add(
          'Mic input: signal detected (peak ${voiceState.lastListenMaxSoundLevel.toStringAsFixed(0)} dB)');
    } else {
      lines.add('Mic input: no signal detected during last naming attempt');
    }

    final locale = voiceState.lastListenLocale.trim();
    if (locale.isNotEmpty && locale != '-') {
      lines.add('ASR locale: $locale');
    } else if (voiceState.micPlatform.isNotEmpty) {
      lines.add('Platform: ${voiceState.micPlatform}');
    }
    return lines.join('\n');
  }

  void _advanceAfterNamingAttempt() {
    if (_mountainCelebrationActive) {
      _queueResumeAfterMountainCelebration(
        _MountainCelebrationResumeAction.advanceNaming,
      );
      return;
    }
    final currentUuid = currentTrial?.target.uuid ?? currentSlot.targetUuid;
    if (currentUuid.isEmpty) {
      _gotoNextTrial();
      return;
    }
    setState(() {
      _namingTransition = true;
    });
    final disableNamingTransitions = shouldDisableNamingTransitions(
      namingDisabled: namingDisabled,
      namingBlockRemaining: namingBlockRemaining,
    );
    final decision = presentationPolicy.onNamingAttemptFinished(
      currentUuid: currentUuid,
      namingDisabled: disableNamingTransitions,
      namingInProgress: namingInProgress,
    );
    if (kDebugMode) {
      debugPrint(
          '[naming][advance] current=$currentUuid -> next=${decision.nextSlot.mode}:${decision.nextSlot.targetUuid} policyActive=${presentationPolicy.isNamingActive}');
    }
    if (decision.refillerQueueDirty) {
      unawaited(_persistRefillerQueue());
    }
    pendingNextSlot = decision.nextSlot;
    _gotoNextTrial();
  }

  Future<void> _startNamingFlow(int token,
      {bool skipGate = false, bool userInitiated = false}) async {
    if (_namingSessionBusy || !_isNamingTrial()) return;
    if (token != currentTrialToken) return;
    debugPrint(
        '[naming][flow-start] token=$token primed=$micPrimed noMicMode=$namingNoMicMode');
    if (!namingNoMicMode && !micPrimed) {
      setState(() {
        micPromptActive = true;
        namingStatus = '';
      });
      return;
    }
    bool isCurrent() => mounted && token == currentTrialToken;
    final trial = currentTrial;
    if (trial == null) return;
    final Future<String?>? localeFuture = namingNoMicMode
        ? null
        : namingLocaleHelper.resolveAndLog(
            speech: voiceController.speech,
            lang: lang,
            overrides: speechLocaleOverrides,
            protocolLog: protocolLog,
          );
    setState(() {
      hasAnswered = true; // block Selektionen/Advances während Naming
    });
    final result = namingNoMicMode
        ? await _runNoMicNamingFlow(token, trial: trial)
        : await runNamingFlow(
            voiceController: voiceController,
            namingLocaleHelper: namingLocaleHelper,
            protocolLog: protocolLog,
            speechLocaleOverrides: speechLocaleOverrides,
            lang: lang,
            token: token,
            trial: trial,
            isCurrent: isCurrent,
            scorer: (transcript, targetText) => _isTranscriptCorrect(
              transcript,
              targetText,
              uuid: trial.target.uuid,
            ),
            playHintAudioForItem: _playHintAudioForItem,
            onTranscript: (text) {
              if (!isCurrent()) return;
              debugPrint(
                  '[naming][asr] uuid=${trial.target.uuid} heard="$text" target="${trial.target.text}"');
              setState(() {
                _liveTranscript = text;
              });
            },
            onCorrectDetected: () {
              _handleNamingCorrectDetected(token: token, steps: 1);
            },
            userInitiated: userInitiated,
            firstWindow: const Duration(seconds: namingFirstWindowSec),
            repeatWindow: const Duration(seconds: namingRepeatWindowSec),
            localeIdFuture: localeFuture,
          );

    if (!mounted || token != currentTrialToken) return;
    if (result == null) {
      protocolLog.addNote(
        'Naming flow returned no result: token=$token uuid=${trial.target.uuid} action=keep_current_item_active',
      );
      setState(() {
        namingOutcome = null;
        namingCorrectDetected = false;
        namingHold = false;
        namingStatus = _instructionText('naming_interrupted');
        _liveTranscript = '';
        hasAnswered = false;
      });
      return;
    }

    final wasCorrect = result.moves > 0;
    final transcript = result.transcript;
    final moves = result.moves;
    final uuid = trial.target.uuid;
    debugPrint(
        '[naming][scored] uuid=$uuid transcript="$transcript" target="${trial.target.text}" correct=$wasCorrect moves=$moves result_null=false');
    protocolLog.addNaming(
      label: trial.target.text,
      nativeLabel: trial.target.nativeText,
      phonetic: trial.target.phonetic,
      heard: transcript,
      correct: wasCorrect,
    );
    _lastAnsweredCursorUuid = uuid;
    _lastNonRefillerCursorUuid = uuid;
    if (loggerReady) {
      unawaited(logger.log('naming_result',
          {'lang': lang, 'uuid': uuid, 'correct': wasCorrect}));
    }
    namingHistory.add(wasCorrect);
    // Run semantics: one outcome per naming slot; repeats happen via the naming block.
    // Therefore removal thresholds (mastery/overuse) must be applied across runs.
    itemStats.addNaming(uuid, wasCorrect);
    final stats = itemStats.statsFor(uuid);
    final removedFromNaming = presentationPolicy.onNamingStatsUpdated(
      uuid: uuid,
      namingAttempts: stats.namingAttempts,
      namingCorrect: stats.namingCorrect,
    );
    if (removedFromNaming) {
      final byCorrect = stats.namingCorrect >
          presentationPolicy.config.namingMasteryCorrectThreshold;
      final byAttempts = stats.namingAttempts >
          presentationPolicy.config.namingDownFromNamingMaxAttempts;
      final reason = byCorrect && byAttempts
          ? 'mastery+max_attempts'
          : (byCorrect ? 'mastery' : 'max_attempts');
      protocolLog.addNote(
          'Naming removal: uuid=$uuid reason=$reason attempts=${stats.namingAttempts} correct=${stats.namingCorrect} threshold_correct>${presentationPolicy.config.namingMasteryCorrectThreshold} threshold_attempts>${presentationPolicy.config.namingDownFromNamingMaxAttempts}');
      if (byCorrect && loggerReady) {
        unawaited(logger.log('item_naming_mastered', {
          'lang': lang,
          'uuid': uuid,
          'reason': reason,
          'naming_attempts': stats.namingAttempts,
          'naming_correct': stats.namingCorrect,
        }));
      }
    }
    if (removedFromNaming && presentationPolicy.consumeRefillerDirtyFlag()) {
      unawaited(_persistRefillerQueue());
    }
    _liveTranscript = transcript;
    final noAnswer = transcript.trim().isEmpty;
    if (!wasCorrect && noAnswer) {
      if (namingNoMicMode) {
        namingStatus = _noMicNamingText('scored_false');
        ladderController.tryRivalStep(probability: 0.5);
      } else {
        final bool gotSound = namingController.lastListenGotSoundLevel;
        final bool gotResult = namingController.lastListenGotResultEvent;
        final double maxLevel = namingController.lastListenMaxSoundLevel;
        final String localeUsed = namingController.lastListenLocale;
        final String localeInfo =
            localeUsed.trim().isNotEmpty && localeUsed != '-'
                ? ' (ASR locale: $localeUsed)'
                : '';
        if (kIsWeb && !gotResult) {
          namingStatus = '${_instructionText('browser_no_speech')}$localeInfo.';
        } else if (!gotSound) {
          namingStatus =
              '${_instructionText('no_microphone_signal')}$localeInfo';
        } else if (!gotResult) {
          namingStatus =
              '${_instructionText('speech_not_recognized')}$localeInfo';
        } else {
          namingStatus = '${_instructionText('no_transcript')}$localeInfo';
        }
        debugPrint(
            '[naming][diag] noAnswer=true sound=$gotSound result=$gotResult max=$maxLevel locale=${namingController.lastListenLocale}');
        ladderController.tryRivalStep(probability: 0.5);
      }
    }
    _completeNamingSession(token: token, wasCorrect: wasCorrect, moves: moves);
  }

  Future<void> _skipNaming(String reason) async {
    if (!mounted) return;
    debugPrint('[naming][skip] reason=$reason token=$currentTrialToken');
    voiceController.cancelActive();
    setState(() {
      namingOutcome = null;
      namingCorrectDetected = false;
      namingStatus = '';
    });
    _advanceAfterNamingAttempt();
  }

  void _toggleNamingPauseResume() {
    if (!mounted || !voiceController.canToggleRecordingPause()) return;
    final token = currentTrialToken;
    final wasPaused = namingPaused;
    voiceController.toggleRecordingPause();
    protocolLog.addNote(
      wasPaused
          ? 'Naming resumed: token=$token action=continue_recording'
          : 'Naming paused: token=$token action=pause_recording',
    );
    setState(() {
      if (namingPaused) {
        namingStatus = 'Recording paused. Tap mic to continue.';
      } else if (namingStatus == 'Recording paused. Tap mic to continue.') {
        namingStatus = '';
      }
    });
  }

  Future<void> _continueWithoutMicNaming(String reason) async {
    if (!mounted) return;
    final token = currentTrialToken;
    await _primeAudioForUserGestureAsync('naming-no-mic');
    protocolLog.addNote(
        'Naming manual no-mic start: token=$token reason=$reason action=enable_no_mic_mode_and_start');
    setState(() {
      namingBlockRemaining = 0;
      namingNoMicMode = true;
      namingOutcome = null;
      namingCorrectDetected = false;
      namingStatus = '';
      micDenied = true;
      micPrimed = true;
      micPromptActive = false;
      namingHold = false;
    });
    await _startNamingFlow(token, skipGate: true, userInitiated: true);
  }

  Future<void> _select(bool choseLeft) async {
    if (currentTrial == null ||
        hasAnswered ||
        namingInProgress ||
        _mountainCelebrationActive ||
        _isNamingTrial()) {
      return;
    }
    final trial = currentTrial!;
    final correct = choseLeft == trial.targetOnLeft;
    protocolLog.addComprehension(
      label: trial.target.text,
      nativeLabel: trial.target.nativeText,
      phonetic: trial.target.phonetic,
      correct: correct,
    );
    debugPrint(
        '[select] idx=$trialIndex token=$currentTrialToken naming=${_isNamingTrial()} choseLeft=$choseLeft targetOnLeft=${trial.targetOnLeft} correct=$correct');
    // Ergebnis für Gleitfenster speichern (max 10)
    lastTenResults.add(correct);
    if (lastTenResults.length > 10) {
      lastTenResults.removeAt(0);
    }
    comprehensionSeen.add(trial.target.uuid);
    final bool isRefiller = presentationPolicy.isCurrentSlotFromRefiller;
    _lastAnsweredCursorUuid = trial.target.uuid;
    if (!isRefiller) {
      _lastNonRefillerCursorUuid = trial.target.uuid;
    }
    final wasQualified =
        presentationPolicy.readyToName.contains(trial.target.uuid);
    final disableNamingTransitions = shouldDisableNamingTransitions(
      namingDisabled: namingDisabled,
      namingBlockRemaining: namingBlockRemaining,
    );
    final decision = presentationPolicy.onComprehensionAnswered(
      uuid: trial.target.uuid,
      correct: correct,
      namingDisabled: disableNamingTransitions,
      namingInProgress: namingInProgress,
    );
    if (decision.refillerQueueDirty) {
      unawaited(_persistRefillerQueue());
    }
    final isQualified =
        presentationPolicy.readyToName.contains(trial.target.uuid);
    if (!wasQualified && isQualified && loggerReady) {
      unawaited(logger.log('item_mastered', {
        'lang': lang,
        'uuid': trial.target.uuid,
        'correct_count': 5,
        'attempts': 5,
      }));
    }
    comprehensionHistory.add(correct);
    itemStats.addComprehension(trial.target.uuid, correct);
    if (loggerReady) {
      unawaited(logger.log('trial_result', {
        'lang': lang,
        'uuid': trial.target.uuid,
        'is_refiller': isRefiller,
        'correct': correct,
        'trial_index': trialIndex,
        'selection_left': choseLeft,
        'target_on_left': trial.targetOnLeft,
        'you_x': ladder.youIndex,
        'rival_x': ladder.rivalIndex,
        'you_progress': ladder.youProgress,
        'rival_progress': ladder.rivalProgress,
      }));
    }
    selectionEpoch++;
    final currentEpoch = selectionEpoch;
    final token = currentTrialToken;
    _advancePlayer(correct);
    setState(() {
      hasAnswered = true;
      lastCorrect = correct;
      lastSelectionIsLeft = choseLeft;
      pendingNextSlot = decision.nextSlot;
    });
    if (!mounted || currentEpoch != selectionEpoch) return;
    _advanceToNext(currentEpoch, token: token);
  }

  void _advanceToNext(int epoch, {int? token}) {
    if (_mountainCelebrationActive) {
      _queueResumeAfterMountainCelebration(
        _MountainCelebrationResumeAction.nextTrial,
      );
      return;
    }
    final t = token ?? currentTrialToken;
    final bool initialSkip = shouldSkipComprehensionAutoAdvance(
      namingHold: namingHold,
      namingInProgress: namingInProgress,
      inNamingSlot: currentSlot.mode == PresentationMode.naming,
    );
    if (initialSkip) return;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || epoch != selectionEpoch) return;
      if (t != currentTrialToken) return;
      final bool delayedSkip = shouldSkipComprehensionAutoAdvance(
        namingHold: namingHold,
        namingInProgress: namingInProgress,
        inNamingSlot: currentSlot.mode == PresentationMode.naming,
      );
      if (delayedSkip) {
        return;
      }
      if (_mountainCelebrationActive) {
        _queueResumeAfterMountainCelebration(
          _MountainCelebrationResumeAction.nextTrial,
        );
        return;
      }
      _gotoNextTrial();
    });
  }

  void _gotoNextTrial() {
    if (_disposed || !mounted) return;
    if (_mountainCelebrationActive) {
      _queueResumeAfterMountainCelebration(
        _MountainCelebrationResumeAction.nextTrial,
      );
      return;
    }
    if (_namingSessionBusy) {
      debugPrint(
          '[trial][next-blocked] namingBusy=true token=$currentTrialToken idx=$trialIndex');
      return;
    }
    voiceController.cancelActive();
    // Hints are one-run toggles: hide again on the next trial advance.
    hintRevealedUuid = null;
    final current = currentTrial?.target;
    if (current != null) {
      if (nativeLang != null) {
        nativeSeenCounts[current.uuid] =
            (nativeSeenCounts[current.uuid] ?? 0) + 1;
      }
      phoneticSeenCounts[current.uuid] =
          (phoneticSeenCounts[current.uuid] ?? 0) + 1;
      if (phoneticGlobalOverrideRemaining > 0) {
        phoneticGlobalOverrideRemaining--;
      }
    }
    if (namingBlockRemaining > 0) {
      namingBlockRemaining = max(0, namingBlockRemaining - 1);
    }
    final nextSlot = pendingNextSlot ?? presentationPolicy.currentSlot;
    assert(() {
      if (presentationPolicy.isNamingActive &&
          nextSlot.mode != PresentationMode.naming) {
        debugPrint(
            '[flow][invariant] namingActive=true but nextSlot=${nextSlot.mode} currentSlot=${currentSlot.mode} pendingNextSlot=${pendingNextSlot?.mode} policySlot=${presentationPolicy.currentSlot.mode}');
        return false;
      }
      return true;
    }());
    pendingNextSlot = null;
    unawaited(_applySlot(nextSlot));
    debugPrint(
        '[trial][next] idx=$trialIndex token=$currentTrialToken block=$namingBlockRemaining');
  }

  void _togglePhoneticsForAllItems({
    required bool currentlyVisible,
  }) {
    setState(() {
      if (currentlyVisible) {
        phoneticForceHiddenByToggle = true;
        phoneticGlobalOverrideRemaining = 0;
        return;
      }
      phoneticForceHiddenByToggle = false;
      phoneticGlobalOverrideRemaining = _phoneticGlobalOverrideRuns;
    });
  }

  void _advancePlayer(bool correct) {
    final targetUuid = currentTrial?.target.uuid ?? currentSlot.targetUuid;
    if (targetUuid.isEmpty) return;
    if (correct) {
      final count = (correctCounts[targetUuid] ?? 0) + 1;
      correctCounts[targetUuid] = count;
    }
    ladderController.applyPlayerStep(correct);
  }

  Future<void> _playFanfare() async {
    try {
      await fanfarePlayer.stop();
      await fanfarePlayer.play(AssetSource('sounds/fanfare.mp3'));
    } catch (_) {
      // falls kein Asset vorhanden ist, still weiterlaufen
    }
  }

  Future<void> _playMoveSound({
    required bool isYou,
    required MoveKind kind,
    bool? isCorrect,
  }) async {
    final bool correct = isCorrect ?? (kind == MoveKind.forward);
    final String asset;
    if (isYou) {
      asset = correct ? 'sounds/s1_step.wav' : 'sounds/s3_back.wav';
    } else {
      asset = correct ? 'sounds/rs1_step.wav' : 'sounds/s3_back.wav';
    }
    final playerToUse = isYou ? moveYouPlayer : moveRivalPlayer;
    try {
      await playerToUse.stop();
      await playerToUse.setVolume(moveSoundVolume);
      await playerToUse.play(AssetSource(asset));
    } catch (_) {
      // leise scheitern, falls Asset fehlt
    }
  }

  Future<void> _runNamingRewardSteps({
    required int token,
    required int steps,
  }) async {
    if (steps <= 0) return;
    const asset = 'sounds/s1_step.wav';
    final spacing = Duration(milliseconds: max(80, namingRewardStepSpacingMs));

    for (int i = 0; i < steps; i++) {
      if (!mounted || token != currentTrialToken) return;
      // Game rule: naming moves both player and rival forward.
      ladderController.applyCoupledForwardSteps(
        1,
        emitPlayerMoveEvents: false,
        emitRivalMoveEvents: false,
      );
      final playerToUse = (i % 2 == 0) ? namingBeepPlayer : namingBeepPlayer2;
      try {
        await playerToUse.stop();
        await playerToUse.setVolume(namingBeepVolume);
        await playerToUse.play(AssetSource(asset));
      } catch (_) {
        // ignore missing asset / platform limitations
      }
      if (i < steps - 1) {
        await Future.delayed(spacing);
      }
    }
  }

  void _handleLadderMove(MoveEvent event) {
    unawaited(_playMoveSound(
        isYou: event.isYou, kind: event.kind, isCorrect: event.isCorrect));
  }

  void _saveOnboardingSnapshot({String? startKey}) {
    final data = OnboardingData(
      lang: lang,
      startKey: startKey ?? activeStartCurriculumKey ?? defaultStartCurriculum,
      nativeLang: nativeLang,
      winsYou: ladder.winsYou,
      winsRival: ladder.winsRival,
      tapPrimerSeen: _tapPrimerConsumed,
      lastModuleRowId: lastModuleRowId,
      lastModuleMode: lastModuleMode?.name,
    );
    unawaited(onboardingStore.save(data));
  }

  bool _handleKeyboardEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return false;
    final focusWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusWidget is EditableText) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_isNamingTrial() && !_namingSessionBusy) {
        unawaited(_startNamingFlowFromKeyboard());
        return true;
      }
      if (showRestartSplash) {
        _handleResumeStartGesture('resume-start-keyboard');
        return true;
      }
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyF) {
      unawaited(_select(true));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyJ) {
      unawaited(_select(false));
      return true;
    }
    return false;
  }

  Future<void> _startNamingFlowFromKeyboard() async {
    await _primeAudioForUserGestureAsync('naming-enter-key');
    if (!mounted) return;
    await _primeMicAndStart(skipGate: true);
  }

  bool _canAutofocusKeyboardShortcuts() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText) return false;
    return true;
  }

  Widget _wrapWithKeyboardShortcuts(Widget child) {
    if (_canAutofocusKeyboardShortcuts() && !_keyboardFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _canAutofocusKeyboardShortcuts() &&
            !_keyboardFocusNode.hasFocus) {
          _keyboardFocusNode.requestFocus();
        }
      });
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (_canAutofocusKeyboardShortcuts() && !_keyboardFocusNode.hasFocus) {
          _keyboardFocusNode.requestFocus();
        }
      },
      child: RawKeyboardListener(
        focusNode: _keyboardFocusNode,
        onKey: _handleKeyboardEvent,
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(playbackEngine.dispose());
    fanfarePlayer.dispose();
    moveYouPlayer.dispose();
    moveRivalPlayer.dispose();
    namingBeepPlayer.dispose();
    namingBeepPlayer2.dispose();
    voiceController.cancelActive();
    ladderController.dispose();
    _micControllerDisposed = true;
    micController.dispose();
    nativeSelectTimer?.cancel();
    _mountainThemeAdvanceTimer?.cancel();
    _clearMountainCelebrationState();
    _resumeEmojiAckRetryTimer?.cancel();
    _namingStartAutoTimer?.cancel();
    _keyboardFocusNode.dispose();
    if (loggerReady) {
      unawaited(logger.endSession());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleOpenHistoryPanelFromQueryIfRequested();
    if (_historyPanelRequestedByQuery() && !_historyPanelQueryDialogClosed) {
      return _wrapWithKeyboardShortcuts(
        const Scaffold(
          body: SafeArea(
            child: SizedBox.expand(),
          ),
        ),
      );
    }
    if (awaitingLang) {
      final landingLanguage = _landingLanguageFromQuery();
      return _wrapWithKeyboardShortcuts(
        Scaffold(
          body: SafeArea(
            child: LangSelector(
              onSelect: _onSelectLang,
              initialSelectedLanguage: landingLanguage,
              autoSelectDelay:
                  landingLanguage == null || _historyPanelRequestedByQuery()
                      ? Duration.zero
                      : _openingPanelAutoProceedDelay,
            ),
          ),
        ),
      );
    }

    if (pickFlowActive) {
      if (awaitingPickNative) {
        return _wrapWithKeyboardShortcuts(
          Scaffold(
            body: SafeArea(
              child: NativeLangSelector(
                targetLang: lang,
                onSelect: _onSelectPickNative,
              ),
            ),
          ),
        );
      }
      return _wrapWithKeyboardShortcuts(
        Scaffold(
          body: SafeArea(
            child: _buildPickMenu(),
          ),
        ),
      );
    }

    if (awaitingStart) {
      return _wrapWithKeyboardShortcuts(
        Scaffold(
          body: SafeArea(
            child: activeFlavor.id == 'dailywords'
                ? DailywordsModuleSelector(
                    targetLanguageCode: lang,
                    nativeLanguageCode: nativeLang,
                    recommendedRowId: lastModuleRowId ?? 'dailywords',
                    recommendedMode:
                        lastModuleMode ?? DailywordsModuleMode.training,
                    showHistoryButton: true,
                    onOpenHistory: _openHistoryPanel,
                    historyHasSupervisorInfo: _historyPanelHasSupervisorInfo,
                    onTargetLanguageChange: _onModuleTargetLanguageChange,
                    onNativeLanguageChange: _onModuleNativeLanguageChange,
                    onSelect: (choice) =>
                        unawaited(_onSelectDailywordsModule(choice)),
                  )
                : StartCurriculumSelector(
                    onSelect: _onSelectStart,
                    targetLanguageCode: lang,
                    nativeLanguageCode: nativeLang,
                    onOpenRealTalk: _openRealTalk,
                    onPickSelected:
                        activeFlavor.allowPickManifest ? _enterPickFlow : null,
                    showHistoryButton: true,
                    onOpenHistory: _openHistoryPanel,
                    historyHasSupervisorInfo: _historyPanelHasSupervisorInfo,
                  ),
          ),
        ),
      );
    }

    if (awaitingNative && activeStartCurriculumKey != null) {
      return _wrapWithKeyboardShortcuts(
        Scaffold(
          body: SafeArea(
            child: NativeLangSelector(
              targetLang: lang,
              onSelect: (mother) =>
                  _onSelectNative(mother, activeStartCurriculumKey!),
            ),
          ),
        ),
      );
    }

    if (showRestartSplash) {
      return _wrapWithKeyboardShortcuts(
        RestartSplash(
          wins: ladder.winsYou,
          rivalWins: ladder.winsRival,
          viewCount: dashboardViewCount,
          targetLanguage: lang,
          nativeLanguage: nativeLang,
          onTargetLanguageChange: _onModuleTargetLanguageChange,
          onNativeLanguageChange: _onModuleNativeLanguageChange,
          onRestart: () => _restartOnboarding(),
          onStart: () => _handleResumeStartGesture('resume-start-arrow'),
          onSelectModule: _openModuleSelectorFromResume,
          onOpenHistory: _openHistoryPanel,
          selectedTrainingDepth: trainingDepthMode,
          onSelectTrainingDepth: _selectTrainingDepthMode,
          moduleProgress: restartModuleProgress,
          historyHasSupervisorInfo: _historyPanelHasSupervisorInfo,
          userId: userId,
          workerHost: workerHost,
          apiPrefix: apiPrefix,
          fallbackDatesUtc: _resumeFallbackDatesUtc(),
          onResumeEmojiChanged: _handleResumeSelectedEmojiChanged,
          onResumeFeedbackIdsChanged: _handleResumeSelectedFeedbackIdsChanged,
        ),
      );
    }

    Widget body;
    bool showTapPrimer = false;
    final bool showGlobalHourglass =
        loading || batchLoading || namingInProgress;
    if (loading) {
      final isCloudLoad = lastCloudLoadToken > 0;
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isCloudLoad)
              Image.asset('assets/icons/download.webp',
                  width: 200, height: 200, fit: BoxFit.contain),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
        ),
      );
    } else if (error != null) {
      body = Center(child: Text('Fehler: $error'));
    } else if (items.isEmpty) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Keine Items geladen.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Worker anpassen'),
            ),
            if (loadErrors.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Fehler beim Laden:'),
              SizedBox(
                height: 160,
                child: ListView(
                  shrinkWrap: true,
                  children: loadErrors
                      .map((e) => Text(e, style: const TextStyle(fontSize: 12)))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      final bool namingBlockActive = presentationPolicy.isNamingActive;
      final Trial? renderTrial = currentTrial ??
          ((namingBlockActive || _namingTransition) ? _lastDisplayTrial : null);
      if (renderTrial == null) {
        if (namingBlockActive || _namingTransition) {
          body = const Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        } else {
          body = Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Trial lädt…'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    final slot = presentationPolicy.currentSlot;
                    if (slot.targetUuid.isEmpty) {
                      _loadInitial();
                    } else {
                      unawaited(_applySlot(slot));
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut versuchen'),
                ),
              ],
            ),
          );
        }
      } else {
        final trial = renderTrial;
        final bool trialIsLoading = currentTrial == null;
        final leftImg = trial.targetOnLeft
            ? trial.targetImageBytes
            : trial.distractorImageBytes;
        final rightImg = trial.targetOnLeft
            ? trial.distractorImageBytes
            : trial.targetImageBytes;
        final size = MediaQuery.of(context).size;
        final bool isLandscape = size.width > size.height;
        final bool isNamingView = shouldRenderNamingView(
          slotMode: currentSlot.mode,
          namingInProgress: namingInProgress,
          hasNamingOutcome: namingOutcome != null,
          policyNamingActive: namingBlockActive,
          namingTransition: _namingTransition,
        );
        final double baseImageHeight = isLandscape
            ? min(size.height * 0.38, min(size.width * 0.55, 320.0))
            : min(size.height * 0.38, 320.0);
        final double imageHeight = baseImageHeight;
        final bool showDashboardButton = ladder.hasFlagAppeared ||
            ladder.winsYou > 0 ||
            ladder.winsRival > 0;
        final bool showHourglass = namingInProgress || batchLoading || loading;
        assert(() {
          if (currentSlot.mode == PresentationMode.naming && !isNamingView) {
            debugPrint(
                '[flow][invariant] slot=naming but isNamingView=false (trialLoading=$trialIsLoading policyNamingActive=$namingBlockActive namingInProgress=$namingInProgress namingOutcome=${namingOutcome != null} transition=$_namingTransition)');
            return false;
          }
          return true;
        }());
        final String phoneticLang = HintsService.normalizeLangCode(lang);
        final bool hasPhoneticData = trial.target.phonetic != null &&
            trial.target.phonetic!.isNotEmpty &&
            _phoneticEligibleLangs.contains(phoneticLang);
        final int phoneticSeen = phoneticSeenCounts[trial.target.uuid] ?? 0;
        final int phoneticOverrideCount = phoneticGlobalOverrideRemaining;
        final bool phoneticOverrideActive = phoneticOverrideCount > 0;
        final bool showPhonetic = hasPhoneticData &&
            !phoneticForceHiddenByToggle &&
            (phoneticSeen < 3 || phoneticOverrideActive);
        final bool showNative =
            !trialIsLoading && _shouldShowNative(trial.target);
        final bool hintsEnabled =
            nativeLang != null && nativeLang!.trim().isNotEmpty;
        final String normL1 =
            hintsEnabled ? HintsService.normalizeLangCode(nativeLang) : '';
        final String normL2 = HintsService.normalizeLangCode(lang);
        final bool hintPackMatches = hintPack != null &&
            hintPack!.l1 == normL1 &&
            hintPack!.l2 == normL2;
        final List<String> hintIds = hintPackMatches
            ? (trial.target.hintRefsByLang[normL2] ?? const <String>[])
            : const <String>[];
        final bool showHintsInline =
            !isNamingView && hintPackMatches && hintIds.isNotEmpty;
        final List<HintContent> resolvedHints = showHintsInline
            ? hintPack!.hintsForIds(hintIds)
            : const <HintContent>[];
        final bool hintAvailable = showHintsInline && resolvedHints.isNotEmpty;
        final bool hintRevealedForItem =
            hintAvailable && hintRevealedUuid == trial.target.uuid;
        final List<HintContent> hintEntries =
            hintRevealedForItem ? resolvedHints : const <HintContent>[];
        final String hintLabel =
            hintsEnabled ? HintsService.hintLabelFor(nativeLang!) : 'Hint';
        final String? hintMissingText =
            hintRevealedForItem && hintIds.isNotEmpty && hintEntries.isEmpty
                ? 'No hint text found for ids: ${hintIds.join(', ')}'
                : null;

        // Naming UX: don't show L2 text before the audio hint phase starts.
        // micStage: 0=first recording, 1=hint, 2=repeat, -1=idle/finished.
        final bool forceShowNamingText = isNamingView &&
            (namingHold ||
                micDenied ||
                micPermanentlyDenied ||
                speechPermanentlyDenied);
        final bool showL2Text = (!trialIsLoading) &&
            (!isNamingView ||
                namingOutcome != null ||
                micStage >= 1 ||
                forceShowNamingText);
        showTapPrimer = !trialIsLoading && !isNamingView && _showTapPrimerPanel;
        if (showTapPrimer) {
          body = TapPrimerPanel(
            autoProceedDelay: _openingPanelAutoProceedDelay,
            l1: nativeLang,
            l2: lang,
            onProceed: (primeAudio) {
              unawaited(_dismissTapPrimer(primeAudio: primeAudio));
            },
          );
        } else {
          body = SessionBody(
            ladder: ladder,
            runsDone: comprehensionHistory.length + namingHistory.length,
            isNaming: isNamingView,
            imageHeight: imageHeight,
            leftImageBytes: leftImg,
            rightImageBytes: rightImg,
            targetOnLeft: trial.targetOnLeft,
            hasAnswered: hasAnswered,
            lastSelectionIsLeft: lastSelectionIsLeft,
            namingCorrectDetected: namingCorrectDetected,
            namingOutcome: namingOutcome,
            namingStatus: namingStatus,
            micPrimed: micPrimed,
            micDenied: micDenied,
            micPermanentlyDenied: micPermanentlyDenied,
            speechPermanentlyDenied: speechPermanentlyDenied,
            micStatusDetails: _buildMicStatusDetails(),
            namingHold: namingHold,
            showHourglass: showHourglass,
            namingInProgress: namingInProgress,
            namingStartPending: _namingStartPending,
            micOn: micOn,
            micStage: micStage,
            namingPaused: namingPaused,
            showTinySpinner:
                trialIsLoading && (namingBlockActive || _namingTransition),
            liveTranscript: _liveTranscript,
            startNamingLabel: _instructionText('start_naming'),
            retryMicLabel: _instructionText('retry_mic'),
            settingsLabel: _instructionText('settings'),
            withoutMicLabel: _instructionText('without_mic'),
            targetText: showL2Text ? trial.target.text : '',
            targetPhonetic:
                showL2Text && showPhonetic ? trial.target.phonetic : null,
            phoneticButtonVisible: showL2Text && hasPhoneticData,
            phoneticOverrideActive: showPhonetic,
            onTogglePhonetic: hasPhoneticData
                ? () => _togglePhoneticsForAllItems(
                      currentlyVisible: showPhonetic,
                    )
                : null,
            spokenCueText:
                !isNamingView && !trialIsLoading ? trial.target.text : null,
            nativeText: trial.target.nativeText,
            showNative: showNative,
            hintEntries: hintEntries,
            hintLabel: hintLabel,
            hintMissingText: hintMissingText,
            hintButtonVisible: hintAvailable,
            hintButtonActive: hintRevealedForItem,
            onToggleHints: _toggleHintsForCurrent,
            hintPanelKey: _hintPanelKey,
            audioHintEnabled: !isNamingView && !trialIsLoading,
            onPlayAudioHint: () {
              unawaited(_playHintAudioForItem(trial.target));
            },
            showDashboardButton: showDashboardButton,
            showGlobalHourglass: showGlobalHourglass,
            mountainTheme: _activeMountainTheme,
            mountainYouWon: _mountainWinnerIsYou == true,
            mountainRivalWon: _mountainWinnerIsYou == false,
            onPrimeMic: () => unawaited(_primeMicAndStart(skipGate: true)),
            onOpenMicSettings: _openMicSettings,
            onContinueWithoutMic: _continueWithoutMicNaming,
            onSkipNaming: _skipNaming,
            onToggleNamingPauseResume: _toggleNamingPauseResume,
            onSelect: _select,
            tooltipLanguageCode:
                HintsService.normalizeLangCode(nativeLang ?? lang),
            onOpenDashboard: () {
              _mountainCelebrationTimer?.cancel();
              unawaited(_persistUserCursor());
              if (!sessionEnded) {
                _finishSession();
              }
              unawaited(_openDashboardPreview(context, focus: 'wins'));
            },
            onEscapeToOpeningPanel: _exitToOpeningPanel,
            onExitToResumePanel: _exitToResumePanelIfAvailable,
            onReturnToModuleSelection: _returnToModuleSelectionFromTraining,
          );
        }
      }
    }

    return _wrapWithKeyboardShortcuts(
      Scaffold(
        bottomNavigationBar: namingInProgress
            ? SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF3F6),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: const Color(0xFFBEC8CF), width: 1.4),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: MicProgressBar(
                    micStage: micStage,
                    micOn: micOn,
                    isPaused: namingPaused,
                    firstWindowSeconds: namingProgressFirstRatio,
                    repeatWindowSeconds: namingProgressRepeatRatio,
                    hintWindowSeconds: namingProgressHintRatio,
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: showTapPrimer
              ? body
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: body,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _openDashboardPreview(BuildContext context,
      {required String focus}) async {
    if (mounted) {
      setState(() {
        _clearMountainCelebrationState();
      });
    } else {
      _clearMountainCelebrationState();
    }
    _invalidateActiveSessionFlow();
    voiceController.cancelActive();
    await _stopAllSessionAudioPlayers();
    if (!mounted || !context.mounted) return;
    final mastered = presentationPolicy.readyToName.length;
    final wins = ladder.winsYou;
    final rivalWins = ladder.winsRival;
    setState(() {
      dashboardViewCount++;
    });
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          focus: focus,
          wins: wins,
          rivalWins: rivalWins,
          mastered: mastered,
          dashboardViewCount: dashboardViewCount,
          sessionStart: sessionStart,
          comprehensionHistory: List<bool>.from(comprehensionHistory),
          namingHistory: List<bool>.from(namingHistory),
          comprehensionAttempts: itemStats.comprehensionAttempts(),
          namingAttempts: itemStats.namingAttempts(),
          onExitToResumePanel: _exitToResumePanelIfAvailable,
          tooltipLanguageCode:
              HintsService.normalizeLangCode(nativeLang ?? lang),
          onExportProtocol: () => protocolLog.export(),
          onReturnToGame: () {},
        ),
      ),
    );
  }

  Future<void> _stopAllSessionAudioPlayers() async {
    try {
      await playbackEngine.stopSpeech();
    } catch (_) {}
    try {
      await playbackEngine.stopHint();
    } catch (_) {}
    final players = <AudioPlayer>[
      fanfarePlayer,
      moveYouPlayer,
      moveRivalPlayer,
      namingBeepPlayer,
      namingBeepPlayer2,
    ];
    for (final p in players) {
      try {
        await p.stop();
      } catch (_) {
        // best-effort shutdown
      }
    }
  }

  Future<void> _openRealTalk(Uri uri) async {
    if (!mounted) return;
    final useInAppRealTalk = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!useInAppRealTalk) {
      await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RealTalkScreen(
          initialUri: uri,
          onReturnToResumePanel: _exitToResumePanelIfAvailable,
        ),
      ),
    );
  }

  void _invalidateActiveSessionFlow() {
    currentTrialToken++;
    selectionEpoch++;
    pendingNextSlot = null;
    _showTapPrimerPanel = false;
  }

  Future<void> _flushExitLogsForDailyWords() async {
    if (!loggerReady) return;
    if (activeFlavor.id != 'dailywords') {
      if (sessionStart != null && !sessionEnded) {
        unawaited(logger.endSession());
      }
      return;
    }
    if (sessionStart != null && !sessionEnded) {
      await logger.endSessionAndFlush();
      return;
    }
    await logger.flushPendingUploads();
  }

  Future<void> _exitToResumePanelIfAvailable() async {
    await _persistUserCursor();
    await _pushResumeState();
    final saved = await onboardingStore.load();
    if (!mounted) return;
    final resumeLang = saved?.lang ?? lang;
    final resumeStartKey =
        saved?.startKey ?? activeStartCurriculumKey ?? defaultStartCurriculum;
    final resumeNative = saved?.nativeLang ?? nativeLang;
    final resumeWinsYou = saved?.winsYou ?? ladder.winsYou;
    final resumeWinsRival = saved?.winsRival ?? ladder.winsRival;
    voiceController.cancelActive();
    await _stopAllSessionAudioPlayers();
    await _flushExitLogsForDailyWords();
    setState(() {
      _clearMountainCelebrationState();
      _invalidateActiveSessionFlow();
      lang = resumeLang;
      activeStartCurriculumKey = resumeStartKey;
      nativeLang = resumeNative;
      awaitingLang = false;
      awaitingStart = false;
      awaitingNative = false;
      awaitingPickNative = false;
      pickFlowActive = false;
      showRestartSplash = true;
      loading = false;
      error = null;
      sessionStart = null;
      sessionEnded = true;
      currentTrial = null;
      _lastDisplayTrial = null;
      _namingTransition = false;
      currentSlot = const PresentationSlot(
          mode: PresentationMode.comprehension, targetUuid: '');
    });
    unawaited(_loadHintPack());
    ladderController.setWins(you: resumeWinsYou, rival: resumeWinsRival);
    await _loadLastSessionWins();
    unawaited(_updateRestartModuleProgress());
  }

  void _exitToOpeningPanel() {
    voiceController.cancelActive();
    unawaited(_stopAllSessionAudioPlayers());
    if (loggerReady && sessionStart != null && !sessionEnded) {
      unawaited(logger.endSession());
    }
    setState(() {
      _clearMountainCelebrationState();
      _invalidateActiveSessionFlow();
      awaitingLang = true;
      awaitingStart = false;
      awaitingNative = false;
      awaitingPickNative = false;
      pickFlowActive = false;
      showRestartSplash = false;
      loading = false;
      error = null;
      sessionStart = null;
      sessionEnded = true;
      currentTrial = null;
      _lastDisplayTrial = null;
      _namingTransition = false;
      currentSlot = const PresentationSlot(
          mode: PresentationMode.comprehension, targetUuid: '');
    });
  }

  Future<void> _returnToModuleSelectionFromTraining() async {
    final realTalkReturnUrl = _realTalkReturnUrlFromQuery();
    voiceController.cancelActive();
    _mountainCelebrationTimer?.cancel();
    await _runReturnStep(
      'stop-audio',
      _stopAllSessionAudioPlayers,
      timeout: const Duration(milliseconds: 900),
    );
    await _runReturnStep(
      'persist-progress',
      () => _persistProgressSnapshot(skipRemoteFetch: true),
      timeout: const Duration(milliseconds: 1600),
    );
    if (loggerReady && sessionStart != null && !sessionEnded) {
      await _runReturnStep(
        'logger-end-session',
        logger.endSession,
        timeout: const Duration(milliseconds: 900),
      );
    }
    if (realTalkReturnUrl != null) {
      final opened = await _openReturnUrl(realTalkReturnUrl);
      if (opened) return;
      if (!mounted) return;
      setState(() {
        error = 'Rückkehr zur RealTalk-Modulauswahl fehlgeschlagen.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _clearMountainCelebrationState();
      _invalidateActiveSessionFlow();
      awaitingLang = false;
      awaitingStart = true;
      awaitingNative = false;
      awaitingPickNative = false;
      pickFlowActive = false;
      showRestartSplash = false;
      loading = false;
      error = null;
      sessionEnded = true;
      currentTrial = null;
      _lastDisplayTrial = null;
      _namingTransition = false;
      lastModuleRowId = _moduleRowIdForStart(
          activeStartCurriculumKey ?? defaultStartCurriculum);
      lastModuleMode = DailywordsModuleMode.training;
      currentSlot = const PresentationSlot(
          mode: PresentationMode.comprehension, targetUuid: '');
    });
  }

  Future<void> _runReturnStep(
    String label,
    Future<void> Function() action, {
    required Duration timeout,
  }) async {
    try {
      await action().timeout(timeout);
    } on TimeoutException {
      debugPrint('[module-selection-return][$label][timeout]');
    } catch (e) {
      debugPrint('[module-selection-return][$label][error] $e');
    }
  }

  Future<bool> _openReturnUrl(Uri uri) async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      ).timeout(const Duration(milliseconds: 1200));
    } on TimeoutException {
      debugPrint('[module-selection-return][launch-timeout] $uri');
      return false;
    } catch (e) {
      debugPrint('[module-selection-return][launch-error] $e');
      return false;
    }
  }

  Uri? _realTalkReturnUrlFromQuery() {
    final params = _launchQueryParameters();
    final source = params['source']?.trim().toLowerCase();
    final rawReturnTo = params['return_to']?.trim();
    if (rawReturnTo != null && rawReturnTo.isNotEmpty) {
      final parsed = Uri.tryParse(rawReturnTo);
      if (parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https')) {
        return parsed;
      }
    }
    if (source != 'realtalk') return null;
    final host = Uri.base.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost') {
      return Uri.parse('http://127.0.0.1:8092/');
    }
    return Uri.parse('https://realtalk.dailywords-project.org/');
  }

  void _finishSession() {
    setState(() {
      _invalidateActiveSessionFlow();
      sessionEnded = true;
    });
    if (loggerReady) {
      unawaited(logger.endSession());
    }
  }

  bool _isTranscriptCorrect(String transcript, String target, {String? uuid}) {
    final t = normalizeText(transcript);
    final g = normalizeText(target);
    if (t.isEmpty || g.isEmpty) return false;
    final exactMatch = t == g;
    final containsMatch = t.contains(g) || g.contains(t);
    if (exactMatch || containsMatch) {
      if (loggerReady) {
        final stage = voiceController.state.micStage;
        final attempt = stage == 0
            ? 'first'
            : stage == 2
                ? 'repeat'
                : 'stage_$stage';
        unawaited(logger.log('audio_target_match', {
          if (uuid != null) 'uuid': uuid,
          'attempt': attempt,
          'accepted': true,
          'reason': exactMatch ? 'exact' : 'contains',
          'transcript': transcript,
          'target': target,
          't_norm': t,
          'g_norm': g,
          'exact_match': exactMatch,
          'contains_match': containsMatch,
          'asr_final': voiceController.namingController.lastFinalResult,
          'asr_confidence': voiceController.namingController.lastConfidence,
          'asr_words': voiceController.namingController.lastRecognizedWords,
        }));
      }
      return true;
    }
    final dist = levenshtein(t, g);
    final maxLen = max(t.length, g.length);
    final ratio = maxLen == 0 ? 1.0 : 1.0 - dist / maxLen;
    // toleranter: 3 Abweichungen oder 60% Übereinstimmung reichen
    const maxDist = 3;
    const minRatio = 0.6;
    final accepted = dist <= maxDist || ratio >= minRatio;
    if (loggerReady) {
      final stage = voiceController.state.micStage;
      final attempt = stage == 0
          ? 'first'
          : stage == 2
              ? 'repeat'
              : 'stage_$stage';
      unawaited(logger.log('audio_target_match', {
        if (uuid != null) 'uuid': uuid,
        'attempt': attempt,
        'accepted': accepted,
        'reason':
            accepted ? (dist <= maxDist ? 'levenshtein' : 'ratio') : 'rejected',
        'transcript': transcript,
        'target': target,
        't_norm': t,
        'g_norm': g,
        'exact_match': false,
        'contains_match': false,
        'levenshtein': dist,
        'max_len': maxLen,
        'ratio': ratio,
        'threshold_dist': maxDist,
        'threshold_ratio': minRatio,
        'asr_final': voiceController.namingController.lastFinalResult,
        'asr_confidence': voiceController.namingController.lastConfidence,
        'asr_words': voiceController.namingController.lastRecognizedWords,
      }));
    }
    return accepted;
  }
}

class _SessionWinSnapshot {
  int you = 0;
  int rival = 0;
  DateTime? lastTs;
}

typedef AsyncVoidCallback = Future<void> Function();

class PickMappingScreen extends StatefulWidget {
  const PickMappingScreen({
    super.key,
    required this.manifestName,
    required this.entriesFuture,
    required this.manifestService,
    required this.l1Lang,
    required this.l2Lang,
    required this.onStart,
    required this.onBack,
  });

  final String manifestName;
  final Future<List<CurriculumEntry>> entriesFuture;
  final PickManifestService manifestService;
  final String l1Lang;
  final String l2Lang;
  final AsyncVoidCallback onStart;
  final VoidCallback onBack;

  @override
  State<PickMappingScreen> createState() => _PickMappingScreenState();
}

class _PickMappingScreenState extends State<PickMappingScreen>
    with SingleTickerProviderStateMixin {
  final Map<String, Future<PickManifestRowTexts>> _texts = {};
  bool _isDownloading = false;
  late final AnimationController _wiggleController;
  late final Animation<double> _wiggleAnimation;

  Future<void> _handleStartPressed() async {
    if (_isDownloading) return;
    _setDownloading(true);
    try {
      await widget.onStart();
    } finally {
      if (!mounted) return;
      _setDownloading(false);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _setDownloading(bool downloading) {
    setState(() {
      _isDownloading = downloading;
      if (_isDownloading) {
        _wiggleController.repeat(reverse: true);
      } else {
        _wiggleController.stop();
        _wiggleController.reset();
      }
    });
  }

  Widget _buildAnimatedDownloadIcon() {
    return AnimatedBuilder(
      animation: _wiggleAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _wiggleAnimation.value,
          child: child,
        );
      },
      child: SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/icons/download.webp',
              width: 60,
              height: 60,
              fit: BoxFit.contain,
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.loop,
                  size: 24,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickTextBlock({required String text, String? phonetic}) {
    final trimmedPhonetic = phonetic?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 16),
        ),
        if (trimmedPhonetic?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              trimmedPhonetic!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Future<PickManifestRowTexts> _textForEntry(CurriculumEntry entry) {
    return _texts.putIfAbsent(
      entry.uuid,
      () => widget.manifestService.fetchRowTexts(
        entry,
        lang: widget.l2Lang,
        nativeLang: widget.l1Lang == widget.l2Lang ? null : widget.l1Lang,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _wiggleAnimation = Tween<double>(begin: -0.08, end: 0.08).animate(
      CurvedAnimation(
        parent: _wiggleController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _wiggleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Image.asset(
            'assets/icons/pick.webp',
            width: 32,
            height: 32,
            fit: BoxFit.contain,
          ),
          onPressed: widget.onBack,
        ),
        title: Text(widget.manifestName),
        actions: [
          IconButton(
            icon: _isDownloading
                ? _buildAnimatedDownloadIcon()
                : const Icon(Icons.check_circle, color: Colors.green, size: 28),
            onPressed: _isDownloading ? null : _handleStartPressed,
          ),
        ],
      ),
      body: FutureBuilder<List<CurriculumEntry>>(
        future: widget.entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }
          final entries = snapshot.data ?? [];
          if (entries.isEmpty) {
            return const Center(child: Text('Keine Einträge gefunden.'));
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return FutureBuilder<PickManifestRowTexts>(
                  future: _textForEntry(entry),
                  builder: (ctx, rowSnapshot) {
                    final text = rowSnapshot.data;
                    final l1 = text?.l1 ?? '…';
                    final l2 = text?.l2 ?? '…';
                    final disabled =
                        rowSnapshot.connectionState != ConnectionState.done;
                    return Opacity(
                      opacity: disabled ? 0.6 : 1.0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              entry.index.toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Expanded(
                            child: _buildPickTextBlock(text: l1),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.arrow_forward_ios,
                                size: 16, color: Colors.grey[600]),
                          ),
                          Expanded(
                            child: _buildPickTextBlock(
                              text: l2,
                              phonetic: text?.l2Phonetic,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
