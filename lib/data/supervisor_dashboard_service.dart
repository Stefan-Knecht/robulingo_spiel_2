import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:robulingo_flutter/flavor_config.dart';

class SupervisorDashboardService {
  SupervisorDashboardService({
    required this.workerHost,
    required this.apiPrefix,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String workerHost;
  final String apiPrefix;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 10);

  Uri _path(String path, [Map<String, String>? query]) =>
      Uri.https(workerHost, '$apiPrefix$path', query);

  Future<bool> enqueueEmoji({
    required String userId,
    required String emoji,
    String? reason,
    String? note,
    int priority = 0,
    Map<String, dynamic>? meta,
    String source = 'app',
  }) async {
    final uid = userId.trim();
    final emojiValue = emoji.trim();
    if (uid.isEmpty || emojiValue.isEmpty) return false;
    final body = <String, dynamic>{
      'emoji': emojiValue,
      'source': source,
      'priority': priority,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (meta != null && meta.isNotEmpty) 'meta': meta,
    };
    try {
      final res = await _http
          .post(
            _path('/emoji-queue'),
            headers: withFlavorHeader({
              'content-type': 'application/json',
              'x-user-id': uid,
            }),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[supervisor-dashboard][enqueue-emoji-error] $e');
      return false;
    }
  }

  Future<bool> enqueueVoiceFeedback({
    required String userId,
    required Uint8List audioBytes,
    String mimeType = 'audio/mp4',
    int? durationMs,
    String? reason,
    String? note,
    int priority = 0,
    Map<String, dynamic>? meta,
    String source = 'app',
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty || audioBytes.isEmpty) return false;
    final body = <String, dynamic>{
      'type': 'voice',
      'audioBase64': base64Encode(audioBytes),
      'mimeType': mimeType.trim().isEmpty ? 'audio/mp4' : mimeType.trim(),
      'source': source,
      'priority': priority,
      if (durationMs != null && durationMs > 0) 'durationMs': durationMs,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (meta != null && meta.isNotEmpty) 'meta': meta,
    };
    try {
      final res = await _http
          .post(
            _path('/emoji-queue'),
            headers: withFlavorHeader({
              'content-type': 'application/json',
              'x-user-id': uid,
            }),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[supervisor-dashboard][enqueue-voice-error] $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchDashboardInfo({
    required String userId,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return null;
    try {
      final res = await _http
          .get(
            _path('/dashboard-info'),
            headers: withFlavorHeader({'x-user-id': uid}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (e) {
      debugPrint('[supervisor-dashboard][dashboard-info-error] $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchEmojiQueue({
    required String userId,
    String status = 'pending',
    int limit = 50,
    int cursor = 0,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return const [];
    try {
      final res = await _http
          .get(
            _path('/emoji-queue', {
              'status': status,
              'limit': '$limit',
              'cursor': '$cursor',
            }),
            headers: withFlavorHeader({'x-user-id': uid}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return const [];
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return const [];
      final rawItems = decoded['items'];
      if (rawItems is! List) return const [];
      return rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[supervisor-dashboard][emoji-queue-read-error] $e');
      return const [];
    }
  }

  Future<Uint8List?> fetchFeedbackAudio({
    required String userId,
    required String feedbackId,
  }) async {
    final uid = userId.trim();
    final fid = feedbackId.trim();
    if (uid.isEmpty || fid.isEmpty) return null;
    try {
      final res = await _http
          .get(
            _path('/feedback-audio', {'feedbackId': fid}),
            headers: withFlavorHeader({'x-user-id': uid}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint(
          '[supervisor-dashboard][feedback-audio-http] status=${res.statusCode} uid=$uid fid=$fid',
        );
        return null;
      }
      if (res.bodyBytes.isEmpty) {
        debugPrint(
          '[supervisor-dashboard][feedback-audio-empty] uid=$uid fid=$fid',
        );
        return null;
      }
      return res.bodyBytes;
    } catch (e) {
      debugPrint('[supervisor-dashboard][feedback-audio-error] $e');
      return null;
    }
  }

  Future<bool> ackEmojiQueue({
    required String userId,
    required List<String> ids,
    String status = 'delivered',
    bool remove = false,
  }) async {
    final uid = userId.trim();
    final cleanedIds = ids
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uid.isEmpty || cleanedIds.isEmpty) return false;
    final body = <String, dynamic>{
      'ids': cleanedIds,
      if (remove)
        'mode': 'remove'
      else ...{
        'mode': 'status',
        'status': status,
      },
    };
    try {
      final res = await _http
          .post(
            _path('/emoji-queue-ack'),
            headers: withFlavorHeader({
              'content-type': 'application/json',
              'x-user-id': uid,
            }),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[supervisor-dashboard][emoji-queue-ack-error] $e');
      return false;
    }
  }
}
