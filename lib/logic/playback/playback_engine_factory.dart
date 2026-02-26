import 'package:audioplayers/audioplayers.dart';

import 'playback_engine.dart';
import 'playback_engine_factory_stub.dart'
    if (dart.library.io) 'playback_engine_factory_native.dart'
    if (dart.library.html) 'playback_engine_factory_web.dart' as impl;

PlaybackEngine createPlaybackEngine({
  required AudioContext speechContext,
  required AudioContext hintContext,
  PlaybackLogFn? onLog,
}) {
  return impl.createPlaybackEngine(
    speechContext: speechContext,
    hintContext: hintContext,
    onLog: onLog,
  );
}
