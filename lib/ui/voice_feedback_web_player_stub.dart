typedef VoiceLogFn = void Function(String message);

Future<bool> playVoiceFeedbackWeb({
  required String url,
  VoiceLogFn? onLog,
}) async {
  onLog?.call(
    '[supervisor-resume] voice-web-player unavailable on this platform',
  );
  return false;
}

Future<void> stopVoiceFeedbackWeb() async {}
