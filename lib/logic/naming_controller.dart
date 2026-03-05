// ------------------------------------------------------------
// Ziel (Laien): Mikro-/ASR-Flow kapseln (Freigabe, zwei Hörfenster, Scoring) getrennt von der UI.
// Verbindung: Wird von VoiceController/robulingo_app.dart genutzt; wertet Transkripte gegen text_utils aus.
// Tücken: Token- und Session-IDs entwerten alte Async-Calls; Permission-Handling unterscheidet Simulator/Gerät.
// ------------------------------------------------------------
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:robulingo_flutter/utils/platform_info.dart';

enum NamingPhase {
  idle,
  listeningFirst,
  playingHint,
  listeningRepeat,
  finished,
  cancelled,
}

class NamingFlowOutcome {
  NamingFlowOutcome({
    required this.correct,
    required this.moves,
    required this.transcript,
    required this.attempts,
    required this.correctCount,
    required this.usedHint,
  });

  final bool correct;
  final int moves;
  final String transcript;
  final int attempts;
  final int correctCount;
  final bool usedHint;
}

class MicInitResult {
  MicInitResult({
    required this.ready,
    required this.micGranted,
    required this.speechGranted,
    required this.initOk,
    required this.isAvailable,
    required this.hasPermission,
    required this.platform,
    required this.micStatus,
    required this.speechStatus,
    required this.isMicPermanentlyDenied,
    required this.isSpeechPermanentlyDenied,
  });

  final bool ready;
  final bool micGranted;
  final bool speechGranted;
  final bool initOk;
  final bool isAvailable;
  final bool hasPermission;
  final String platform;
  final PermissionStatus micStatus;
  final PermissionStatus speechStatus;
  final bool isMicPermanentlyDenied;
  final bool isSpeechPermanentlyDenied;
}

class AsrProbeResult {
  AsrProbeResult({
    required this.transcript,
    required this.recognizedWords,
    required this.confidence,
    required this.finalResult,
    required this.gotResultEvent,
    required this.gotSoundLevel,
    required this.maxSoundLevel,
    required this.localeUsed,
  });

  final String transcript;
  final String recognizedWords;
  final double confidence;
  final bool finalResult;
  final bool gotResultEvent;
  final bool gotSoundLevel;
  final double maxSoundLevel;
  final String localeUsed;
}

/// Encapsulates the async mic/naming flow so it can be guarded with tokens and
/// reused without duplicating cancellation logic in the widget.
class NamingController {
  NamingController({
    required this.speech,
    this.onError,
    this.onStatus,
  });

  final stt.SpeechToText speech;
  final void Function(String code)? onError;
  final void Function(String status)? onStatus;

  int _flowToken = 0;
  int _sessionId = 0;
  String _liveTranscript = '';
  String _lastRecognizedWords = '';
  double _lastConfidence = -1;
  bool _lastFinalResult = false;
  bool _lastListenGotResultEvent = false;
  bool _lastListenGotSoundLevel = false;
  double _lastListenMaxSoundLevel = -120;
  String _lastListenLocale = '-';

  String get liveTranscript => _liveTranscript;
  String get lastRecognizedWords => _lastRecognizedWords;
  double get lastConfidence => _lastConfidence;
  bool get lastFinalResult => _lastFinalResult;
  bool get lastListenGotResultEvent => _lastListenGotResultEvent;
  bool get lastListenGotSoundLevel => _lastListenGotSoundLevel;
  double get lastListenMaxSoundLevel => _lastListenMaxSoundLevel;
  String get lastListenLocale => _lastListenLocale;

  /// Increment the flow token to invalidate any pending async work.
  void cancel() {
    _flowToken++;
    try {
      speech.stop();
    } catch (_) {}
  }

  Future<MicInitResult> ensureMicReadyDetailed() async {
    try {
      final micStatus = await Permission.microphone.request();
      final bool micGrantedEffective = micStatus.isGranted;
      PermissionStatus speechStatus = PermissionStatus.granted;
      bool speechGrantedEffective = true;
      if (isIOS || isMacOS) {
        // Try to request speech; do not hard-fail if it misreports (simulator quirks).
        speechStatus = await Permission.speech.status;
        if (!speechStatus.isGranted && !speechStatus.isPermanentlyDenied) {
          speechStatus = await Permission.speech.request();
        }
        speechGrantedEffective = speechStatus.isGranted;
      }
      _log(
          '[naming][perm] platform=$operatingSystem mic=$micStatus speech=$speechStatus effectiveMic=$micGrantedEffective effectiveSpeech=$speechGrantedEffective debug=$kDebugMode');
      if (!micGrantedEffective || !speechGrantedEffective) {
        return MicInitResult(
          ready:
              false, // will be overridden below if init succeeds with effective grants
          micGranted: micGrantedEffective,
          speechGranted: speechGrantedEffective,
          initOk: false,
          isAvailable: false,
          hasPermission: false,
          platform: operatingSystem,
          micStatus: micStatus,
          speechStatus: speechStatus,
          isMicPermanentlyDenied: micStatus.isPermanentlyDenied,
          isSpeechPermanentlyDenied: speechStatus.isPermanentlyDenied,
        );
      }
      try {
        final ok = await speech.initialize(
          onStatus: (s) {
            if (onStatus != null) onStatus!(s);
          },
          onError: (e) => _handleInitializeError(e),
          finalTimeout: const Duration(seconds: 4),
          options: <stt.SpeechConfigOption>[
            stt.SpeechToText.androidIntentLookup,
            stt.SpeechToText.androidAlwaysUseStop,
            stt.SpeechToText.androidNoBluetooth,
          ],
        );
        final hasSpeechPerm = await speech.hasPermission;
        _log(
            '[naming][init] ok=$ok available=${speech.isAvailable} hasSpeechPerm=$hasSpeechPerm micGranted=$micGrantedEffective');
        return MicInitResult(
          // Treat mic grant + init success as ready; require ASR availability on device.
          ready: ok && micGrantedEffective && speech.isAvailable,
          micGranted: micGrantedEffective,
          speechGranted: hasSpeechPerm || speechGrantedEffective,
          initOk: ok,
          isAvailable: speech.isAvailable,
          hasPermission: hasSpeechPerm,
          platform: operatingSystem,
          micStatus: micStatus,
          speechStatus: speechStatus,
          isMicPermanentlyDenied: micStatus.isPermanentlyDenied,
          isSpeechPermanentlyDenied: speechStatus.isPermanentlyDenied,
        );
      } catch (e) {
        _log('[naming][init-error] $e');
        return MicInitResult(
          ready: false,
          micGranted: micStatus.isGranted,
          speechGranted: speechStatus.isGranted,
          initOk: false,
          isAvailable: false,
          hasPermission: micStatus.isGranted,
          platform: operatingSystem,
          micStatus: micStatus,
          speechStatus: speechStatus,
          isMicPermanentlyDenied: micStatus.isPermanentlyDenied,
          isSpeechPermanentlyDenied: speechStatus.isPermanentlyDenied,
        );
      }
    } catch (e) {
      _log('[naming][perm-error] $e');
      return MicInitResult(
        ready: false,
        micGranted: false,
        speechGranted: false,
        initOk: false,
        isAvailable: false,
        hasPermission: false,
        platform: operatingSystem,
        micStatus: PermissionStatus.denied,
        speechStatus: PermissionStatus.denied,
        isMicPermanentlyDenied: false,
        isSpeechPermanentlyDenied: false,
      );
    }
  }

  Future<bool> ensureMicReady() async {
    final res = await ensureMicReadyDetailed();
    return res.ready;
  }

  Future<AsrProbeResult> runAsrProbe({
    Duration duration = const Duration(seconds: 4),
    required bool Function() isCurrent,
    void Function(String transcript)? onTranscript,
    String? localeId,
  }) async {
    _flowToken++;
    _sessionId++;
    final int localFlow = _flowToken;
    final int sessionId = _sessionId;

    final transcript = await _listenForDuration(
      duration,
      localFlow,
      sessionId,
      isCurrent,
      onTranscript ?? (_) {},
      localeId,
    );
    if (!_isValid(localFlow, sessionId, isCurrent)) {
      return AsrProbeResult(
        transcript: '',
        recognizedWords: '',
        confidence: -1,
        finalResult: false,
        gotResultEvent: false,
        gotSoundLevel: false,
        maxSoundLevel: -120,
        localeUsed: localeId ?? '-',
      );
    }
    return AsrProbeResult(
      transcript: transcript,
      recognizedWords: _lastRecognizedWords,
      confidence: _lastConfidence,
      finalResult: _lastFinalResult,
      gotResultEvent: _lastListenGotResultEvent,
      gotSoundLevel: _lastListenGotSoundLevel,
      maxSoundLevel: _lastListenMaxSoundLevel,
      localeUsed: _lastListenLocale,
    );
  }

  Future<NamingFlowOutcome?> runFlow({
    required int trialToken,
    required String targetText,
    required bool Function() isCurrent,
    required bool Function(String transcript, String targetText) scorer,
    required Future<void> Function() playHint,
    required void Function(NamingPhase phase) onPhase,
    required void Function(String transcript) onTranscript,
    Duration firstWindow = const Duration(seconds: 4),
    Duration repeatWindow = const Duration(seconds: 3),
    bool allowRepeat = true,
    String? localeId,
    bool Function()? isPaused,
    Future<void> Function()? waitUntilResumed,
  }) async {
    _flowToken++;
    _sessionId++;
    final int localFlow = _flowToken;
    final int sessionId = _sessionId;
    _liveTranscript = '';
    print('_liveTranscript: $_liveTranscript');
    print('localeID: $localeId');

    // Run semantics: one outcome per slot/uuid.
    // Optionally allow exactly one hint+repeat listen (listen -> hint -> listen).
    if (!_isValid(localFlow, sessionId, isCurrent)) return null;

    onPhase(NamingPhase.listeningFirst);
    final firstCorrect = await _listenAndScore(
      duration: firstWindow,
      targetText: targetText,
      flowToken: localFlow,
      sessionId: sessionId,
      isCurrent: isCurrent,
      scorer: scorer,
      onTranscript: onTranscript,
      localeId: localeId,
      isPaused: isPaused,
      waitUntilResumed: waitUntilResumed,
    );
    if (!_isValid(localFlow, sessionId, isCurrent)) return null;

    if (firstCorrect || !allowRepeat) {
      if (firstCorrect) {
        onPhase(NamingPhase.playingHint);
        await playHint();
        if (!_isValid(localFlow, sessionId, isCurrent)) return null;
      }
      onPhase(NamingPhase.finished);
      return NamingFlowOutcome(
        correct: firstCorrect,
        moves: firstCorrect ? 1 : 0,
        transcript: _liveTranscript,
        attempts: 1,
        correctCount: firstCorrect ? 1 : 0,
        usedHint: false,
      );
    }

    onPhase(NamingPhase.playingHint);
    await playHint();
    if (!_isValid(localFlow, sessionId, isCurrent)) return null;

    onPhase(NamingPhase.listeningRepeat);
    final repeatCorrect = await _listenAndScore(
      duration: repeatWindow,
      targetText: targetText,
      flowToken: localFlow,
      sessionId: sessionId,
      isCurrent: isCurrent,
      scorer: scorer,
      onTranscript: onTranscript,
      localeId: localeId,
      isPaused: isPaused,
      waitUntilResumed: waitUntilResumed,
    );
    if (!_isValid(localFlow, sessionId, isCurrent)) return null;

    final correct = repeatCorrect;
    onPhase(NamingPhase.finished);
    return NamingFlowOutcome(
      correct: correct,
      moves: correct ? 1 : 0,
      transcript: _liveTranscript,
      attempts: 1,
      correctCount: correct ? 1 : 0,
      usedHint: true,
    );
  }

  void _handleInitializeError(dynamic error) {
    if (onError == null) return;
    String? msg;
    try {
      msg = (error as dynamic).errorMsg as String?;
    } catch (_) {
      msg = null;
    }
    final message = (msg != null && msg.trim().isNotEmpty)
        ? msg
        : (error?.toString() ?? 'speech-init-error');
    onError!(message);
  }

  Future<bool> _listenAndScore({
    required Duration duration,
    required String targetText,
    required int flowToken,
    required int sessionId,
    required bool Function() isCurrent,
    required bool Function(String transcript, String targetText) scorer,
    required void Function(String transcript) onTranscript,
    void Function(String transcript, bool correct)? onScored,
    String? localeId,
    bool Function()? isPaused,
    Future<void> Function()? waitUntilResumed,
  }) async {
    final transcript = await _listenForDuration(
      duration,
      flowToken,
      sessionId,
      isCurrent,
      onTranscript,
      localeId,
      isPaused: isPaused,
      waitUntilResumed: waitUntilResumed,
    );
    print('transcript: $transcript');
    if (!_isValid(flowToken, sessionId, isCurrent)) {
      return false;
    }
    final correct = scorer(transcript, targetText);
    onScored?.call(transcript, correct);
    return correct;
  }

  Future<String> _listenForDuration(
    Duration duration,
    int flowToken,
    int sessionId,
    bool Function() isCurrent,
    void Function(String transcript) onTranscript,
    String? localeId,
    {bool Function()? isPaused, Future<void> Function()? waitUntilResumed}
  ) async {
    _liveTranscript = '';
    _lastRecognizedWords = '';
    _lastConfidence = -1;
    _lastFinalResult = false;
    _lastListenGotResultEvent = false;
    _lastListenGotSoundLevel = false;
    _lastListenMaxSoundLevel = -120;
    _lastListenLocale = localeId ?? '-';
    try {
      await speech.stop();
    } catch (_) {}
    if (operatingSystem == 'android') {
      // Give Android's recognizer a moment to spin up (helps first window).
      await Future.delayed(const Duration(milliseconds: 300));
    }
    final completer = Completer<void>();
    bool gotResultEvent = false;
    bool gotSoundLevel = false;
    double maxSoundLevel = -120;
    final bool isAndroid = operatingSystem == 'android';
    final Duration phaseBudget = isAndroid
        ? duration + const Duration(seconds: 4)
        : duration + const Duration(seconds: 1);
    final budgetWatch = Stopwatch()..start();
    _log(
        '[naming][listen] locale=${localeId ?? "-"} dur=${duration.inSeconds}s flow=$flowToken session=$sessionId');
    String? baseLocaleCandidate(String? rawLocale) {
      final raw = rawLocale?.trim() ?? '';
      if (raw.isEmpty) return null;
      final parts = raw.split(RegExp(r'[-_]'));
      if (parts.isEmpty) return null;
      final base = parts.first.trim().toLowerCase();
      if (base.isEmpty) return null;
      if (base == raw.toLowerCase()) return null;
      return base;
    }

    Duration remainingBudget() {
      final left = phaseBudget - budgetWatch.elapsed;
      return left.isNegative ? Duration.zero : left;
    }

    Future<void> startListen(
      String? useLocale, {
      required stt.ListenMode mode,
      required bool onDevice,
      required bool partialResults,
    }) async {
      _lastListenLocale = useLocale ?? '-';
      final Duration? listenFor = kIsWeb
          ? null
          : (isAndroid ? duration + const Duration(seconds: 3) : duration);
      final Duration? pauseFor = kIsWeb
          ? null
          : (isAndroid
              ? const Duration(milliseconds: 2400)
              : const Duration(milliseconds: 800));
      await speech.listen(
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenOptions: stt.SpeechListenOptions(
          listenMode: mode,
          onDevice: onDevice,
          partialResults: partialResults,
          cancelOnError: false,
        ),
        localeId: useLocale,
        onSoundLevelChange: (level) {
          gotSoundLevel = true;
          if (level > maxSoundLevel) maxSoundLevel = level;
        },
        onResult: (res) {
          if (!_isValid(flowToken, sessionId, isCurrent)) return;
          gotResultEvent = true;
          _liveTranscript = res.recognizedWords;
          _lastRecognizedWords = res.recognizedWords;
          _lastConfidence = res.confidence;
          _lastFinalResult = res.finalResult;
          _log(
              '[naming][listen-result] final=${res.finalResult} words="${res.recognizedWords}" conf=${res.confidence}');
          onTranscript(_liveTranscript);
          if (res.finalResult && !completer.isCompleted) {
            completer.complete();
          }
        },
      );
    }

    Future<void> waitForResult(
      Duration timeout, {
      required String? activeLocale,
      required stt.ListenMode mode,
      required bool onDevice,
      required bool partialResults,
    }) async {
      final left = remainingBudget();
      if (left <= Duration.zero) return;
      final effectiveTimeout = timeout <= left ? timeout : left;
      var remaining = effectiveTimeout;
      var chunkStartedAt = DateTime.now();

      Future<void> restartListening() async {
        await startListen(
          activeLocale,
          mode: mode,
          onDevice: onDevice,
          partialResults: partialResults,
        );
      }

      while (remaining > Duration.zero &&
          !completer.isCompleted &&
          _isValid(flowToken, sessionId, isCurrent)) {
        final paused = isPaused?.call() ?? false;
        if (paused) {
          final elapsed = DateTime.now().difference(chunkStartedAt);
          remaining -= elapsed;
          if (remaining <= Duration.zero) break;
          await _stopListening();
          while ((isPaused?.call() ?? false) &&
              _isValid(flowToken, sessionId, isCurrent)) {
            if (waitUntilResumed != null) {
              await waitUntilResumed();
            } else {
              await Future<void>.delayed(const Duration(milliseconds: 70));
            }
          }
          if (!_isValid(flowToken, sessionId, isCurrent)) break;
          try {
            await restartListening();
          } catch (e) {
            _log(
                '[naming][listen-restart-error] locale="$activeLocale" mode=$mode onDevice=$onDevice err=$e');
            break;
          }
          chunkStartedAt = DateTime.now();
          continue;
        }

        final slice = remaining <= const Duration(milliseconds: 120)
            ? remaining
            : const Duration(milliseconds: 120);
        await Future.any([completer.future, Future.delayed(slice)]);
        if (completer.isCompleted) break;
        if (!_isValid(flowToken, sessionId, isCurrent)) break;
        final elapsed = DateTime.now().difference(chunkStartedAt);
        remaining -= elapsed;
        chunkStartedAt = DateTime.now();
      }

      await _stopListening();
    }

    final stt.ListenMode primaryMode = (kIsWeb || isAndroid)
        ? stt.ListenMode.confirmation
        : stt.ListenMode.dictation;
    final stt.ListenMode alternateMode = primaryMode == stt.ListenMode.dictation
        ? stt.ListenMode.confirmation
        : stt.ListenMode.dictation;

    String normalizeLocale(String raw) =>
        raw.trim().toLowerCase().replaceAll('_', '-');

    List<String> preferredLocaleVariants(String base) {
      switch (base) {
        case 'de':
          return const ['de-DE', 'de-AT', 'de-CH', 'de'];
        case 'es':
          return const ['es-ES', 'es-MX', 'es-US', 'es-419', 'es'];
        case 'fr':
          return const ['fr-FR', 'fr-CA', 'fr-CH', 'fr'];
        case 'it':
          return const ['it-IT', 'it-CH', 'it'];
        case 'en':
          return const ['en-US', 'en-GB', 'en'];
        case 'pt':
          return const ['pt-PT', 'pt-BR', 'pt'];
        case 'zh':
          return const ['zh-CN', 'zh-TW', 'zh-HK', 'zh'];
        case 'ar':
          return const ['ar-SA', 'ar-EG', 'ar'];
        case 'ru':
          return const ['ru-RU', 'ru'];
        case 'hi':
          return const ['hi-IN', 'hi'];
        case 'el':
          return const ['el-GR', 'el'];
        case 'tr':
          return const ['tr-TR', 'tr'];
        case 'ja':
          return const ['ja-JP', 'ja'];
        default:
          return <String>[base];
      }
    }

    Future<List<String?>> buildLocaleAttempts() async {
      final out = <String?>[];
      void add(String? value) {
        final v = value?.trim();
        if (v == null || v.isEmpty) return;
        final n = normalizeLocale(v);
        final exists = out.any((e) => normalizeLocale(e ?? '') == n);
        if (!exists) out.add(v);
      }

      final base = baseLocaleCandidate(localeId) ??
          (() {
            final raw = localeId?.trim() ?? '';
            if (raw.isEmpty) return null;
            final parts = raw.split(RegExp(r'[-_]'));
            if (parts.isEmpty) return null;
            final b = parts.first.trim().toLowerCase();
            return b.isEmpty ? null : b;
          })();
      if (base == null) {
        add(localeId);
        return out;
      }
      try {
        final locales = await speech.locales();
        // Prefer locales that the recognizer explicitly reports as supported.
        final supported = <String>[];
        for (final locale in locales) {
          final id = locale.localeId.trim();
          if (id.isEmpty) continue;
          final norm = normalizeLocale(id);
          if (norm == base || norm.startsWith('$base-')) {
            supported.add(id);
          }
        }
        for (final id in supported) {
          add(id);
        }
      } catch (_) {
        // If locales cannot be queried, fall back to known variants.
      }
      // Then try strong L2 variants and the requested locale.
      for (final candidate in preferredLocaleVariants(base)) {
        add(candidate);
      }
      add(localeId);
      add(base);
      return out;
    }

    final localeAttempts = await buildLocaleAttempts();
    if (localeAttempts.isEmpty &&
        localeId != null &&
        localeId.trim().isNotEmpty) {
      localeAttempts.add(localeId);
    }

    for (final attemptLocale in localeAttempts) {
      if (remainingBudget() <= Duration.zero) break;
      try {
        await startListen(
          attemptLocale,
          mode: primaryMode,
          onDevice: false,
          partialResults: true,
        );
      } catch (e) {
        _log(
            '[naming][listen-error] locale="$attemptLocale" mode=$primaryMode onDevice=false err=$e');
        continue;
      }
      await waitForResult(
        isAndroid
            ? duration + const Duration(milliseconds: 2600)
            : duration + const Duration(seconds: 1),
        activeLocale: attemptLocale,
        mode: primaryMode,
        onDevice: false,
        partialResults: true,
      );
      if (gotResultEvent || !_isValid(flowToken, sessionId, isCurrent)) break;
      if (!gotSoundLevel) break;

      if (remainingBudget() <= const Duration(milliseconds: 1100)) continue;
      try {
        await startListen(
          attemptLocale,
          mode: alternateMode,
          onDevice: false,
          partialResults: true,
        );
        await waitForResult(
          isAndroid
              ? const Duration(milliseconds: 1800)
              : const Duration(milliseconds: 900),
          activeLocale: attemptLocale,
          mode: alternateMode,
          onDevice: false,
          partialResults: true,
        );
      } catch (e) {
        _log(
            '[naming][listen-error] alt locale="$attemptLocale" mode=$alternateMode onDevice=false err=$e');
      }
      if (gotResultEvent || !_isValid(flowToken, sessionId, isCurrent)) break;

      if (isAndroid &&
          gotSoundLevel &&
          !gotResultEvent &&
          remainingBudget() > const Duration(milliseconds: 1200)) {
        try {
          await startListen(
            attemptLocale,
            mode: stt.ListenMode.confirmation,
            onDevice: true,
            partialResults: false,
          );
          await waitForResult(
            const Duration(milliseconds: 1200),
            activeLocale: attemptLocale,
            mode: stt.ListenMode.confirmation,
            onDevice: true,
            partialResults: false,
          );
        } catch (e) {
          _log(
              '[naming][listen-error] onDevice locale="$attemptLocale" mode=confirmation err=$e');
        }
        if (gotResultEvent || !_isValid(flowToken, sessionId, isCurrent)) break;
      }
    }
    if (!_isValid(flowToken, sessionId, isCurrent)) {
      return '';
    }
    if (!gotResultEvent) {
      _log(
          '[naming][listen-empty] no result events (soundLevel=$gotSoundLevel max=$maxSoundLevel)');
    }
    if (_liveTranscript.isEmpty) {
      _log('[naming][listen-empty-transcript]');
    }
    _lastListenGotResultEvent = gotResultEvent;
    _lastListenGotSoundLevel = gotSoundLevel;
    _lastListenMaxSoundLevel = maxSoundLevel;
    return _liveTranscript;
  }

  Future<void> _stopListening() async {
    try {
      await speech.stop();
    } catch (_) {}
  }

  bool _isValid(int flowToken, int sessionId, bool Function() isCurrent) {
    return flowToken == _flowToken && sessionId == _sessionId && isCurrent();
  }

  void _log(String msg) {
    // Use stdout to avoid depending on Flutter's debugPrint here.
    // ignore: avoid_print
    print(msg);
  }
}

@visibleForTesting
NamingFlowOutcome simulateNamingRunOutcome({
  required bool firstCorrect,
  required bool repeatCorrect,
  bool allowRepeat = true,
}) {
  if (firstCorrect || !allowRepeat) {
    return NamingFlowOutcome(
      correct: firstCorrect,
      moves: firstCorrect ? 1 : 0,
      transcript: '',
      attempts: 1,
      correctCount: firstCorrect ? 1 : 0,
      usedHint: false,
    );
  }
  return NamingFlowOutcome(
    correct: repeatCorrect,
    moves: repeatCorrect ? 1 : 0,
    transcript: '',
    attempts: 1,
    correctCount: repeatCorrect ? 1 : 0,
    usedHint: true,
  );
}
