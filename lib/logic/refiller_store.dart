import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RefillerState {
  RefillerState({required this.queue});

  final List<String> queue;

  factory RefillerState.fromJson(Map<String, dynamic> json) {
    return RefillerState(
      queue: (json['queue'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'queue': queue,
      };
}

/// Local per-user + per-curriculum FIFO refiller queue.
class RefillerStore {
  Future<File> _file({
    required String userId,
    required String startKey,
    required String lang,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeStart = startKey.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final safeLang = lang.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final safeUser = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final file = File(
        '${dir.path}/refiller_${safeUser}_${safeStart}_${safeLang}.json');
    await file.parent.create(recursive: true);
    return file;
  }

  Future<RefillerState> load({
    required String userId,
    required String startKey,
    required String lang,
  }) async {
    try {
      final f = await _file(userId: userId, startKey: startKey, lang: lang);
      if (!await f.exists()) return RefillerState(queue: []);
      final raw = await f.readAsString();
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) return RefillerState.fromJson(data);
      return RefillerState(queue: []);
    } catch (_) {
      return RefillerState(queue: []);
    }
  }

  Future<void> save({
    required String userId,
    required String startKey,
    required String lang,
    required RefillerState state,
  }) async {
    try {
      final f = await _file(userId: userId, startKey: startKey, lang: lang);
      await f.writeAsString(jsonEncode(state.toJson()));
    } catch (_) {
      // ignore
    }
  }
}
