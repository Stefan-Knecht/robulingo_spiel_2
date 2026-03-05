import '../data/models.dart';
import 'naming_controller.dart';
import 'naming_locale_helper.dart';
import 'presentation_protocol_log.dart';
import 'voice_state.dart';

Future<NamingFlowOutcome?> runNamingFlow({
  required VoiceController voiceController,
  required NamingLocaleHelper namingLocaleHelper,
  required PresentationProtocolLog protocolLog,
  required Map<String, String> speechLocaleOverrides,
  required String lang,
  required int token,
  required Trial trial,
  required bool Function() isCurrent,
  required bool Function(String transcript, String targetText) scorer,
  required Future<void> Function(ItemData item) playHintAudioForItem,
  required void Function(String transcript) onTranscript,
  required bool userInitiated,
  Duration firstWindow = const Duration(seconds: 4),
  Duration repeatWindow = const Duration(seconds: 3),
  Future<String?>? localeIdFuture,
}) async {
  final String? localeId = await (localeIdFuture ??
      namingLocaleHelper.resolveAndLog(
        speech: voiceController.speech,
        lang: lang,
        overrides: speechLocaleOverrides,
        protocolLog: protocolLog,
      ));
  return voiceController.startNamingFlow(
    token: token,
    targetText: trial.target.text,
    scorer: scorer,
    playHint: () async {
      if (!isCurrent()) return;
      await playHintAudioForItem(trial.target);
      if (!isCurrent()) return;
      await Future.delayed(const Duration(milliseconds: 250));
      if (!isCurrent()) return;
      await playHintAudioForItem(trial.target);
    },
    onTranscript: (text) {
      if (!isCurrent()) return;
      onTranscript(text);
    },
    isCurrent: isCurrent,
    userInitiated: userInitiated,
    firstWindow: firstWindow,
    repeatWindow: repeatWindow,
    allowRepeat: true,
    localeId: localeId,
  );
}
