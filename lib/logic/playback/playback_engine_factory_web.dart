import 'dart:async';
import 'dart:html' as html;

import 'package:audioplayers/audioplayers.dart';

import 'playback_engine.dart';

PlaybackEngine createPlaybackEngine({
  required AudioContext speechContext,
  required AudioContext hintContext,
  PlaybackLogFn? onLog,
}) {
  return _WebPlaybackEngine(onLog: onLog);
}

class _WebPlaybackEngine implements PlaybackEngine {
  _WebPlaybackEngine({this.onLog});

  final PlaybackLogFn? onLog;
  bool _initialized = false;
  bool _primedForUserGesture = false;

  static const String _silentWavDataUri =
      'data:audio/wav;base64,UklGRiYAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YQIAAAAAAA==';

  late final html.AudioElement _speech = _newAudioElement();
  late final html.AudioElement _hint = _newAudioElement();

  html.AudioElement _newAudioElement() {
    final el = html.AudioElement();
    el.preload = 'auto';
    el.crossOrigin = 'anonymous';
    el.setAttribute('playsinline', 'true');
    return el;
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await init();
  }

  @override
  Future<void> primeForUserGesture({String source = ''}) async {
    if (!_initialized) {
      _initialized = true;
    }
    if (_primedForUserGesture) return;
    try {
      await _primeElement(_speech);
      await _primeElement(_hint);
      _primedForUserGesture = true;
      if (source.isNotEmpty) {
        onLog?.call('[audio][web-primed] source=$source');
      } else {
        onLog?.call('[audio][web-primed]');
      }
    } catch (e) {
      onLog?.call('[audio][web-prime-failed] source=$source error=$e');
    }
  }

  @override
  Future<PlaybackResult> playSpeech(
    Uri uri, {
    Duration startTimeout = const Duration(seconds: 8),
  }) {
    return _play(
      _speech,
      uri,
      startTimeout: startTimeout,
      awaitCompletion: false,
      completionTimeout: Duration.zero,
    );
  }

  @override
  Future<PlaybackResult> playHint(
    Uri uri, {
    Duration startTimeout = const Duration(seconds: 8),
    Duration completionTimeout = const Duration(seconds: 10),
  }) {
    return _play(
      _hint,
      uri,
      startTimeout: startTimeout,
      awaitCompletion: true,
      completionTimeout: completionTimeout,
    );
  }

  Future<PlaybackResult> _play(
    html.AudioElement element,
    Uri uri, {
    required Duration startTimeout,
    required bool awaitCompletion,
    required Duration completionTimeout,
  }) async {
    await _ensureInit();

    final started = Completer<void>();
    final completed = Completer<void>();
    Object? lastError;
    final subs = <StreamSubscription<dynamic>>[];

    void markStarted() {
      if (!started.isCompleted) started.complete();
    }

    void markCompleted() {
      markStarted();
      if (!completed.isCompleted) completed.complete();
    }

    void markError(Object e) {
      lastError = e;
      if (!started.isCompleted) started.completeError(e);
      if (!completed.isCompleted) completed.completeError(e);
    }

    try {
      await _stopElement(element);
      subs.add(element.onPlaying.listen((_) => markStarted()));
      subs.add(element.onCanPlay.listen((_) {
        if (element.currentTime > 0) markStarted();
      }));
      subs.add(element.onTimeUpdate.listen((_) {
        if (element.currentTime > 0) markStarted();
      }));
      subs.add(element.onEnded.listen((_) => markCompleted()));
      subs.add(element.onError.listen((_) {
        final err = element.error;
        markError(
          StateError(
            'web-audio-error code=${err?.code} message=${err?.message}',
          ),
        );
      }));

      element.src = uri.toString();
      element.load();
      await element.play();

      try {
        await started.future.timeout(startTimeout);
      } on TimeoutException catch (e) {
        await _stopElement(element);
        onLog?.call('[audio][web-start-timeout] url=$uri');
        return PlaybackResult.failure(timedOut: true, error: lastError ?? e);
      }

      if (!awaitCompletion) {
        return const PlaybackResult.success();
      }

      try {
        await completed.future.timeout(completionTimeout);
        return const PlaybackResult.success(completed: true);
      } on TimeoutException catch (e) {
        await _stopElement(element);
        onLog?.call('[audio][web-complete-timeout] url=$uri');
        return PlaybackResult.failure(timedOut: true, error: lastError ?? e);
      }
    } catch (e) {
      await _stopElement(element);
      return PlaybackResult.failure(error: lastError ?? e);
    } finally {
      for (final sub in subs) {
        await sub.cancel();
      }
    }
  }

  Future<void> _stopElement(html.AudioElement element) async {
    try {
      element.pause();
      element.currentTime = 0;
    } catch (_) {
      // Ignore stop issues for robustness on mobile web.
    }
  }

  Future<void> _primeElement(html.AudioElement element) async {
    final previousSrc = element.src;
    final previousCurrentTime = element.currentTime;
    void restore() {
      try {
        element.pause();
      } catch (_) {}
      try {
        element.currentTime = 0;
      } catch (_) {}
      element.src = previousSrc;
      try {
        if (previousCurrentTime > 0) {
          element.currentTime = previousCurrentTime;
        }
      } catch (_) {}
    }

    try {
      try {
        element.pause();
        element.currentTime = 0;
      } catch (_) {}
      element.src = _silentWavDataUri;
      element.load();
      await element.play();
    } finally {
      restore();
    }
  }

  @override
  Future<void> stopSpeech() async {
    await _ensureInit();
    await _stopElement(_speech);
  }

  @override
  Future<void> stopHint() async {
    await _ensureInit();
    await _stopElement(_hint);
  }

  @override
  Future<void> dispose() async {
    await _stopElement(_speech);
    await _stopElement(_hint);
    _speech.src = '';
    _hint.src = '';
  }
}
