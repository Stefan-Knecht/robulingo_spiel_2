import 'dart:convert';
import 'resume_state_controller.dart';
import 'log_storage.dart';

class CursorResolution {
  const CursorResolution({
    required this.cursor,
    required this.source,
    this.uuid,
    this.updatedAt,
  });

  final int cursor;
  final String source;
  final String? uuid;
  final DateTime? updatedAt;
}

Future<String?> loadLogDerivedCursorUuid({
  required String? userId,
  required String startKey,
  required String lang,
}) async {
  try {
    final storage = LogStorage();
    final lines = await storage.readLines();
    if (lines.isEmpty) return null;

    final String? uid = (userId != null && userId.isNotEmpty) ? userId : null;
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      Map<String, dynamic> data;
      try {
        data = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (data['type'] != 'trial_result') continue;
      if (data['is_refiller'] == true) continue;

      final eventUser = (data['user'] as String?)?.trim();
      if (uid != null &&
          eventUser != null &&
          eventUser.isNotEmpty &&
          eventUser != uid) {
        continue;
      }

      final uuid = (data['uuid'] as String?)?.trim();
      if (uuid == null || uuid.isEmpty) continue;

      final eventStart = (data['start_key'] as String?)?.trim();
      if (eventStart == startKey) {
        return uuid;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

int? indexOfUuidInList(List<String> uuids, String uuid) {
  final idx = uuids.indexOf(uuid);
  return idx >= 0 ? idx : null;
}

Future<int?> resolveCursorIndex({
  required String startKey,
  required String lang,
  required List<String> curriculumUuids,
  required String? userId,
  required String? nativeLang,
  required int? deltaCursor,
  required ResumeStateController resumeStateController,
}) async {
  final resolution = await resolveCursor(
    startKey: startKey,
    lang: lang,
    curriculumUuids: curriculumUuids,
    userId: userId,
    nativeLang: nativeLang,
    deltaCursor: deltaCursor,
    resumeStateController: resumeStateController,
  );
  return resolution?.cursor;
}

Future<CursorResolution?> resolveCursor({
  required String startKey,
  required String lang,
  required List<String> curriculumUuids,
  required String? userId,
  required String? nativeLang,
  required int? deltaCursor,
  required ResumeStateController resumeStateController,
}) async {
  if (resumeStateController.fallbackEnabled) {
    final entry = resumeStateController.entryForStartKey(startKey);
    if (entry != null && entry.cursor >= 0) {
      final idx = entry.cursor;
      return CursorResolution(
        cursor: idx,
        source: 'cloud_resume_state',
        uuid: idx >= 0 && idx < curriculumUuids.length
            ? curriculumUuids[idx]
            : null,
        updatedAt: entry.date.toUtc(),
      );
    }
  }
  final logUuid = await loadLogDerivedCursorUuid(
    userId: userId,
    startKey: startKey,
    lang: lang,
  );
  if (logUuid != null) {
    final idx = indexOfUuidInList(curriculumUuids, logUuid);
    if (idx != null) {
      return CursorResolution(
        cursor: idx,
        source: 'local_trial_log',
        uuid: logUuid,
      );
    }
  }
  if (deltaCursor != null && deltaCursor >= 0) {
    return CursorResolution(
      cursor: deltaCursor,
      source: 'user_curriculum_delta',
      uuid: deltaCursor >= 0 && deltaCursor < curriculumUuids.length
          ? curriculumUuids[deltaCursor]
          : null,
    );
  }
  return null;
}
