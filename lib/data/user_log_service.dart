import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';

class UserLogService {
  UserLogService({
    required this.workerHost,
    required this.apiPrefix,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String workerHost;
  final String apiPrefix;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 10);

  Uri _path(String path, [Map<String, String>? query]) {
    return Uri.https(workerHost, '$apiPrefix$path', query);
  }

  Future<List<String>> fetchLines({required String userId}) async {
    if (userId.isEmpty) return const [];
    final candidates = <Uri>[
      Uri.parse('$userDataBucketVirtualHost/$userId/events.ndjson'),
      Uri.parse('$userDataBucketPathBase/$userId/events.ndjson'),
      Uri.parse('$userDataBucketVirtualHost/$userId/logs/events.ndjson'),
      Uri.parse('$userDataBucketPathBase/$userId/logs/events.ndjson'),
      _path('/user-logs', {'uid': userId}),
      _path('/logs', {'uid': userId}),
      _path('/log', {'uid': userId}),
    ];
    for (final uri in candidates) {
      try {
        final res = await _http.get(uri).timeout(_timeout);
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) continue;
        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final lines = body
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false);
        if (lines.isNotEmpty) return lines;
      } catch (e) {
        debugPrint('[user-log][fetch-error] $uri $e');
      }
    }
    return const [];
  }
}
