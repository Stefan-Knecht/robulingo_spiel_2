import '../data/api_client.dart';
import '../data/models.dart';

class CurriculumLoadResult {
  CurriculumLoadResult({
    required this.curriculum,
    required this.resolvedStart,
    required this.errors,
  });

  final List<CurriculumEntry> curriculum;
  final String resolvedStart;
  final List<String> errors;
}

typedef StartKeyChanged = void Function(String newStart);

Future<CurriculumLoadResult> loadCurriculumWithFallback({
  required ApiClient api,
  required String resolvedStart,
  required String baseStart,
  required bool explicitStartRequested,
  required bool allowDefaultFallback,
  required String lang,
  StartKeyChanged? onStartKeyChanged,
}) async {
  final errors = <String>[];
  var currentStart = resolvedStart;
  List<CurriculumEntry> curriculum = [];
  try {
    curriculum = await api.loadStartCurriculum(currentStart,
        allowDefaultFallback: allowDefaultFallback, requireCompleteForLang: lang);
    if (curriculum.isEmpty && currentStart != baseStart) {
      final previousStart = currentStart;
      currentStart = baseStart;
      onStartKeyChanged?.call(currentStart);
      errors.add('Start-Curriculum leer ($previousStart) -> verwende $currentStart.');
      curriculum = await api.loadStartCurriculum(currentStart,
          allowDefaultFallback: allowDefaultFallback,
          requireCompleteForLang: lang);
    }
  } catch (e) {
    if (currentStart != baseStart) {
      final failedStart = currentStart;
      errors.add(
          'Start-Curriculum fehlgeschlagen ($failedStart): $e, versuche $baseStart');
      currentStart = baseStart;
      onStartKeyChanged?.call(currentStart);
      try {
        curriculum = await api.loadStartCurriculum(currentStart,
            allowDefaultFallback: allowDefaultFallback,
            requireCompleteForLang: lang);
      } catch (baseError) {
        if (explicitStartRequested) {
          rethrow;
        }
        errors.add(
            'Start-Curriculum fehlgeschlagen ($currentStart): $baseError');
        curriculum = await api.loadCurriculum(lang);
      }
    } else {
      if (explicitStartRequested) {
        rethrow;
      }
      errors.add('Start-Curriculum fehlgeschlagen ($currentStart): $e');
      curriculum = await api.loadCurriculum(lang);
    }
  }
  return CurriculumLoadResult(
    curriculum: curriculum,
    resolvedStart: currentStart,
    errors: errors,
  );
}
