import '../data/resume_state_service.dart';

class ResumeStateController {
  ResumeStateController({required this.service});

  final ResumeStateService service;
  ResumeState? state;

  bool get fallbackEnabled => state != null && state!.entries.isNotEmpty;

  ResumeStateEntry? mostRecentEntry() => state?.mostRecentEntry();

  ResumeStateEntry? entryForStartKey(String startKey) =>
      state?.entryForStartKey(startKey);

  Future<ResumeState?> fetchAndSet(String userId) async {
    if (userId.isEmpty) return null;
    final fetched = await service.fetch(userId: userId);
    if (fetched == null ||
        (fetched.entries.isEmpty && !fetched.hasLanguagePreferences)) {
      return null;
    }
    state = fetched;
    return fetched;
  }

  void setState(ResumeState? next) {
    state = next;
  }

  Future<void> pushEntry({
    required String userId,
    required ResumeStateEntry entry,
    bool fetchExisting = true,
  }) async {
    if (userId.isEmpty) return;
    final existing = state ??
        (fetchExisting ? await service.fetch(userId: userId) : null) ??
        ResumeState(userId: userId, entries: []);
    final updated = <ResumeStateEntry>[];
    bool replaced = false;
    for (final e in existing.entries) {
      if (e.startKey == entry.startKey) {
        updated.add(entry);
        replaced = true;
      } else {
        updated.add(e);
      }
    }
    if (!replaced) updated.add(entry);
    final next = existing.copyWith(
      userId: userId,
      entries: updated,
      updatedAt: DateTime.now().toUtc(),
    );
    state = next;
    await service.push(userId: userId, state: next);
  }

  Future<void> pushLanguagePreferences({
    required String userId,
    required String lang,
    required String? nativeLang,
    required String? startKey,
    required String? moduleRowId,
    required String? moduleMode,
    bool fetchExisting = true,
  }) async {
    if (userId.isEmpty || lang.trim().isEmpty) return;
    final existing = state ??
        (fetchExisting ? await service.fetch(userId: userId) : null) ??
        ResumeState(userId: userId, entries: []);
    final next = existing.copyWith(
      userId: userId,
      lastLang: lang.trim().toLowerCase(),
      lastNativeLang: nativeLang?.trim().isEmpty == true
          ? null
          : nativeLang?.trim().toLowerCase(),
      lastStartKey: startKey?.trim().isEmpty == true ? null : startKey?.trim(),
      lastModuleRowId:
          moduleRowId?.trim().isEmpty == true ? null : moduleRowId?.trim(),
      lastModuleMode:
          moduleMode?.trim().isEmpty == true ? null : moduleMode?.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    state = next;
    await service.push(userId: userId, state: next);
  }

  int? cursorForStartKey({
    required String startKey,
    required String lang,
    required String? nativeLang,
  }) {
    final entry = entryForStartKey(startKey);
    if (entry == null) return null;
    if (entry.cursor < 0) return null;
    return entry.cursor;
  }
}
