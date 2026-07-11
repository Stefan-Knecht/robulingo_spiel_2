import 'dart:convert';

import 'package:robulingo_flutter/logic/app_key_value_store.dart';

class LocalProgressSnapshot {
  const LocalProgressSnapshot({
    required this.userId,
    required this.startKey,
    required this.cursor,
    required this.uuid,
    required this.updatedAt,
    required this.source,
  });

  final String userId;
  final String startKey;
  final int cursor;
  final String uuid;
  final DateTime updatedAt;
  final String source;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'startKey': startKey,
        'cursor': cursor,
        'uuid': uuid,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'source': source,
      };

  factory LocalProgressSnapshot.fromJson(Map<String, dynamic> json) {
    final rawUpdatedAt = (json['updatedAt'] as String?)?.trim();
    return LocalProgressSnapshot(
      userId: (json['userId'] as String?)?.trim() ?? '',
      startKey: (json['startKey'] as String?)?.trim() ?? '',
      cursor: (json['cursor'] as num?)?.toInt() ?? -1,
      uuid: (json['uuid'] as String?)?.trim() ?? '',
      updatedAt: rawUpdatedAt == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.tryParse(rawUpdatedAt)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      source: (json['source'] as String?)?.trim() ?? 'unknown',
    );
  }

  bool get isUsable => userId.isNotEmpty && startKey.isNotEmpty && cursor >= 0;
}

class LocalProgressStore {
  static const _prefix = 'robulingo_progress_v1';

  String _key({
    required String userId,
    required String startKey,
  }) =>
      '$_prefix:${Uri.encodeComponent(userId)}:${Uri.encodeComponent(startKey)}';

  Future<void> save(LocalProgressSnapshot snapshot) async {
    if (!snapshot.isUsable) return;
    final store = await openAppKeyValueStore('local-progress', 'save');
    if (store == null) return;
    await store.setString(
      _key(userId: snapshot.userId, startKey: snapshot.startKey),
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<LocalProgressSnapshot?> load({
    required String userId,
    required String startKey,
  }) async {
    if (userId.isEmpty || startKey.isEmpty) return null;
    final store = await openAppKeyValueStore('local-progress', 'load');
    if (store == null) return null;
    try {
      final raw = store.getString(_key(userId: userId, startKey: startKey));
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final snapshot =
          LocalProgressSnapshot.fromJson(Map<String, dynamic>.from(data));
      if (!snapshot.isUsable) return null;
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear({
    required String userId,
    required String startKey,
  }) async {
    if (userId.isEmpty || startKey.isEmpty) return;
    final store = await openAppKeyValueStore('local-progress', 'clear');
    if (store == null) return;
    await store.remove(_key(userId: userId, startKey: startKey));
  }
}
