import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:robulingo_flutter/constants.dart';
import 'package:robulingo_flutter/data/api_client.dart';
import 'package:robulingo_flutter/data/pick_manifest_service.dart';
import 'package:robulingo_flutter/data/hint_models.dart';
import 'package:robulingo_flutter/data/hints_service.dart';
import 'package:robulingo_flutter/data/models.dart';
import 'package:robulingo_flutter/data/user_curriculum_delta.dart';
import 'package:robulingo_flutter/data/user_curriculum_service.dart';
import 'package:robulingo_flutter/event_logger.dart';
import 'package:robulingo_flutter/logic/item_stats.dart';
import 'package:robulingo_flutter/logic/hexagon_controller.dart';
import 'package:robulingo_flutter/logic/ladder_controller.dart'
    show MoveEvent, MoveKind;
import 'package:robulingo_flutter/logic/naming_controller.dart';
import 'package:robulingo_flutter/logic/onboarding_store.dart';
import 'package:robulingo_flutter/logic/session_cache.dart';
import 'package:robulingo_flutter/logic/trial_buffer.dart';
import 'package:robulingo_flutter/logic/user_delta_store.dart';
import 'package:robulingo_flutter/logic/user_identity.dart';
import 'package:robulingo_flutter/logic/voice_state.dart';
import 'package:robulingo_flutter/ui/dashboard/dashboard_screen.dart';
import 'package:robulingo_flutter/ui/lang_selector.dart';
import 'package:robulingo_flutter/ui/mic_gate.dart';
import 'package:robulingo_flutter/ui/mic_progress_bar.dart';
import 'package:robulingo_flutter/ui/native_lang_selector.dart';
import 'package:robulingo_flutter/ui/session/session_widgets.dart';
import 'package:robulingo_flutter/ui/start_curriculum_selector.dart';
import 'package:robulingo_flutter/ui/training_calendar_panel.dart';
import 'package:robulingo_flutter/utils/platform_info.dart';
import 'package:robulingo_flutter/utils/text_utils.dart';

const Set<String> _phoneticEligibleLangs = {'el', 'ar', 'ru', 'zh', 'hi'};

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
//   - Naming-Gate: erst nach Zustimmung; Block bei Ablehnung/Timeout (5 Durchläufe).
//   - Rückwärtszüge im Rennen: nicht zweimal hintereinander auf derselben Kante, sonst Seitenwechsel.
//   - Seeds/Curriculum können fehlen (z.B. zh-Audio); Fehlermeldung prüfen.
// Willkürliche Parameter (Stand jetzt):
//   1) Muttersprache: Anzeige nur beim ersten Durchlauf pro Item (nativeSeenCounts < 1).
//   2) Rival-Startprognose: erste 10 Züge maxProb=0.9, danach skaliert mit letzter Accuracy.
//   3) Benennen: erst nach >=5 Comprehension-Versuchen mit >=4 korrekten Antworten und nach min. 5 unterschiedlichen Items (readyToName).
//   4) Naming-Zeitfenster: 5s erste Aufnahme, 5s Wiederholung.
//   5) Naming-Block: 5 Trials Pause nach Ablehnung/Timeout im Gate.
// ------------------------------------------------------------
class RobuLingoApp extends StatefulWidget {
  const RobuLingoApp({super.key});
  @override
  State<RobuLingoApp> createState() => _RobuLingoAppState();
}

class _RestartCurriculumMetadata {
  const _RestartCurriculumMetadata(
      {required this.totalItems, this.gratisValue});

  final int totalItems;
  final String? gratisValue;
}

class _RestartGratisInfo {
  const _RestartGratisInfo({required this.total, required this.remaining});

  final int total;
  final int remaining;
}

class _RobuLingoAppState extends State<RobuLingoApp>
    with TickerProviderStateMixin {
  static const int cachedItemCount = 12; // TODO: 500 im Zielzustand
  static const int namingMinCompAttempts = 2;
  static const int namingMinCompCorrect = 2;
  static const int namingMinUniqueItems = 2;
  late ApiClient api;
  late PickManifestService pickManifestService;
  late UserCurriculumService userCurriculumService;
  late HintsService hintsService;
  String workerHost = defaultWorkerHost;
  String apiPrefix = defaultApiPrefix;
  final AudioPlayer player = AudioPlayer();
  final AudioPlayer hintPlayer = AudioPlayer();
  final AudioPlayer fanfarePlayer = AudioPlayer();
  final AudioPlayer moveYouPlayer = AudioPlayer();
  final AudioPlayer moveRivalPlayer = AudioPlayer();
  final OnboardingStore onboardingStore = OnboardingStore();
  final SessionCacheStore sessionCacheStore = SessionCacheStore();
  final UserDeltaStore userDeltaStore = UserDeltaStore();
  final UserIdentity userIdentity = UserIdentity();
  UserCurriculumDelta? userDelta;
  bool resetCursorOnNextLoad = false;
  String? userId;
  bool awaitingLang = true;
  bool awaitingStart = false;
  bool awaitingNative = false;
  String? activeStartCurriculumKey;
  String? nativeLang; // Muttersprache; null = keine zweite Anzeige
  bool pickFlowActive = false;
  bool awaitingPickNative = false;
  bool pickListLoading = false;
  String? pickListError;
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
  bool get namingDisabled => voiceState.namingDisabled;
  set namingDisabled(bool value) => voiceState.namingDisabled = value;
  int get namingBlockRemaining => voiceState.namingBlockRemaining;
  set namingBlockRemaining(int value) =>
      voiceState.namingBlockRemaining = value;
  int get micGateToken => voiceState.micGateToken;
  set micGateToken(int value) => voiceState.micGateToken = value;
  bool get micGateGranted => voiceState.micGateGranted;
  set micGateGranted(bool value) => voiceState.micGateGranted = value;
  bool get micOn => voiceState.micOn;
  set micOn(bool value) => voiceState.micOn = value;
  int get micStage => voiceState.micStage;
  set micStage(int value) => voiceState.micStage = value;
  int get lastNamingAutoToken => voiceState.lastNamingAutoToken;
  set lastNamingAutoToken(int value) => voiceState.lastNamingAutoToken = value;
  late AnimationController micController;
  late Animation<double> micAnimation;
  final List<bool> lastTenResults =
      []; // letzte 10 Spieler-Ergebnisse (true = korrekt)

  String lang = 'de';
  HintPack? hintPack;
  int hintLoadToken = 0;
  final Set<String> hintRevealed = {};
  final GlobalKey _hintPanelKey = GlobalKey();
  List<CurriculumEntry> curriculum = [];
  int curriculumStartOffset = 0; // Delta-Cursor aus user_curriculum
  final TrialBuffer trialBuffer = TrialBuffer();
  late HexagonController ladderController;
  HexagonState get ladder => ladderController.state;
  List<ItemData> get items => trialBuffer.items;
  List<Trial> get trials => trialBuffer.trials;
  Set<String> get loadedUuids => trialBuffer.loadedUuids;
  final List<String> loadErrors = [];
  int trialIndex = 0;
  bool loading = true;
  bool batchLoading = false;
  String? error;
  bool hasAnswered = false;
  bool? lastCorrect;
  bool? lastSelectionIsLeft;
  Timer? nativeSelectTimer;
  final Map<String, int> correctCounts = {};
  final Map<String, int> audioPlayCounts = {};
  final Map<String, int> audioMaxSequenceIndex = {};
  final Map<String, bool> audioUrlOkCache = {};
  int currentTrialAudioToken = -1;
  String? currentTrialAudioUuid;
  Uri? currentTrialAudioUri;
  final Set<String> readyToName = {};
  final ItemStatsTracker itemStats = ItemStatsTracker();
  final List<bool> comprehensionHistory = [];
  final List<bool> namingHistory = [];
  final Set<String> comprehensionSeen = {};
  int selectionEpoch = 0; // bleibt für 2AFC erhalten
  int currentTrialToken =
      0; // entwertet alle asynchronen Tasks beim Trialwechsel/Hold
  bool sessionReady = false;
  StreamSubscription? playbackSub;
  late final EventLogger logger;
  bool loggerReady = false;
  DateTime? sessionStart;
  int dashboardViewCount =
      0; // zählt Dashboard-Opens, steuert Rival-Variante (alle 100 Wechsel)
  bool showRestartSplash =
      false; // Startbildschirm nur beim Wiederstart, nicht beim ersten Start
  bool sessionEnded = false;
  final Map<String, int> nativeSeenCounts =
      {}; // wie oft Ziel-Item angezeigt wurde
  final Map<String, int> phoneticSeenCounts =
      {}; // wie oft Items mit Lautschrift gezeigt wurden
  final Map<String, int> phoneticOverrideRemaining =
      {}; // noch aktive Phonetik-Zeichen für UUIDs
  int lastCloudLoadToken = 0;
  String? _cachedLocaleId;
  String? _cachedLocaleLang;
  RestartModuleProgress restartModuleProgress = RestartModuleProgress(
    iconAsset: startCurriculumIcons[defaultStartCurriculum] ??
        'assets/icons/cross.webp',
    progress: 0,
    completed: 0,
    total: 0,
    freeItemsTotal: 0,
    freeItemsRemaining: 0,
  );
  int _restartPanelInfoRequest = 0;

  @override
  void initState() {
    super.initState();
    logger = EventLogger();
    namingController = NamingController(
      speech: speech,
      onError: _handleSpeechError,
      onStatus: (s) => debugPrint('[asr][status] $s'),
    );
    player.setReleaseMode(ReleaseMode.stop);
    hintPlayer.setReleaseMode(ReleaseMode.stop);
    playbackSub = player.onPlayerStateChanged.listen((state) {
      debugPrint(
          '[audio] state=$state playing=${state == PlayerState.playing}');
    }, onError: (Object e, StackTrace st) {
      debugPrint('[audio][error-state] $e');
    });
    moveYouPlayer.setReleaseMode(ReleaseMode.stop);
    moveRivalPlayer.setReleaseMode(ReleaseMode.stop);
    micController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    micAnimation = CurvedAnimation(parent: micController, curve: Curves.linear);
    voiceController = VoiceController(
      speech: speech,
      namingController: namingController,
      micController: micController,
      state: voiceState,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );
    ladderController = HexagonController(
      onChanged: _onLadderChanged,
      onYouWin: _handleWinYou,
      onRivalWin: _handleWinRival,
      onMove: _handleLadderMove,
      accuracyProvider: () => lastTenResults,
    );
    api = ApiClient(workerHost: workerHost, apiPrefix: apiPrefix);
    pickManifestService = PickManifestService(api: api);
    userCurriculumService =
        UserCurriculumService(workerHost: workerHost, apiPrefix: apiPrefix);
    hintsService = HintsService(workerHost: workerHost, apiPrefix: apiPrefix);
    voiceController.initSpeech();
    _initLogger();
    _initUserId();
    _loadSavedOnboarding();
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
      final id = await userIdentity.loadOrCreate();
      if (!mounted) return;
      setState(() {
        userId = id;
      });
      _configureLoggerRemote();
      if (showRestartSplash) {
        unawaited(_updateRestartModuleProgress());
      }
    } catch (_) {
      // ignore
    }
  }

  void _configureLoggerRemote() {
    if (!loggerReady) return;
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

  void _onLadderChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleWinYou() {
    if (loggerReady) {
      unawaited(logger.log('win', {'side': 'you', 'lang': lang}));
    }
    unawaited(_persistUserCursor());
    setState(() {
      if (!sessionEnded) {
        sessionEnded =
            true; // Flagschlag zählt als Sieg, schaltet Dashboard frei
      }
    });
    _playFanfare();
    _saveOnboardingSnapshot();
  }

  void _handleWinRival() {
    if (loggerReady) {
      unawaited(logger.log('win', {'side': 'rival', 'lang': lang}));
    }
    unawaited(_persistUserCursor());
    setState(() {
      if (!sessionEnded) {
        sessionEnded = true;
      }
    });
    _playFanfare();
    _saveOnboardingSnapshot();
  }

  Future<void> _loadSavedOnboarding() async {
    final saved = await onboardingStore.load();
    if (!mounted || saved == null) return;
    setState(() {
      lang = saved.lang;
      activeStartCurriculumKey = saved.startKey;
      nativeLang = saved.nativeLang;
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
        trials.isNotEmpty &&
        trialIndex < trials.length &&
        hintRevealed.contains(trials[trialIndex].target.uuid)) {
      final normL2 = HintsService.normalizeLangCode(lang);
      final hintIds =
          trials[trialIndex].target.hintRefsByLang[normL2] ?? const <String>[];
      if (hintIds.isNotEmpty && pack.hintsForIds(hintIds).isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollHintPanelIntoView();
        });
      }
    }
  }

  void _toggleHintsForCurrent() {
    if (trials.isEmpty || trialIndex >= trials.length) return;
    final uuid = trials[trialIndex].target.uuid;
    final bool shouldReveal = !hintRevealed.contains(uuid);
    setState(() {
      if (hintRevealed.contains(uuid)) {
        hintRevealed.remove(uuid);
      } else {
        hintRevealed.add(uuid);
      }
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
          trials[trialIndex].target.hintRefsByLang[l2] ?? const <String>[];
      final resolved = hintPack!.hintsForIds(hintIds).length;
      debugPrint(
          '[hints][item] uuid=$uuid l1=$l1 l2=$l2 ids=${hintIds.length} resolved=$resolved');
    }
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
      final resetDelta = UserCurriculumDelta(cursor: -1);
      unawaited(userDeltaStore.save(userId!, resetDelta));
      unawaited(userCurriculumService.pushDelta(
          userId: userId!,
          startKey: activeStartCurriculumKey ?? defaultStartCurriculum,
          delta: resetDelta));
    }
    setState(() {
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
      trialIndex = 0;
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

  Future<void> _updateRestartModuleProgress() async {
    if (!showRestartSplash) return;
    final int requestId = ++_restartPanelInfoRequest;
    final startKey = activeStartCurriculumKey ?? defaultStartCurriculum;
    final iconAsset = _moduleIconForStart(startKey);
    final metadata = await _fetchRestartCurriculumMetadata(startKey);
    final cursor = await _loadRestartCursor();
    final int nextIndex = (cursor ?? -1) + 1;
    final int completed =
        metadata.totalItems > 0 ? nextIndex.clamp(0, metadata.totalItems) : 0;
    final int total = metadata.totalItems;
    final double progressValue =
        total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;
    final _RestartGratisInfo freeInfo =
        _calculateGratisInfo(metadata.gratisValue, total, completed);
    if (!mounted ||
        requestId != _restartPanelInfoRequest ||
        !showRestartSplash) {
      return;
    }
    setState(() {
      restartModuleProgress = RestartModuleProgress(
        iconAsset: iconAsset,
        progress: progressValue,
        completed: completed,
        total: total,
        freeItemsTotal: freeInfo.total,
        freeItemsRemaining: freeInfo.remaining,
      );
    });
  }

  Future<int?> _loadRestartCursor() async {
    final delta = userDelta ??
        (userId != null && userId!.isNotEmpty
            ? await userDeltaStore.load(userId!)
            : null);
    return delta?.cursor;
  }

  Future<_RestartCurriculumMetadata> _fetchRestartCurriculumMetadata(
      String startKey) async {
    try {
      final data = await api.loadStartCurriculumJson(
        startKey,
        allowDefaultFallback: true,
      );
      if (data == null) return const _RestartCurriculumMetadata(totalItems: 0);
      List items = (data['items'] as List?) ?? [];
      if (items.isEmpty && data['item_order'] is List) {
        items = data['item_order'] as List;
      }
      final total = items.length;
      return _RestartCurriculumMetadata(
        totalItems: total,
        gratisValue: (data['gratis'] as String?)?.trim(),
      );
    } catch (e) {
      debugPrint('[restart][curriculum-info] $e');
      return const _RestartCurriculumMetadata(totalItems: 0);
    }
  }

  _RestartGratisInfo _calculateGratisInfo(
      String? value, int total, int completed) {
    if (value == null || value.isEmpty) {
      return const _RestartGratisInfo(total: 0, remaining: 0);
    }
    final double? percent = _parsePercent(value);
    if (percent != null && total > 0) {
      final int freeItems = (total * (percent / 100)).round();
      final int remaining = max(0, freeItems - completed);
      return _RestartGratisInfo(total: freeItems, remaining: remaining);
    }
    return const _RestartGratisInfo(total: 0, remaining: 0);
  }

  double? _parsePercent(String raw) {
    final cleaned = raw.replaceAll(RegExp('[^0-9.,-]'), '');
    if (cleaned.isEmpty) return null;
    final normalized = cleaned.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  String _moduleIconForStart(String startKey) {
    return startCurriculumIcons[startKey] ??
        startCurriculumIcons[defaultStartCurriculum] ??
        'assets/icons/cross.webp';
  }

  Future<bool> _restoreFromCache() async {
    final cache = await sessionCacheStore.load();
    if (cache == null) return false;
    try {
      final cachedItems = cache.items
          .map((c) => ItemData(
                uuid: c.uuid,
                index: c.index,
                position: c.position,
                text: c.text,
                nativeText: c.nativeText,
                phonetic: c.phonetic,
                hintRefsByLang: c.hintRefsByLang,
                imageBytes: c.imageVariants.isNotEmpty
                    ? c.imageVariants.first
                    : c.imageBytes,
                imageVariants:
                    c.imageVariants.isEmpty ? [c.imageBytes] : c.imageVariants,
                audioUri: Uri.parse(c.audioUri),
                audioVariants:
                    c.audioVariants.map(Uri.parse).toList(growable: false),
                imageSignature: c.imageSignature,
              ))
          .toList();
      if (cachedItems.length < 2) return false;
      trialBuffer.replaceAll(cachedItems);
      ladderController.reset(clearWins: false);
      final savedIndex = cache.lastIndex
          .clamp(0, cachedItems.isEmpty ? 0 : cachedItems.length - 1);
      final savedUuid =
          cachedItems.isNotEmpty ? cachedItems[savedIndex].uuid : null;
      int idx = _trialIndexForNonReviewIndex(savedIndex);
      if (savedUuid != null && trials.isNotEmpty) {
        final found =
            trials.indexWhere((t) => !t.isReview && t.target.uuid == savedUuid);
        if (found >= 0) idx = found;
      }
      setState(() {
        lang = cache.lang;
        activeStartCurriculumKey = cache.startKey;
        nativeLang = cache.nativeLang;
        trialIndex = idx;
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
        namingInProgress = false;
        namingHold = false;
        micOn = false;
        micStage = -1;
      });
      sessionStart = DateTime.now().toUtc();
      logger.setSessionContext(
          startKey: activeStartCurriculumKey,
          lang: lang,
          nativeLang: nativeLang);
      _configureLoggerRemote();
      if (loggerReady) {
        unawaited(logger.startSession(lang: lang));
      }
      await _updateRivalIdleDays();
      _startTrial(currentTrialToken);
      unawaited(_ensureCurriculumLoaded());
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
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/logs/events.ndjson');
      if (!await file.exists()) return;
      final lines = await file.readAsLines();
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
      );
      final idleDays = data.idleDaysSince(DateTime.now().toUtc());
      ladderController.setRivalIdleDays(idleDays);
    } catch (_) {
      // ignore log errors
    }
  }

  Future<void> _openSettings() async {
    final hostCtrl = TextEditingController(text: workerHost);
    final prefixCtrl = TextEditingController(text: apiPrefix);
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
        api = ApiClient(workerHost: workerHost, apiPrefix: apiPrefix);
        pickManifestService = PickManifestService(api: api);
        userCurriculumService =
            UserCurriculumService(workerHost: workerHost, apiPrefix: apiPrefix);
        hintsService =
            HintsService(workerHost: workerHost, apiPrefix: apiPrefix);
      });
      _configureLoggerRemote();
      unawaited(_loadHintPack(forceRefresh: true));
      _loadInitial();
    }
  }

  void _handleSpeechError(String code) {
    if (code.toLowerCase().contains('no_match') ||
        code.toLowerCase().contains('no-match')) {
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

  void _onSelectLang(String l) {
    setState(() {
      lang = l;
      awaitingLang = false;
      awaitingStart = true;
      activeStartCurriculumKey = null;
      nativeLang = null;
      hintPack = null;
      hintRevealed.clear();
    });
  }

  Future<void> _onSelectStart(String fileName) async {
    nativeSelectTimer?.cancel();
    nativeSelectTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || !awaitingNative) return;
      _onSelectNative(null, fileName);
    });
    setState(() {
      awaitingStart = false;
      awaitingNative = true;
      activeStartCurriculumKey = fileName;
    });
  }

  void _enterPickFlow() {
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
    _resetPickSelection();
    await _loadInitial(startKey: key);
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
      hintRevealed.clear();
    });
    unawaited(_loadHintPack(forceRefresh: true));
    await _loadInitial(startKey: startKey);
  }

  Future<void> _loadInitial({String? startKey}) async {
    // Initialer Ladepfad: UI zurücksetzen, Curriculum holen,
    // dann so viele Batches laden, bis mindestens 1 valides Item da ist
    // oder nichts Brauchbares gefunden wird.
    lastCloudLoadToken++;
    if (!resetCursorOnNextLoad) {
      await _persistUserCursor();
    }
    if (loggerReady && sessionStart != null) {
      unawaited(logger.endSession());
    }
    final previousStartKey = activeStartCurriculumKey;
    final baseStart = startKey ?? previousStartKey ?? defaultStartCurriculum;
    final bool explicitStartRequested =
        startKey != null || previousStartKey != null;
    var resolvedStart = await _startCurriculumKeyForLanguage(baseStart);
    activeStartCurriculumKey = resolvedStart;
    _saveOnboardingSnapshot(startKey: resolvedStart);
    ladderController.reset(clearWins: true);
    setState(() {
      awaitingLang = false;
      awaitingStart = false;
      awaitingNative = false;
      loading = true;
      error = null;
      trialIndex = 0;
      trialBuffer.reset();
      loadErrors.clear();
      hasAnswered = false;
      lastCorrect = null;
      lastSelectionIsLeft = null;
      micPromptActive = false;
      micDenied = false;
      nativeSelectTimer?.cancel();
      correctCounts.clear();
      audioPlayCounts.clear();
      audioMaxSequenceIndex.clear();
      audioUrlOkCache.clear();
      currentTrialAudioToken = -1;
      currentTrialAudioUuid = null;
      currentTrialAudioUri = null;
      readyToName.clear();
      comprehensionSeen.clear();
      itemStats.reset();
      comprehensionHistory.clear();
      namingHistory.clear();
      namingInProgress = false;
      namingStatus = '';
      namingDisabled = false;
      _liveTranscript = '';
      currentTrialToken = 0;
      sessionStart = DateTime.now().toUtc();
      sessionEnded = false;
      nativeSeenCounts.clear();
      curriculumStartOffset = 0;
      hintRevealed.clear();
    });
    logger.setSessionContext(
        startKey: resolvedStart, lang: lang, nativeLang: nativeLang);
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
      try {
        curriculum = await api.loadStartCurriculum(resolvedStart,
            allowDefaultFallback: allowDefaultFallback,
            requireCompleteForLang: lang);
        if (curriculum.isEmpty && resolvedStart != baseStart) {
          final previousStart = resolvedStart;
          resolvedStart = baseStart;
          activeStartCurriculumKey = resolvedStart;
          _saveOnboardingSnapshot(startKey: resolvedStart);
          logger.setSessionContext(
              startKey: resolvedStart, lang: lang, nativeLang: nativeLang);
          loadErrors.add(
              'Start-Curriculum leer ($previousStart) -> verwende $resolvedStart.');
          curriculum = await api.loadStartCurriculum(resolvedStart,
              allowDefaultFallback: allowDefaultFallback,
              requireCompleteForLang: lang);
        }
      } catch (e) {
        if (resolvedStart != baseStart) {
          final failedStart = resolvedStart;
          loadErrors.add(
              'Start-Curriculum fehlgeschlagen ($failedStart): $e, versuche $baseStart');
          resolvedStart = baseStart;
          activeStartCurriculumKey = resolvedStart;
          _saveOnboardingSnapshot(startKey: resolvedStart);
          logger.setSessionContext(
              startKey: resolvedStart, lang: lang, nativeLang: nativeLang);
          try {
            curriculum = await api.loadStartCurriculum(resolvedStart,
                allowDefaultFallback: allowDefaultFallback,
                requireCompleteForLang: lang);
          } catch (baseError) {
            if (explicitStartRequested) {
              rethrow;
            }
            loadErrors.add(
                'Start-Curriculum fehlgeschlagen ($resolvedStart): $baseError');
            curriculum = await api.loadCurriculum(lang);
          }
        } else {
          if (explicitStartRequested) {
            rethrow; // explizite Auswahl darf nicht still auf A/lang fallen
          }
          // Fallback: normales Curriculum nach Sprache laden, Fehler merken
          loadErrors
              .add('Start-Curriculum fehlgeschlagen ($resolvedStart): $e');
          curriculum = await api.loadCurriculum(lang);
        }
      }
      await _maybeApplyUserCurriculumDelta(resolvedStart);
      if (curriculum.isEmpty) {
        setState(() {
          loading = false;
          error =
              'Kein Curriculum gefunden. Prüfe Start-Curriculum ($resolvedStart) in R2 oder Worker-Host.';
        });
        return;
      }

      // Seed: erste Items mit Audio für alle Sprachen vorziehen
      await _loadSeeds();

      // Lade nur initialItemDownloadLimit Items, der Rest folgt über die Refresh-/Prefetch-Logik.
      var offset = _nextCurriculumOffset();
      var attempts = 0;
      while (items.length < initialItemDownloadLimit &&
          attempts < curriculum.length + 1 &&
          curriculum.isNotEmpty) {
        final remaining = initialItemDownloadLimit - items.length;
        final batchLimit =
            remaining > 0 ? min(remaining, batchSize) : batchSize;
        await _loadBatch(offset, maxEntries: batchLimit);
        attempts++;
        offset = _nextCurriculumOffset();
      }

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
        // Ersten Trial automatisch mit Audio starten, sobald UI steht.
        if (mounted && trials.isNotEmpty) {
          final token = currentTrialToken;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startTrial(token);
          });
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
    if (startKey.toLowerCase().startsWith('pick_')) {
      return startKey;
    }
    final candidate = _startCurriculumKeyWithLangSuffix(startKey, lang);
    return candidate == startKey ? startKey : candidate;
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

  int _nonReviewIndexForTrial(int idx) {
    if (trials.isEmpty) return 0;
    int count = 0;
    for (int i = 0; i <= idx && i < trials.length; i++) {
      if (!trials[i].isReview) {
        count++;
      }
    }
    return count > 0 ? count - 1 : 0;
  }

  int _trialIndexForNonReviewIndex(int nonReviewIndex) {
    if (trials.isEmpty) return 0;
    int count = -1;
    for (int i = 0; i < trials.length; i++) {
      if (!trials[i].isReview) {
        count++;
      }
      if (count == nonReviewIndex) return i;
    }
    return 0;
  }

  int _currentCursorIndex() {
    if (curriculum.isEmpty) return 0;
    final nonReviewIndex = _nonReviewIndexForTrial(trialIndex);
    return (curriculumStartOffset + nonReviewIndex) % curriculum.length;
  }

  Future<void> _persistUserCursor() async {
    if (userId == null || userId!.isEmpty) return;
    if (curriculum.isEmpty) return;
    final startKey = activeStartCurriculumKey ?? defaultStartCurriculum;
    final cursor = _currentCursorIndex();
    final nextDelta = (userDelta ?? UserCurriculumDelta()).withCursor(cursor);
    userDelta = nextDelta;
    unawaited(userDeltaStore.save(userId!, nextDelta));
    unawaited(userCurriculumService.pushDelta(
        userId: userId!, startKey: startKey, delta: nextDelta));
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

  void _maybePrefetch() {
    if (batchLoading || curriculum.isEmpty) return;
    final remaining = trials.length - trialIndex - 1;
    final threshold = (prefetchWindowSize * prefetchThreshold).ceil();
    if (remaining <= threshold) {
      unawaited(_loadBatch(_nextCurriculumOffset()));
    }
  }

  Future<void> _persistSessionCache() async {
    if (items.isEmpty || trials.isEmpty) return;
    final current = trials[trialIndex % trials.length].target;
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
    final base = variants.first;
    final sequence = <Uri>[base, base];
    if (variants.length > 1) {
      sequence
        ..add(variants[1])
        ..add(variants[1]);
    }
    if (variants.length > 2) {
      sequence.add(variants[2]);
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

  Future<bool> _audioUrlOkCached(Uri uri) async {
    final key = uri.toString();
    final cached = audioUrlOkCache[key];
    if (cached != null) return cached;
    final ok = await api.audioUrlOk(uri);
    audioUrlOkCache[key] = ok;
    return ok;
  }

  Uri _audioUriForItem(ItemData item, {required bool advance}) {
    final bool alreadyAssigned = currentTrialAudioToken == currentTrialToken &&
        currentTrialAudioUuid == item.uuid &&
        currentTrialAudioUri != null;
    if (alreadyAssigned) return currentTrialAudioUri!;
    final sequence = _audioSequenceForItem(item);
    final count = audioPlayCounts[item.uuid] ?? 0;
    final maxIndex = audioMaxSequenceIndex[item.uuid];
    int index = count < sequence.length ? count : sequence.length - 1;
    if (maxIndex != null && maxIndex < index) {
      index = maxIndex;
    }
    final chosen = sequence[index];
    if (advance) {
      audioPlayCounts[item.uuid] = count + 1;
      currentTrialAudioToken = currentTrialToken;
      currentTrialAudioUuid = item.uuid;
      currentTrialAudioUri = chosen;
    }
    return chosen;
  }

  Future<bool> _playAudioUri(Uri uri) async {
    try {
      await player.stop();
      await player.play(UrlSource(uri.toString()));
      return true;
    } catch (e) {
      debugPrint('[audio][error] url=$uri err=$e');
      return false;
    }
  }

  Future<void> _playAudioForItem(ItemData item, {bool advance = false}) async {
    final sequence = _audioSequenceForItem(item);
    var uri = _audioUriForItem(item, advance: advance);
    final initialIndex = sequence.lastIndexOf(uri);
    if (initialIndex >= 0) {
      final ok = await _audioUrlOkCached(uri);
      if (!ok) {
        final fallbackIndex =
            await _previousPlayableIndex(sequence, initialIndex);
        if (fallbackIndex != null) {
          final fallbackUri = sequence[fallbackIndex];
          audioMaxSequenceIndex[item.uuid] = fallbackIndex;
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
    final ok = await _playAudioUri(uri);
    if (ok) return;
    if (playedIndex < 0) return;
    final fallbackIndex = _previousVariantIndex(sequence, playedIndex);
    if (fallbackIndex == null) return;
    final fallbackUri = sequence[fallbackIndex];
    audioMaxSequenceIndex[item.uuid] = fallbackIndex;
    final bool updateCache = advance ||
        (currentTrialAudioToken == currentTrialToken &&
            currentTrialAudioUuid == item.uuid);
    if (updateCache) {
      currentTrialAudioToken = currentTrialToken;
      currentTrialAudioUuid = item.uuid;
      currentTrialAudioUri = fallbackUri;
    }
    debugPrint('[audio][fallback] uuid=${item.uuid} from=$uri to=$fallbackUri');
    await _playAudioUri(fallbackUri);
  }

  Future<int?> _previousPlayableIndex(
      List<Uri> sequence, int startIndex) async {
    var index = _previousVariantIndex(sequence, startIndex);
    while (index != null) {
      final candidate = sequence[index];
      if (await _audioUrlOkCached(candidate)) return index;
      index = _previousVariantIndex(sequence, index);
    }
    return null;
  }

  Future<void> _playHintAudioForItem(ItemData item) async {
    final base = item.audioVariants.isNotEmpty
        ? item.audioVariants.first
        : item.audioUri;
    await _playHintUri(base);
  }

  Future<void> _playHintUri(Uri uri) async {
    try {
      await hintPlayer.stop();
      await hintPlayer.play(UrlSource(uri.toString()));
      await hintPlayer.onPlayerComplete.first;
    } catch (e) {
      debugPrint('[audio][hint-error] url=$uri err=$e');
    }
  }

  Future<void> _playNextTrialAudio(int token) async {
    if (!mounted || token != currentTrialToken) return;
    if (trialIndex >= trials.length) return;
    final item = trials[trialIndex].target;
    await _playAudioForItem(item, advance: true);
  }

  bool _isNamingTrial() {
    if (namingDisabled) return false;
    if (trialIndex >= trials.length) return false;
    if (namingBlockRemaining > 0) return false;
    // Keep 2AFC feedback visible even if the item just became "ready to name".
    if (hasAnswered && !namingInProgress && namingOutcome == null) return false;
    final int uniqueNeeded = min(namingMinUniqueItems, max(1, items.length));
    if (comprehensionSeen.length < uniqueNeeded) return false;
    return readyToName.contains(trials[trialIndex].target.uuid);
  }

  bool _shouldShowNative(ItemData item) {
    if (nativeLang == null) return false;
    if (item.nativeText == null || item.nativeText!.isEmpty) return false;
    final seen = nativeSeenCounts[item.uuid] ?? 0;
    return seen == 0 || seen == 1 || seen == 3;
  }

  Future<void> _startTrial(int token) async {
    if (!mounted || token != currentTrialToken) return;
    if (namingHold) return; // Benennen wartet auf Button (nur für 2AFC)
    unawaited(_persistSessionCache());
    if (_isNamingTrial()) {
      if (!micPrimed) {
        setState(() {
          micPromptActive = true;
          namingStatus = 'Tippe das Mikro, um Benennen zu starten.';
        });
        return;
      }
      debugPrint('[trial][start] idx=$trialIndex token=$token naming=true');
      return _startNamingFlow(token);
    } else {
      debugPrint('[trial][start] idx=$trialIndex token=$token naming=false');
      return _playNextTrialAudio(token);
    }
  }

  Future<void> _openMicSettings() async {
    setState(() {
      namingStatus = 'Einstellungen öffnen...';
    });
    await openAppSettings();
    if (!mounted) return;
    final ready = await voiceController.ensureMicReady();
    if (!mounted) return;
    setState(() {
      micDenied = !ready;
      namingHold = !ready;
      micPermanentlyDenied = voiceState.micPermanentlyDenied;
      speechPermanentlyDenied = voiceState.speechPermanentlyDenied;
      if (ready) {
        namingStatus = '';
      } else if (micPermanentlyDenied || speechPermanentlyDenied) {
        namingStatus =
            'Bitte erlaube Mikrofon/Spracherkennung in den Einstellungen.';
      } else {
        namingStatus = 'Mic/Sprache nicht erlaubt. Tippe Aufnehmen erneut.';
      }
    });
  }

  Future<void> _primeMicAndStart({bool skipGate = false}) async {
    if (namingInProgress) return;
    final token = currentTrialToken;
    debugPrint(
        '[naming][prime] token=$token skipGate=$skipGate gateGranted=$micGateGranted primed=$micPrimed');
    setState(() {
      micDenied = false;
    });
    if (!await voiceController.ensureMicReady(onPermanentDisable: () {
      setState(() {
        micDenied = true;
      });
    })) {
      setState(() {
        micDenied = true;
        if (namingStatus.isEmpty) {
          namingStatus = micPermanentlyDenied || speechPermanentlyDenied
              ? 'Mikro dauerhaft gesperrt. Öffne die Einstellungen.'
              : 'Mikro gesperrt.';
        }
      });
      return;
    }
    setState(() {
      micPrimed = true;
      micPromptActive = false;
      namingStatus = '';
    });
    lastNamingAutoToken = -1; // nächsten Naming-Autostart erlauben
    await _startNamingFlow(token, skipGate: skipGate, userInitiated: true);
  }

  void _completeNamingSession(
      {required int token, required bool wasCorrect, required int moves}) {
    if (!mounted || token != currentTrialToken) return;
    namingInProgress = false;
    micOn = false;
    micStage = -1;
    micController.stop();
    if (moves > 0) {
      for (int i = 0; i < moves; i++) {
        _advancePlayer(true);
      }
    }
    setState(() {
      namingStatus = '';
      namingOutcome = wasCorrect;
      _liveTranscript = _liveTranscript;
      hasAnswered = false;
    });
    debugPrint(
        '[naming][flow-end] token=$token correct=$wasCorrect moves=$moves');
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      if (token != currentTrialToken) return;
      _gotoNextTrial();
    });
  }

  Future<void> _startNamingFlow(int token,
      {bool skipGate = false, bool userInitiated = false}) async {
    if (namingInProgress || !_isNamingTrial()) return;
    if (token != currentTrialToken) return;
    if (!skipGate && _showMicGateIfNeeded(token)) return;
    debugPrint(
        '[naming][flow-start] token=$token gateGranted=$micGateGranted primed=$micPrimed');
    if (!micPrimed) {
      setState(() {
        micPromptActive = true;
        namingStatus = 'Tippe das Mikro, um Benennen zu starten.';
      });
      return;
    }
    setState(() {
      hasAnswered = true; // block Selektionen/Advances während Naming
    });
    const int windowFirst = 5; // mehr Zeit für erste Aufnahme
    const int windowRepeat = 5;
    // Temporär ohne Locale, um iOS-Speech-Engines nicht zu blockieren.
    final String? localeId =
        (isIOS || isMacOS) ? null : await _resolveLocaleId();
    bool isCurrent() => mounted && token == currentTrialToken;
    final result = await voiceController.startNamingFlow(
      token: token,
      targetText: trials[trialIndex].target.text,
      scorer: _isTranscriptCorrect,
      playHint: () async {
        if (!isCurrent()) return;
        await _playHintAudioForItem(trials[trialIndex].target);
      },
      onTranscript: (text) {
        if (!isCurrent()) return;
        debugPrint(
            '[naming][asr] heard="$text" target="${trials[trialIndex].target.text}"');
        setState(() {
          _liveTranscript = text;
        });
      },
      isCurrent: isCurrent,
      userInitiated: userInitiated,
      firstWindow: const Duration(seconds: windowFirst),
      repeatWindow: const Duration(seconds: windowRepeat),
      allowRepeat: true,
      localeId: localeId,
    );

    if (!mounted || token != currentTrialToken) return;

    if (result == null) {
      setState(() {
        namingOutcome = null;
        hasAnswered = false;
      });
      return;
    }

    final wasCorrect = result.moves > 0;
    final uuid = trials[trialIndex].target.uuid;
    debugPrint(
        '[naming][scored] transcript="${result.transcript}" target="${trials[trialIndex].target.text}" correct=$wasCorrect moves=${result.moves}');
    itemStats.addNaming(uuid, wasCorrect);
    if (loggerReady) {
      unawaited(logger.log('naming_result',
          {'lang': lang, 'uuid': uuid, 'correct': wasCorrect}));
    }
    namingHistory.add(wasCorrect);
    if (!wasCorrect) {
      readyToName.remove(trials[trialIndex].target.uuid);
    }
    _liveTranscript = result.transcript;
    _completeNamingSession(
        token: token, wasCorrect: wasCorrect, moves: result.moves);
  }

  Future<String?> _resolveLocaleId() async {
    if (_cachedLocaleLang == lang && _cachedLocaleId != null) {
      return _cachedLocaleId;
    }
    try {
      final locales = await speech.locales();
      final target = lang.toLowerCase();
      final override = speechLocaleOverrides[lang]?.toLowerCase();
      String normalize(String value) => value.replaceAll('_', '-');
      if (locales.isEmpty) {
        if (override != null) {
          _cachedLocaleId = override;
          _cachedLocaleLang = lang;
          return _cachedLocaleId;
        }
        _cachedLocaleId = target;
        _cachedLocaleLang = lang;
        return _cachedLocaleId;
      }
      final exact = locales.firstWhere(
        (l) {
          final id = l.localeId.toLowerCase();
          final normalized = normalize(id);
          if (override != null) {
            final overrideNorm = normalize(override);
            return normalized == overrideNorm ||
                normalized.startsWith('$overrideNorm-');
          }
          return id == target ||
              id.startsWith('$target-') ||
              id.startsWith('${target}_');
        },
        orElse: () => locales.first,
      );
      _cachedLocaleId = exact.localeId;
      _cachedLocaleLang = lang;
      return _cachedLocaleId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _skipNaming(String reason) async {
    if (!mounted) return;
    debugPrint('[naming][skip] reason=$reason token=$currentTrialToken');
    voiceController.cancelActive();
    setState(() {
      namingOutcome = null;
      namingStatus = '';
    });
    _gotoNextTrial();
  }

  Future<void> _select(bool choseLeft) async {
    if (trials.isEmpty || hasAnswered || namingInProgress || _isNamingTrial()) {
      return;
    }
    final trial = trials[trialIndex];
    final correct = choseLeft == trial.targetOnLeft;
    debugPrint(
        '[select] idx=$trialIndex token=$currentTrialToken naming=${_isNamingTrial()} choseLeft=$choseLeft targetOnLeft=${trial.targetOnLeft} correct=$correct');
    // Ergebnis für Gleitfenster speichern (max 10)
    lastTenResults.add(correct);
    if (lastTenResults.length > 10) {
      lastTenResults.removeAt(0);
    }
    comprehensionSeen.add(trial.target.uuid);
    comprehensionHistory.add(correct);
    itemStats.addComprehension(trial.target.uuid, correct);
    if (loggerReady) {
      unawaited(logger.log('trial_result', {
        'lang': lang,
        'uuid': trial.target.uuid,
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
    final bool hasNext = trialIndex + 1 < trials.length;
    setState(() {
      hasAnswered = true;
      lastCorrect = correct;
      lastSelectionIsLeft = choseLeft;
    });
    if (!mounted || currentEpoch != selectionEpoch) return;
    if (!hasNext) {
      debugPrint('[audio][no-next] trials=${trials.length} idx=$trialIndex');
      final added = await _loadBatch(_nextCurriculumOffset());
      // versuche nachzuladen, falls Curriculum noch mehr hat
      final bool canAdvance = trialIndex + 1 < trials.length;
      if (canAdvance) {
        _advanceToNext(currentEpoch, token: token);
      } else if (!added && trials.isNotEmpty) {
        // Harte Schleife: zurück zum Anfang und weitermachen.
        setState(() {
          trialIndex = 0;
          hasAnswered = false;
          lastCorrect = null;
          lastSelectionIsLeft = null;
          currentTrialToken++;
        });
        final t = currentTrialToken;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startTrial(t);
        });
      }
      return;
    }
    _advanceToNext(currentEpoch, token: token);
  }

  void _advanceToNext(int epoch, {int? token}) {
    final t = token ?? currentTrialToken;
    // Im Benennen-Modus nie auto-advance; nur Weiter-Button darf wechseln.
    final bool namingActive = _isNamingTrial() || namingInProgress;
    if (namingHold || namingActive) return;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || epoch != selectionEpoch) return;
      if (t != currentTrialToken) return;
      final bool namingActiveInner = _isNamingTrial() || namingInProgress;
      if (namingHold || namingActiveInner) return;
      _gotoNextTrial();
    });
  }

  void _gotoNextTrial() {
    if (namingInProgress) {
      debugPrint(
          '[trial][next-blocked] namingInProgress=true token=$currentTrialToken idx=$trialIndex');
      return;
    }
    voiceController.cancelActive();
    if (trials.isNotEmpty) {
      final current = trials[trialIndex].target;
      if (nativeLang != null) {
        nativeSeenCounts[current.uuid] =
            (nativeSeenCounts[current.uuid] ?? 0) + 1;
      }
      phoneticSeenCounts[current.uuid] =
          (phoneticSeenCounts[current.uuid] ?? 0) + 1;
      final overrideRemaining = phoneticOverrideRemaining[current.uuid];
      if (overrideRemaining != null) {
        final next = overrideRemaining - 1;
        if (next > 0) {
          phoneticOverrideRemaining[current.uuid] = next;
        } else {
          phoneticOverrideRemaining.remove(current.uuid);
        }
      }
    }
    if (namingBlockRemaining > 0) {
      namingBlockRemaining = max(0, namingBlockRemaining - 1);
      if (namingBlockRemaining == 0) {
        micGateGranted = false;
        micGateToken = -1;
      }
    }
    setState(() {
      trialIndex = (trialIndex + 1) % trials.length;
      hasAnswered = false;
      lastCorrect = null;
      lastSelectionIsLeft = null;
      currentTrialToken++; // entwertet alte async Tasks
      namingOutcome = null;
      namingHold = false;
      namingStatus = '';
      _liveTranscript = '';
    });
    final token = currentTrialToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTrial(token);
    });
    _maybePrefetch();
    debugPrint(
        '[trial][next] idx=$trialIndex token=$token block=$namingBlockRemaining gateGranted=$micGateGranted');
  }

  void _reinstatePhoneticsFor(ItemData item) {
    setState(() {
      phoneticOverrideRemaining[item.uuid] = 10;
    });
  }

  bool _showMicGateIfNeeded(int token) {
    if (!_isNamingTrial()) return false;
    if (micGateGranted) return false;
    if (micGateToken == token) return false;
    micGateToken = token;
    debugPrint(
        '[naming][gate-open] token=$token trialIdx=$trialIndex block=$namingBlockRemaining');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != currentTrialToken) return;
      Navigator.of(context)
          .push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MicGate(
            onAllow: () => Navigator.of(context).pop('allow'),
            onDeny: () => Navigator.of(context).pop('deny'),
            onTimeout: () => Navigator.of(context).pop('timeout'),
          ),
        ),
      )
          .then((result) {
        if (!mounted || token != currentTrialToken) return;
        micGateToken = -1;
        if (result == 'allow') {
          micGateGranted = true;
          micPrimed = true;
          _primeMicAndStart(skipGate: true);
        } else {
          // deny oder timeout: Block setzen und weiter, Gate später erneut zeigen
          setState(() {
            namingBlockRemaining = 20;
            namingOutcome = null;
            namingStatus = '';
            micPrimed = false;
            micGateGranted = false;
          });
          _gotoNextTrial();
        }
        debugPrint(
            '[naming][gate-close] token=$token result=$result block=$namingBlockRemaining');
      });
    });
    return true;
  }

  void _advancePlayer(bool correct) {
    final targetUuid = trials[trialIndex].target.uuid;
    if (correct) {
      final count = (correctCounts[targetUuid] ?? 0) + 1;
      correctCounts[targetUuid] = count;
    }
    final stats = itemStats.statsFor(targetUuid);
    final compAttempts = stats.compAttempts;
    final compCorrect = stats.compCorrect;
    final bool wasReady = readyToName.contains(targetUuid);
    if (!namingDisabled &&
        compAttempts >= namingMinCompAttempts &&
        compCorrect >= namingMinCompCorrect) {
      readyToName.add(targetUuid);
      if (loggerReady && !wasReady) {
        unawaited(logger.log('item_mastered', {
          'lang': lang,
          'uuid': targetUuid,
          'correct_count': compCorrect,
          'attempts': compAttempts,
        }));
      }
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
      await playerToUse.play(AssetSource(asset));
    } catch (_) {
      // leise scheitern, falls Asset fehlt
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
    );
    unawaited(onboardingStore.save(data));
  }

  @override
  void dispose() {
    playbackSub?.cancel();
    player.dispose();
    hintPlayer.dispose();
    fanfarePlayer.dispose();
    moveYouPlayer.dispose();
    moveRivalPlayer.dispose();
    voiceController.cancelActive();
    ladderController.dispose();
    micController.dispose();
    nativeSelectTimer?.cancel();
    unawaited(_persistUserCursor());
    if (loggerReady) {
      unawaited(logger.endSession());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (awaitingLang) {
      return Scaffold(
        body: SafeArea(
          child: LangSelector(
            onSelect: _onSelectLang,
          ),
        ),
      );
    }

    if (pickFlowActive) {
      if (awaitingPickNative) {
        return Scaffold(
          body: SafeArea(
            child: NativeLangSelector(
              targetLang: lang,
              onSelect: _onSelectPickNative,
            ),
          ),
        );
      }
      return Scaffold(
        body: SafeArea(
          child: _buildPickMenu(),
        ),
      );
    }

    if (awaitingStart) {
      return Scaffold(
        body: SafeArea(
          child: StartCurriculumSelector(
            onSelect: _onSelectStart,
            onPickSelected: _enterPickFlow,
          ),
        ),
      );
    }

    if (awaitingNative && activeStartCurriculumKey != null) {
      return Scaffold(
        body: SafeArea(
          child: NativeLangSelector(
            targetLang: lang,
            onSelect: (mother) =>
                _onSelectNative(mother, activeStartCurriculumKey!),
          ),
        ),
      );
    }

    if (showRestartSplash) {
      return RestartSplash(
        wins: ladder.winsYou,
        rivalWins: ladder.winsRival,
        viewCount: dashboardViewCount,
        onRestart: () => _restartOnboarding(),
        onStart: _startFromSplash,
        moduleProgress: restartModuleProgress,
      );
    }

    Widget body;
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
    } else if (trials.isEmpty) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Zu wenige Items für Lingomatch (mind. 2 benötigt).'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadInitial,
              icon: const Icon(Icons.refresh),
              label: const Text('Neu laden'),
            ),
          ],
        ),
      );
    } else if (trialIndex >= trials.length) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Keine weiteren Trials.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadInitial,
              icon: const Icon(Icons.refresh),
              label: const Text('Neu laden'),
            ),
          ],
        ),
      );
    } else {
      final trial = trials[trialIndex];
      final leftImg = trial.targetOnLeft
          ? trial.targetImageBytes
          : trial.distractorImageBytes;
      final rightImg = trial.targetOnLeft
          ? trial.distractorImageBytes
          : trial.targetImageBytes;
      final size = MediaQuery.of(context).size;
      final bool isLandscape = size.width > size.height;
      final double imageHeight = isLandscape
          ? min(size.height * 0.38, min(size.width * 0.55, 320.0))
          : min(size.height * 0.38, 320.0);
      final bool isNamingTrial = _isNamingTrial();
      final bool isNamingView =
          isNamingTrial || namingInProgress || namingOutcome != null;
      final bool showDashboardButton =
          ladder.hasFlagAppeared || ladder.winsYou > 0 || ladder.winsRival > 0;
      final bool showHourglass = namingInProgress || batchLoading || loading;
      if (isNamingTrial) {
        _showMicGateIfNeeded(currentTrialToken);
        if (micGateGranted &&
            micPrimed &&
            !namingHold &&
            !namingInProgress &&
            namingOutcome == null &&
            lastNamingAutoToken != currentTrialToken) {
          lastNamingAutoToken = currentTrialToken;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _startNamingFlow(currentTrialToken, skipGate: true);
          });
        }
      }

      final bool hasPhoneticData = trial.target.phonetic != null &&
          trial.target.phonetic!.isNotEmpty &&
          _phoneticEligibleLangs.contains(lang);
      final int phoneticSeen = phoneticSeenCounts[trial.target.uuid] ?? 0;
      final int phoneticOverrideCount =
          phoneticOverrideRemaining[trial.target.uuid] ?? 0;
      final bool phoneticOverrideActive = phoneticOverrideCount > 0;
      final bool showPhonetic =
          hasPhoneticData && (phoneticSeen < 4 || phoneticOverrideActive);
      final bool showNative = _shouldShowNative(trial.target);
      final bool hintsEnabled =
          nativeLang != null && nativeLang!.trim().isNotEmpty;
      final String normL1 =
          hintsEnabled ? HintsService.normalizeLangCode(nativeLang) : '';
      final String normL2 = HintsService.normalizeLangCode(lang);
      final bool hintPackMatches =
          hintPack != null && hintPack!.l1 == normL1 && hintPack!.l2 == normL2;
      final List<String> hintIds = hintPackMatches
          ? (trial.target.hintRefsByLang[normL2] ?? const <String>[])
          : const <String>[];
      final bool showHintsInline =
          !isNamingView && hintPackMatches && hintIds.isNotEmpty;
      final bool hintRevealedForItem =
          showHintsInline && hintRevealed.contains(trial.target.uuid);
      final List<HintContent> hintEntries = showHintsInline
          ? hintPack!.hintsForIds(hintIds)
          : const <HintContent>[];
      final String hintLabel =
          hintsEnabled ? HintsService.hintLabelFor(nativeLang!) : 'Hint';
      final String? hintMissingText =
          showHintsInline && hintIds.isNotEmpty && hintEntries.isEmpty
              ? 'No hint text found for ids: ${hintIds.join(', ')}'
              : null;
      body = SessionBody(
        ladder: ladder,
        isNaming: isNamingView,
        imageHeight: imageHeight,
        leftImageBytes: leftImg,
        rightImageBytes: rightImg,
        targetOnLeft: trial.targetOnLeft,
        hasAnswered: hasAnswered,
        lastSelectionIsLeft: lastSelectionIsLeft,
        namingOutcome: namingOutcome,
        namingStatus: namingStatus,
        micPrimed: micPrimed,
        micDenied: micDenied,
        micPermanentlyDenied: micPermanentlyDenied,
        speechPermanentlyDenied: speechPermanentlyDenied,
        namingHold: namingHold,
        showHourglass: showHourglass,
        namingInProgress: namingInProgress,
        liveTranscript: _liveTranscript,
        targetText: trial.target.text,
        targetPhonetic: showPhonetic ? trial.target.phonetic : null,
        phoneticButtonVisible: hasPhoneticData,
        phoneticOverrideActive: phoneticOverrideActive,
        phoneticOverrideRemaining: phoneticOverrideCount,
        onTogglePhonetic:
            hasPhoneticData ? () => _reinstatePhoneticsFor(trial.target) : null,
        spokenCueText: !isNamingView ? trial.target.text : null,
        nativeText: trial.target.nativeText,
        showNative: showNative,
        hintEntries: hintEntries,
        hintLabel: hintLabel,
        hintMissingText: hintMissingText,
        hintButtonVisible: false,
        hintButtonActive: hintRevealedForItem,
        onToggleHints: _toggleHintsForCurrent,
        hintPanelKey: _hintPanelKey,
        audioHintEnabled: !isNamingView,
        onPlayAudioHint: () {
          unawaited(_playHintAudioForItem(trial.target));
        },
        showDashboardButton: showDashboardButton,
        showGlobalHourglass: showGlobalHourglass,
        onPrimeMic: _primeMicAndStart,
        onOpenMicSettings: _openMicSettings,
        onSkipNaming: _skipNaming,
        onSelect: _select,
        onOpenDashboard: () {
          if (!sessionEnded) {
            _finishSession();
          }
          _openDashboardPreview(context, focus: 'wins');
        },
      );
    }

    return Scaffold(
      bottomNavigationBar: namingInProgress
          ? SizedBox(
              height: 48,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: MicProgressBar(
                    animation: micAnimation, micStage: micStage, micOn: micOn),
              ),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: body,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openDashboardPreview(BuildContext context, {required String focus}) {
    final mastered = readyToName.length;
    final wins = ladder.winsYou;
    final rivalWins = ladder.winsRival;
    setState(() {
      dashboardViewCount++;
    });
    Navigator.of(context).push(
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
          comprehensionCorrect: itemStats.comprehensionCorrect(),
          namingAttempts: itemStats.namingAttempts(),
          namingCorrect: itemStats.namingCorrect(),
        ),
      ),
    );
  }

  void _finishSession() {
    setState(() {
      sessionEnded = true;
    });
    if (loggerReady) {
      unawaited(logger.endSession());
    }
  }

  bool _isTranscriptCorrect(String transcript, String target) {
    final t = normalizeText(transcript);
    final g = normalizeText(target);
    if (t.isEmpty || g.isEmpty) return false;
    if (t == g) return true;
    if (t.contains(g) || g.contains(t)) return true;
    final dist = levenshtein(t, g);
    final maxLen = max(t.length, g.length);
    final ratio = maxLen == 0 ? 1.0 : 1.0 - dist / maxLen;
    // toleranter: 3 Abweichungen oder 60% Übereinstimmung reichen
    return dist <= 3 || ratio >= 0.6;
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
