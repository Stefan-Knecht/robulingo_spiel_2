// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

typedef VoiceLogFn = void Function(String message);

html.AudioElement? _activeAudio;
StreamSubscription<html.Event>? _activeEndedSub;
String? _activeBlobUrl;

Future<bool> playVoiceFeedbackWeb({
  required String url,
  String? mimeType,
  VoiceLogFn? onLog,
}) async {
  await stopVoiceFeedbackWeb();

  final urlValue = url.trim();
  final normalizedMimeType = _normalizeAudioMimeType(mimeType ?? '');
  if (urlValue.isEmpty) {
    onLog?.call('[supervisor-resume] voice-web-player missing source');
    return false;
  }

  final audio = html.AudioElement()
    ..preload = 'auto'
    ..autoplay = false
    ..src = urlValue;
  audio.setAttribute('playsinline', 'true');
  audio.setAttribute('webkit-playsinline', 'true');
  audio.crossOrigin = 'anonymous';

  var ok = await _startAudio(audio, onLog: onLog);
  if (!ok) {
    onLog?.call('[supervisor-resume] voice-web-blob-fallback-start');
    final blobUrl = await _fetchVoiceBlobUrl(
      url: urlValue,
      mimeType: normalizedMimeType,
      onLog: onLog,
    );
    if (blobUrl != null) {
      final blobAudio = html.AudioElement()
        ..preload = 'auto'
        ..autoplay = false
        ..src = blobUrl;
      blobAudio.setAttribute('playsinline', 'true');
      blobAudio.setAttribute('webkit-playsinline', 'true');
      ok = await _startAudio(blobAudio, onLog: onLog);
      if (ok) {
        _activeBlobUrl = blobUrl;
        onLog?.call('[supervisor-resume] voice-web-blob-fallback-ok');
      } else {
        html.Url.revokeObjectUrl(blobUrl);
        onLog?.call('[supervisor-resume] voice-web-blob-fallback-failed');
      }
    }
  }
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
  final blobUrl = _activeBlobUrl;
  _activeBlobUrl = null;

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
  if (blobUrl != null) {
    try {
      html.Url.revokeObjectUrl(blobUrl);
    } catch (_) {
      // Ignore best-effort cleanup errors.
    }
  }
}

Future<bool> _startAudio(
  html.AudioElement audio, {
  VoiceLogFn? onLog,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final started = Completer<bool>();
  StreamSubscription<html.Event>? playSub;
  StreamSubscription<html.Event>? playingSub;
  StreamSubscription<html.Event>? loadedDataSub;
  StreamSubscription<html.Event>? canPlaySub;
  StreamSubscription<html.Event>? timeUpdateSub;
  StreamSubscription<html.Event>? endedSub;
  StreamSubscription<html.Event>? errorSub;

  void finish(bool value) {
    if (started.isCompleted) return;
    started.complete(value);
  }

  playSub = audio.onPlay.listen((_) => finish(true));
  playingSub = audio.onPlaying.listen((_) => finish(true));
  loadedDataSub = audio.onLoadedData.listen((_) {
    if (!audio.paused) finish(true);
  });
  canPlaySub = audio.onCanPlay.listen((_) {
    if (!audio.paused) finish(true);
  });
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
  await loadedDataSub.cancel();
  await canPlaySub.cancel();
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

String _normalizeAudioMimeType(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return 'audio/mp4';
  switch (value) {
    case 'audio/m4a':
    case 'audio/x-m4a':
    case 'audio/x-mp4':
      return 'audio/mp4';
    case 'audio/mp3':
    case 'audio/x-mp3':
      return 'audio/mpeg';
    case 'audio/x-wav':
      return 'audio/wav';
    default:
      return value.startsWith('audio/') ? value : 'audio/mp4';
  }
}

Future<String?> _fetchVoiceBlobUrl({
  required String url,
  required String mimeType,
  VoiceLogFn? onLog,
}) async {
  try {
    final req = await html.HttpRequest.request(
      url,
      method: 'GET',
      responseType: 'arraybuffer',
    );
    if (req.status != 200) {
      onLog?.call(
          '[supervisor-resume] voice-web-blob-http status=${req.status}');
      return null;
    }
    final response = req.response;
    if (response is! ByteBuffer) {
      onLog?.call('[supervisor-resume] voice-web-blob-response-invalid');
      return null;
    }
    final bytes = Uint8List.view(response);
    if (bytes.isEmpty) {
      onLog?.call('[supervisor-resume] voice-web-blob-empty');
      return null;
    }
    final blob = html.Blob(<Object>[bytes], mimeType);
    return html.Url.createObjectUrlFromBlob(blob);
  } catch (e) {
    onLog?.call('[supervisor-resume] voice-web-blob-fetch-error $e');
    return null;
  }
}
