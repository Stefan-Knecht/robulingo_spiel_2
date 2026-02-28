// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

typedef VoiceLogFn = void Function(String message);

html.AudioElement? _activeAudio;
StreamSubscription<html.Event>? _activeEndedSub;

Future<bool> playVoiceFeedbackWeb({
  required String url,
  VoiceLogFn? onLog,
}) async {
  await stopVoiceFeedbackWeb();

  final urlValue = url.trim();
  if (urlValue.isEmpty) {
    onLog?.call('[supervisor-resume] voice-web-player missing source');
    return false;
  }

  final audio = html.AudioElement()
    ..preload = 'auto'
    ..src = urlValue;

  final ok = await _startAudio(audio, onLog: onLog);
  if (ok) {
    onLog?.call('[supervisor-resume] voice-web-play-started mode=url');
  } else {
    onLog?.call('[supervisor-resume] voice-web-play-failed mode=url');
  }
  return ok;
}

Future<void> stopVoiceFeedbackWeb() async {
  final audio = _activeAudio;
  _activeAudio = null;

  await _activeEndedSub?.cancel();
  _activeEndedSub = null;

  if (audio != null) {
    try {
      audio.pause();
      audio.currentTime = 0;
      audio.removeAttribute('src');
      audio.load();
    } catch (_) {
      // Ignore best-effort cleanup errors.
    }
  }
}

Future<bool> _startAudio(
  html.AudioElement audio, {
  VoiceLogFn? onLog,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final started = Completer<bool>();
  StreamSubscription<html.Event>? playSub;
  StreamSubscription<html.Event>? playingSub;
  StreamSubscription<html.Event>? timeUpdateSub;
  StreamSubscription<html.Event>? endedSub;
  StreamSubscription<html.Event>? errorSub;

  void finish(bool value) {
    if (started.isCompleted) return;
    started.complete(value);
  }

  playSub = audio.onPlay.listen((_) => finish(true));
  playingSub = audio.onPlaying.listen((_) => finish(true));
  timeUpdateSub = audio.onTimeUpdate.listen((_) {
    if (audio.currentTime > 0) finish(true);
  });
  endedSub = audio.onEnded.listen((_) {
    if (audio.currentTime > 0) finish(true);
  });
  errorSub = audio.onError.listen((_) {
    final mediaError = audio.error;
    final code = mediaError?.code;
    onLog
        ?.call('[supervisor-resume] voice-web-audio-error code=${code ?? '-'}');
    finish(false);
  });

  // Do not await play(); some browsers keep this promise pending.
  audio.play().catchError((Object e) {
    onLog?.call('[supervisor-resume] voice-web-play-throw $e');
    finish(false);
  });

  final ok = await started.future.timeout(timeout, onTimeout: () => false);

  await playSub.cancel();
  await playingSub.cancel();
  await timeUpdateSub.cancel();
  await endedSub.cancel();
  await errorSub.cancel();

  if (!ok) {
    try {
      audio.pause();
      audio.removeAttribute('src');
      audio.load();
    } catch (_) {
      // Ignore best-effort cleanup errors.
    }
    return false;
  }

  _activeAudio = audio;
  _activeEndedSub = audio.onEnded.listen((_) {
    stopVoiceFeedbackWeb();
  });
  return true;
}
