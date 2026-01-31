typedef VoidFuture = Future<void> Function();
typedef StartKeyResolver = Future<String> Function(String startKey);
typedef StartKeySetter = void Function(String startKey);

class SessionPrepareResult {
  SessionPrepareResult({
    required this.baseStart,
    required this.resolvedStart,
    required this.explicitStartRequested,
  });

  final String baseStart;
  final String resolvedStart;
  final bool explicitStartRequested;
}

Future<SessionPrepareResult> prepareForInitialLoad({
  required String? startKey,
  required String? previousStartKey,
  required String defaultStartCurriculum,
  required StartKeyResolver resolveStartKeyForLang,
  required bool resetCursorOnNextLoad,
  required VoidFuture persistUserCursor,
  required bool loggerReady,
  required DateTime? sessionStart,
  required VoidFuture endLoggerSession,
  required StartKeySetter onResolvedStart,
  required VoidFuture resetLadder,
}) async {
  if (!resetCursorOnNextLoad) {
    await persistUserCursor();
  }
  if (loggerReady && sessionStart != null) {
    await endLoggerSession();
  }
  final baseStart = startKey ?? previousStartKey ?? defaultStartCurriculum;
  final bool explicitStartRequested =
      startKey != null || previousStartKey != null;
  final resolvedStart = await resolveStartKeyForLang(baseStart);
  onResolvedStart(resolvedStart);
  await resetLadder();
  return SessionPrepareResult(
    baseStart: baseStart,
    resolvedStart: resolvedStart,
    explicitStartRequested: explicitStartRequested,
  );
}
