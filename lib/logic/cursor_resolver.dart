import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'resume_state_controller.dart';

Future<String?> loadLogDerivedCursorUuid({
  required String? userId,
  required String startKey,
  required String lang,
}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/logs/events.ndjson');
    if (!await file.exists()) return null;
    final lines = await file.readAsLines();

    final String? uid = (userId != null && userId.isNotEmpty) ? userId : null;
    String? bestLangOnly;
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
      final eventLang = (data['lang'] as String?)?.trim();
      if (eventLang != lang) continue;

      final eventUser = (data['user'] as String?)?.trim();
      if (uid != null && eventUser != null && eventUser.isNotEmpty && eventUser != uid) {
        continue;
      }

      final uuid = (data['uuid'] as String?)?.trim();
      if (uuid == null || uuid.isEmpty) continue;

      final eventStart = (data['start_key'] as String?)?.trim();
      if (eventStart == startKey) {
        return uuid;
      }
      bestLangOnly ??= uuid;
    }
    return bestLangOnly;
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
  if (resumeStateController.fallbackEnabled) {
    final idx = resumeStateController.cursorForStartKey(
      startKey: startKey,
      lang: lang,
      nativeLang: nativeLang,
    );
    if (idx != null) return idx;
  }
  final logUuid = await loadLogDerivedCursorUuid(
    userId: userId,
    startKey: startKey,
    lang: lang,
  );
  if (logUuid != null) {
    final idx = indexOfUuidInList(curriculumUuids, logUuid);
    if (idx != null) return idx;
  }
  if (deltaCursor != null && deltaCursor >= 0) return deltaCursor;
  return null;
}
