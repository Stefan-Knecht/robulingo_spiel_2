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
  });

  final bool correct;
  final int moves;
  final String transcript;
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

  String get liveTranscript => _liveTranscript;

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
          onError: (e) {
            if (onError != null) onError!(e.errorMsg);
          },
        );
        final hasSpeechPerm = await speech.hasPermission;
        _log(
            '[naming][init] ok=$ok available=${speech.isAvailable} hasSpeechPerm=$hasSpeechPerm micGranted=$micGrantedEffective');
        return MicInitResult(
          // Treat mic grant + init success as ready; tolerate simulator's perm misreporting.
          ready: ok && micGrantedEffective,
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

  Future<NamingFlowOutcome?> runFlow({
    required int trialToken,
    required String targetText,
    required bool Function() isCurrent,
    required bool Function(String transcript, String targetText) scorer,
    required Future<void> Function() playHint,
    required void Function(NamingPhase phase) onPhase,
    required void Function(String transcript) onTranscript,
    Duration firstWindow = const Duration(seconds: 5),
    Duration repeatWindow = const Duration(seconds: 5),
    bool allowRepeat = true,
    String? localeId,
  }) async {
    _flowToken++;
    _sessionId++;
    final int localFlow = _flowToken;
    final int sessionId = _sessionId;
    _liveTranscript = '';
    print('_liveTranscript: $_liveTranscript');
    print('localeID: $localeId');

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
    );
    if (!_isValid(localFlow, sessionId, isCurrent)) {
      return null;
    }
    if (firstCorrect || !allowRepeat) {
      onPhase(NamingPhase.finished);
      return NamingFlowOutcome(
        correct: firstCorrect,
        moves: firstCorrect ? 1 : 0,
        transcript: _liveTranscript,
      );
    }

    onPhase(NamingPhase.playingHint);
    await playHint();
    if (!_isValid(localFlow, sessionId, isCurrent)) {
      return null;
    }

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
    );
    if (!_isValid(localFlow, sessionId, isCurrent)) {
      return null;
    }

    onPhase(NamingPhase.finished);
    return NamingFlowOutcome(
      correct: repeatCorrect,
      moves: repeatCorrect ? 1 : 0,
      transcript: _liveTranscript,
    );
  }

  Future<bool> _listenAndScore({
    required Duration duration,
    required String targetText,
    required int flowToken,
    required int sessionId,
    required bool Function() isCurrent,
    required bool Function(String transcript, String targetText) scorer,
    required void Function(String transcript) onTranscript,
    String? localeId,
  }) async {
    final transcript = await _listenForDuration(
      duration,
      flowToken,
      sessionId,
      isCurrent,
      onTranscript,
      localeId,
    );
    print('transcript: $transcript');
    if (!_isValid(flowToken, sessionId, isCurrent)) {
      return false;
    }
    return scorer(transcript, targetText);
  }

  Future<String> _listenForDuration(
    Duration duration,
    int flowToken,
    int sessionId,
    bool Function() isCurrent,
    void Function(String transcript) onTranscript,
    String? localeId,
  ) async {
    _liveTranscript = '';
    try {
      await speech.stop();
    } catch (_) {}
    final completer = Completer<void>();
    bool gotResultEvent = false;
    bool gotSoundLevel = false;
    double maxSoundLevel = -120;
    _log(
        '[naming][listen] locale=${localeId ?? "-"} dur=${duration.inSeconds}s flow=$flowToken session=$sessionId');
    try {
      const listenMode =
          kIsWeb ? stt.ListenMode.confirmation : stt.ListenMode.dictation;
      final Duration? listenFor = kIsWeb ? null : duration;
      final Duration? pauseFor =
          kIsWeb ? null : const Duration(milliseconds: 800);
      await speech.listen(
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenOptions: stt.SpeechListenOptions(
          listenMode: listenMode,
          partialResults: true,
          cancelOnError: !kIsWeb,
        ),
        localeId: localeId,
        onSoundLevelChange: (level) {
          gotSoundLevel = true;
          if (level > maxSoundLevel) maxSoundLevel = level;
        },
        onResult: (res) {
          if (!_isValid(flowToken, sessionId, isCurrent)) return;
          gotResultEvent = true;
          _liveTranscript = res.recognizedWords;
          _log(
              '[naming][listen-result] final=${res.finalResult} words="${res.recognizedWords}" conf=${res.confidence}');
          onTranscript(_liveTranscript);
          if (res.finalResult && !completer.isCompleted) {
            completer.complete();
          }
        },
      );
    } catch (_) {
      onError?.call('listen-ex');
      return '';
    }
    final timeout = Future.delayed(duration + const Duration(seconds: 1));
    await Future.any([completer.future, timeout]);
    await _stopListening();
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
