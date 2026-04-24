// ------------------------------------------------------------
// Ziel (Laien): Alle Mic-/Naming-Flags bündeln, damit UI/Controller dieselbe Quelle teilen.
// Verbindung: VoiceController steuert diese Flags; robulingo_app.dart liest/schreibt sie für UI-Status.
// Tücken: Mic-Priming und Blockierungen (20 Trials) werden hier verwaltet; kein Persist über Sessions.
// ------------------------------------------------------------
import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'naming_controller.dart';

/// Holds all mic/naming related flags so they can be managed outside the main
/// widget.
class VoiceState {
  bool micReady = false;
  bool micPrimed = false;
  bool micPromptActive = false;
  bool micDenied = false;
  bool micPermanentlyDenied = false;
  bool speechPermanentlyDenied = false;
  bool namingInProgress = false;
  bool namingHold = false;
  String namingStatus = '';
  String liveTranscript = '';
  bool? namingOutcome;
  bool namingCorrectDetected = false;
  bool namingDisabled = false;
  int namingBlockRemaining = 0;
  bool namingNoMicMode = false;
  bool micOn = false;
  int micStage = -1;
  bool namingPaused = false;
  bool micCheckRan = false;
  String micPlatform = '';
  PermissionStatus lastMicStatus = PermissionStatus.denied;
  PermissionStatus lastSpeechStatus = PermissionStatus.denied;
  bool lastMicGranted = false;
  bool lastSpeechGranted = false;
  bool lastInitOk = false;
  bool lastSpeechAvailable = false;
  bool lastSpeechHasPermission = false;
  bool listenCheckRan = false;
  bool lastListenGotSoundLevel = false;
  bool lastListenGotResultEvent = false;
  double lastListenMaxSoundLevel = -120;
  String lastListenLocale = '-';

  void rememberMicInitResult(MicInitResult res) {
    micCheckRan = true;
    micPlatform = res.platform;
    lastMicStatus = res.micStatus;
    lastSpeechStatus = res.speechStatus;
    lastMicGranted = res.micGranted;
    lastSpeechGranted = res.speechGranted;
    lastInitOk = res.initOk;
    lastSpeechAvailable = res.isAvailable;
    lastSpeechHasPermission = res.hasPermission;
  }

  void rememberListenDiagnostics(NamingController controller) {
    listenCheckRan = true;
    lastListenGotSoundLevel = controller.lastListenGotSoundLevel;
    lastListenGotResultEvent = controller.lastListenGotResultEvent;
    lastListenMaxSoundLevel = controller.lastListenMaxSoundLevel;
    lastListenLocale = controller.lastListenLocale;
  }
}

/// Encapsulates the speech/naming flow and mic readiness logic.
class VoiceController {
  VoiceController({
    required this.speech,
    required this.namingController,
    required this.micController,
    required this.state,
    required this.onStateChanged,
  });

  final stt.SpeechToText speech;
  final NamingController namingController;
  final AnimationController micController;
  final VoiceState state;
  final VoidCallback onStateChanged;
  bool _micControllerFailed = false;
  Completer<void>? _resumeCompleter;

  void _safeMicStop() {
    if (_micControllerFailed) return;
    try {
      micController.stop();
    } catch (_) {
      _micControllerFailed = true;
    }
  }

  void _safeMicPulseLoop() {
    if (_micControllerFailed) return;
    try {
      micController.duration = const Duration(milliseconds: 900);
      micController.repeat();
    } catch (_) {
      _micControllerFailed = true;
    }
  }

  Future<void> initSpeech() async {
    // No-op by default: mic preflight is triggered by the naming-session flow.
  }

  Future<bool> ensureMicReady({
    VoidCallback? onPermanentDisable,
    bool forceRecheck = false,
  }) async {
    if (state.micReady && !forceRecheck) return true;
    final res = await namingController.ensureMicReadyDetailed();
    state.rememberMicInitResult(res);
    state.micPermanentlyDenied = res.isMicPermanentlyDenied;
    state.speechPermanentlyDenied = res.isSpeechPermanentlyDenied;
    if (!res.ready) {
      state.micReady = false;
      if (res.isMicPermanentlyDenied || res.isSpeechPermanentlyDenied) {
        onPermanentDisable?.call();
      }
      state.namingHold = true;
      state.micDenied = true;
      onStateChanged();
      return false;
    }
    state.micReady = res.ready;
    state.micDenied = false;
    state.micPermanentlyDenied = false;
    state.speechPermanentlyDenied = false;
    onStateChanged();
    return res.ready;
  }

  void cancelActive() {
    namingController.cancel();
    try {
      speech.stop();
    } catch (_) {}
    state.namingPaused = false;
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    state.namingInProgress = false;
    state.micOn = false;
    state.micStage = -1;
    _safeMicStop();
    onStateChanged();
  }

  bool canToggleRecordingPause() {
    if (!state.namingInProgress) return false;
    return state.micStage == 0 || state.micStage == 2;
  }

  void pauseRecording() {
    if (!canToggleRecordingPause() || state.namingPaused) return;
    state.namingPaused = true;
    state.micOn = false;
    onStateChanged();
  }

  void resumeRecording() {
    if (!state.namingInProgress || !state.namingPaused) return;
    state.namingPaused = false;
    if (state.micStage == 0 || state.micStage == 2) {
      state.micOn = true;
    }
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    onStateChanged();
  }

  void toggleRecordingPause() {
    if (state.namingPaused) {
      resumeRecording();
    } else {
      pauseRecording();
    }
  }

  Future<void> _waitUntilResumed() {
    if (!state.namingPaused) return Future<void>.value();
    _resumeCompleter ??= Completer<void>();
    return _resumeCompleter!.future;
  }

  Future<NamingFlowOutcome?> startNamingFlow({
    required int token,
    required String targetText,
    required bool Function(String transcript, String targetText) scorer,
    required Future<void> Function() playHint,
    required void Function(String transcript) onTranscript,
    required bool Function() isCurrent,
    VoidCallback? onPermanentDisable,
    bool userInitiated = false,
    Duration firstWindow = const Duration(seconds: 4),
    Duration repeatWindow = const Duration(seconds: 3),
    bool allowRepeat = false,
    String? localeId,
    VoidCallback? onCorrectDetected,
  }) async {
    // Do not request permissions here (run should have been initiated explicitly).
    if (!state.micReady) {
      state.namingHold = true;
      state.micDenied = true;
      onStateChanged();
      return null;
    }
    state.micDenied = false;
    state.micPermanentlyDenied = false;
    state.speechPermanentlyDenied = false;
    if (!state.micPrimed) {
      if (userInitiated) {
        state.micPrimed = true;
        state.micPromptActive = false;
      } else {
        state.micPromptActive = true;
        state.namingStatus = '';
        onStateChanged();
        return null;
      }
    }

    state.namingInProgress = true;
    state.micPromptActive = false;
    state.namingHold = false;
    state.namingOutcome = null;
    state.namingCorrectDetected = false;
    state.namingStatus = '';
    state.micStage = 0;
    state.micOn = true;
    state.namingPaused = false;
    state.liveTranscript = '';
    _resumeCompleter = null;
    onStateChanged();
    _safeMicPulseLoop();

    final result = await namingController.runFlow(
      trialToken: token,
      targetText: targetText,
      isCurrent: isCurrent,
      scorer: scorer,
      playHint: () async {
        if (!isCurrent()) return;
        state.namingStatus = '';
        state.micStage = 1;
        state.micOn = false;
        onStateChanged();
        await playHint();
      },
      onPhase: (phase) {
        if (!isCurrent()) return;
        switch (phase) {
          case NamingPhase.idle:
            break;
          case NamingPhase.listeningFirst:
            state.namingStatus = '';
            state.micStage = 0;
            state.micOn = true;
            state.namingOutcome = null;
            state.namingCorrectDetected = false;
            break;
          case NamingPhase.listeningRepeat:
            state.namingStatus = '';
            state.micStage = 2;
            state.micOn = true;
            break;
          case NamingPhase.finished:
          case NamingPhase.cancelled:
          case NamingPhase.playingHint:
            break;
        }
        onStateChanged();
      },
      onTranscript: (text) {
        if (!isCurrent()) return;
        state.liveTranscript = text;
        onStateChanged();
        onTranscript(text);
      },
      firstWindow: firstWindow,
      repeatWindow: repeatWindow,
      allowRepeat: allowRepeat,
      localeId: localeId,
      onCorrectDetected: () {
        if (!isCurrent()) return;
        state.namingCorrectDetected = true;
        onStateChanged();
        onCorrectDetected?.call();
      },
      isPaused: () => state.namingPaused,
      waitUntilResumed: _waitUntilResumed,
    );
    state.rememberListenDiagnostics(namingController);

    state.namingInProgress = false;
    state.micOn = false;
    state.micStage = -1;
    state.namingPaused = false;
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    _safeMicStop();
    if (result == null) {
      state.namingOutcome = null;
      state.namingCorrectDetected = false;
      state.namingStatus = '';
      onStateChanged();
      return null;
    }
    state.liveTranscript = result.transcript;
    onStateChanged();
    return result;
  }
}
