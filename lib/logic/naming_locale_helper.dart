import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'asr_locale_resolver.dart';
import 'presentation_protocol_log.dart';

class NamingLocaleHelper {
  String? _cachedLocaleId;
  String? _cachedLocaleLang;

  Future<String?> resolveAndLog({
    required stt.SpeechToText speech,
    required String lang,
    required Map<String, String> overrides,
    required PresentationProtocolLog protocolLog,
  }) async {
    final localeId = await _resolveLocaleId(
      speech: speech,
      lang: lang,
      overrides: overrides,
    );
    try {
      final locales = await speech.locales();
      final system = await speech.systemLocale();
      final used = localeId ?? 'system-default';
      final method = (localeId == null)
          ? 'system-default'
          : (locales.isEmpty ? 'fallback-no-locales' : 'resolved');
      protocolLog.addNote(
          'ASR locale (naming): l2=$lang used=$used system=${system?.localeId ?? "-"} locales=${locales.length} method=$method');
    } catch (_) {
      final used = localeId ?? 'system-default';
      protocolLog.addNote('ASR locale (naming): l2=$lang used=$used');
    }
    return localeId;
  }

  Future<String?> _resolveLocaleId({
    required stt.SpeechToText speech,
    required String lang,
    required Map<String, String> overrides,
  }) async {
    if (_cachedLocaleLang == lang && _cachedLocaleId != null) {
      return _cachedLocaleId;
    }
    try {
      final locales = await speech.locales();
      final override = overrides[lang];
      final resolved = const AsrLocaleResolver().resolveFromLocales(
        locales,
        lang: lang,
        overrideLocaleId: override,
      );
      _cachedLocaleId =
          resolved ?? (override?.isNotEmpty == true ? override : lang);
      _cachedLocaleLang = lang;
      return _cachedLocaleId;
    } catch (_) {
      return null;
    }
  }
}
