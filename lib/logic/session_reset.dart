import 'item_stats.dart';
import 'item_presentation_policy.dart';
import 'trial_buffer.dart';

class SessionResetDeps {
  SessionResetDeps({
    required this.trialBuffer,
    required this.itemByUuid,
    required this.presentationPolicy,
    required this.itemStats,
    required this.comprehensionHistory,
    required this.namingHistory,
    required this.comprehensionSeen,
    required this.loadErrors,
    required this.correctCounts,
    required this.audioPlayCounts,
    required this.audioMaxSequenceIndex,
    required this.audioMinSequenceIndex,
    required this.audioUrlOkCache,
    required this.imageVariantCursorByUuid,
  });

  final TrialBuffer trialBuffer;
  final Map<String, Object?> itemByUuid;
  final ItemPresentationPolicy presentationPolicy;
  final ItemStatsTracker itemStats;
  final List<bool> comprehensionHistory;
  final List<bool> namingHistory;
  final Set<String> comprehensionSeen;
  final List<String> loadErrors;
  final Map<String, int> correctCounts;
  final Map<String, int> audioPlayCounts;
  final Map<String, int> audioMaxSequenceIndex;
  final Map<String, int> audioMinSequenceIndex;
  final Map<String, bool> audioUrlOkCache;
  final Map<String, int> imageVariantCursorByUuid;
}

void resetSessionState({
  required SessionResetDeps deps,
  required void Function() cancelNativeSelectTimer,
  required void Function() clearHintRevealed,
}) {
  deps.trialBuffer.reset();
  deps.itemByUuid.clear();
  deps.presentationPolicy.reset();
  deps.comprehensionSeen.clear();
  deps.comprehensionHistory.clear();
  deps.namingHistory.clear();
  deps.loadErrors.clear();
  deps.correctCounts.clear();
  deps.imageVariantCursorByUuid.clear();
  deps.audioPlayCounts.clear();
  deps.audioMaxSequenceIndex.clear();
  deps.audioMinSequenceIndex.clear();
  deps.audioUrlOkCache.clear();
  cancelNativeSelectTimer();
  clearHintRevealed();
  deps.itemStats.reset();
}
