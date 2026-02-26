import 'package:audioplayers/audioplayers.dart';

class PlaybackResult {
  final bool ok;
  final bool timedOut;
  final bool completed;
  final Object? error;

  const PlaybackResult._({
    required this.ok,
    required this.timedOut,
    required this.completed,
    this.error,
  });

  const PlaybackResult.success({bool completed = false})
      : this._(ok: true, timedOut: false, completed: completed);

  const PlaybackResult.failure({bool timedOut = false, Object? error})
      : this._(ok: false, timedOut: timedOut, completed: false, error: error);
}

abstract class PlaybackEngine {
  Future<void> init();

  Future<PlaybackResult> playSpeech(
    Uri uri, {
    Duration startTimeout = const Duration(seconds: 8),
  });

  Future<PlaybackResult> playHint(
    Uri uri, {
    Duration startTimeout = const Duration(seconds: 8),
    Duration completionTimeout = const Duration(seconds: 10),
  });

  Future<void> stopSpeech();

  Future<void> stopHint();

  Future<void> dispose();
}

typedef PlaybackLogFn = void Function(String message);
typedef PlaybackFactoryFn = PlaybackEngine Function({
  required AudioContext speechContext,
  required AudioContext hintContext,
  PlaybackLogFn? onLog,
});
