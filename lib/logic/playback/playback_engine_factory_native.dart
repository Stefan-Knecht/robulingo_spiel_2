import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'playback_engine.dart';

PlaybackEngine createPlaybackEngine({
  required AudioContext speechContext,
  required AudioContext hintContext,
  PlaybackLogFn? onLog,
}) {
  return _NativePlaybackEngine(
    speechContext: speechContext,
    hintContext: hintContext,
    onLog: onLog,
  );
}

class _NativePlaybackEngine implements PlaybackEngine {
  _NativePlaybackEngine({
    required this.speechContext,
    required this.hintContext,
    this.onLog,
  });

  final AudioContext speechContext;
  final AudioContext hintContext;
  final PlaybackLogFn? onLog;

  final AudioPlayer _speechPlayer = AudioPlayer();
  final AudioPlayer _hintPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _speechStateSub;
  StreamSubscription? _speechErrSub;
  StreamSubscription? _hintErrSub;
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _speechPlayer.setReleaseMode(ReleaseMode.stop);
    _hintPlayer.setReleaseMode(ReleaseMode.stop);
    unawaited(_speechPlayer.setAudioContext(speechContext));
    unawaited(_hintPlayer.setAudioContext(hintContext));

    _speechStateSub = _speechPlayer.onPlayerStateChanged.listen((state) {
      onLog?.call(
          '[audio] state=$state playing=${state == PlayerState.playing}');
    });
    _speechErrSub = _speechPlayer.eventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        onLog?.call('[audio][error-state] $e');
      },
    );
    _hintErrSub = _hintPlayer.eventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        onLog?.call('[audio][hint-error] $e');
      },
    );
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await init();
  }

  @override
  Future<PlaybackResult> playSpeech(
    Uri uri, {
    Duration startTimeout = const Duration(seconds: 8),
  }) async {
    await _ensureInit();
    try {
      await _speechPlayer.stop();
      await _speechPlayer.play(_sourceForUri(uri));
      final started = await _waitForStart(_speechPlayer, timeout: startTimeout);
      if (!started) {
        return const PlaybackResult.failure(timedOut: true);
      }
      return const PlaybackResult.success();
    } catch (e) {
      return PlaybackResult.failure(error: e);
    }
  }

  @override
  Future<PlaybackResult> playHint(
    Uri uri, {
    Duration startTimeout = const Duration(seconds: 8),
    Duration completionTimeout = const Duration(seconds: 10),
  }) async {
    await _ensureInit();
    try {
      await _hintPlayer.stop();
      await _hintPlayer.play(_sourceForUri(uri));
      final started = await _waitForStart(_hintPlayer, timeout: startTimeout);
      if (!started) {
        await _hintPlayer.stop();
        return const PlaybackResult.failure(timedOut: true);
      }
      await _hintPlayer.onPlayerComplete.first.timeout(completionTimeout);
      return const PlaybackResult.success(completed: true);
    } on TimeoutException catch (e) {
      await _hintPlayer.stop();
      return PlaybackResult.failure(timedOut: true, error: e);
    } catch (e) {
      await _hintPlayer.stop();
      return PlaybackResult.failure(error: e);
    }
  }

  Future<bool> _waitForStart(
    AudioPlayer player, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final pos = await player.getCurrentPosition();
      if (player.state == PlayerState.playing) return true;
      if (pos != null && pos > Duration.zero) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    final pos = await player.getCurrentPosition();
    return player.state == PlayerState.playing ||
        (pos != null && pos > Duration.zero);
  }

  Source _sourceForUri(Uri uri) {
    if (uri.scheme.toLowerCase() == 'file') {
      return DeviceFileSource(uri.toFilePath());
    }
    return UrlSource(uri.toString());
  }

  @override
  Future<void> stopSpeech() async {
    await _ensureInit();
    await _speechPlayer.stop();
  }

  @override
  Future<void> stopHint() async {
    await _ensureInit();
    await _hintPlayer.stop();
  }

  @override
  Future<void> dispose() async {
    await _speechStateSub?.cancel();
    await _speechErrSub?.cancel();
    await _hintErrSub?.cancel();
    await _speechPlayer.dispose();
    await _hintPlayer.dispose();
  }
}
