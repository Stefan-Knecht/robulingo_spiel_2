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
    if (fetched == null || fetched.entries.isEmpty) return null;
    state = fetched;
    return fetched;
  }

  void setState(ResumeState? next) {
    state = next;
  }

  Future<void> pushEntry({
    required String userId,
    required ResumeStateEntry entry,
  }) async {
    if (userId.isEmpty) return;
    final existing =
        state ?? await service.fetch(userId: userId) ?? ResumeState(userId: userId, entries: []);
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
    final next = ResumeState(userId: userId, entries: updated);
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
    if (entry.lang != lang) return null;
    if ((entry.nativeLang ?? '') != (nativeLang ?? '')) return null;
    return entry.cursor;
  }
}
