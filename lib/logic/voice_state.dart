// ------------------------------------------------------------
// Ziel (Laien): Alle Mic-/Naming-Flags bündeln, damit UI/Controller dieselbe Quelle teilen.
// Verbindung: VoiceController steuert diese Flags; robulingo_app.dart liest/schreibt sie für UI-Status.
// Tücken: Mic-Gate/Priming/Blockierungen (20 Trials) werden hier verwaltet; kein Persist über Sessions.
// ------------------------------------------------------------
import 'dart:async';

import 'package:flutter/animation.dart';
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
  bool namingDisabled = false;
  int namingBlockRemaining = 0;
  int micGateToken = -1;
  bool micGateGranted = false;
  bool micOn = false;
  int micStage = -1;
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

  void _safeMicStop() {
    if (_micControllerFailed) return;
    try {
      micController.stop();
    } catch (_) {
      _micControllerFailed = true;
    }
  }

  void _safeMicForward(Duration total) {
    if (_micControllerFailed) return;
    try {
      micController.duration = total;
      micController.forward(from: 0);
    } catch (_) {
      _micControllerFailed = true;
    }
  }

  bool _permissionsGranted(dynamic res) {
    try {
      return res.micGranted == true && res.speechGranted != false;
    } catch (_) {
      return false;
    }
  }

  Future<void> initSpeech() async {
    // No-op by default: do not prompt for permissions implicitly.
    // Mic permission should be requested only via explicit user action.
  }

  Future<bool> ensureMicReady({VoidCallback? onPermanentDisable}) async {
    if (state.micReady) return true;
    final res = await namingController.ensureMicReadyDetailed();
    state.micPermanentlyDenied = res.isMicPermanentlyDenied;
    state.speechPermanentlyDenied = res.isSpeechPermanentlyDenied;
    if (!res.ready) {
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
    state.namingInProgress = false;
    state.micOn = false;
    state.micStage = -1;
    _safeMicStop();
    onStateChanged();
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
    Duration firstWindow = const Duration(seconds: 5),
    Duration repeatWindow = const Duration(seconds: 5),
    bool allowRepeat = false,
    String? localeId,
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
    state.namingStatus = '';
    state.micStage = 0;
    state.micOn = true;
    state.liveTranscript = '';
    onStateChanged();
    final totalSeconds =
        firstWindow.inSeconds + (allowRepeat ? repeatWindow.inSeconds : 0) + 2;
    _safeMicForward(Duration(seconds: totalSeconds));

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
    );

    state.namingInProgress = false;
    state.micOn = false;
    state.micStage = -1;
    _safeMicStop();
    if (result == null) {
      state.namingOutcome = null;
      state.namingStatus = '';
      onStateChanged();
      return null;
    }
    state.liveTranscript = result.transcript;
    onStateChanged();
    return result;
  }
}
