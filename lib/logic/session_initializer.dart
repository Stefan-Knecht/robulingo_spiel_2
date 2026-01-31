import '../data/models.dart';
import '../logic/curriculum_loader.dart';
import '../data/api_client.dart';

class SessionInitOutcome {
  SessionInitOutcome({
    required this.resolvedStart,
    required this.curriculum,
    required this.errors,
  });

  final String resolvedStart;
  final List<CurriculumEntry> curriculum;
  final List<String> errors;
}

Future<SessionInitOutcome> initializeSession({
  required String resolvedStart,
  required String baseStart,
  required bool explicitStartRequested,
  required bool allowDefaultFallback,
  required String lang,
  required ApiClient api,
  required StartKeyChanged onStartKeyChanged,
}) async {
  final result = await loadCurriculumWithFallback(
    api: api,
    resolvedStart: resolvedStart,
    baseStart: baseStart,
    explicitStartRequested: explicitStartRequested,
    allowDefaultFallback: allowDefaultFallback,
    lang: lang,
    onStartKeyChanged: onStartKeyChanged,
  );
  return SessionInitOutcome(
    resolvedStart: result.resolvedStart,
    curriculum: result.curriculum,
    errors: result.errors,
  );
}
