import 'package:audioplayers/audioplayers.dart';

import 'playback_engine.dart';

PlaybackEngine createPlaybackEngine({
  required AudioContext speechContext,
  required AudioContext hintContext,
  PlaybackLogFn? onLog,
}) {
  throw UnsupportedError('No playback engine for this platform');
}
