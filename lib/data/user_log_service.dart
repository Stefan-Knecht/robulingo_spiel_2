import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../flavor_config.dart';

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
      Uri.parse(
          '${activeFlavor.userDataBucketVirtualHost}/$userId/events.ndjson'),
      Uri.parse('${activeFlavor.userDataBucketPathBase}/$userId/events.ndjson'),
      Uri.parse(
          '${activeFlavor.userDataBucketVirtualHost}/$userId/logs/events.ndjson'),
      Uri.parse(
          '${activeFlavor.userDataBucketPathBase}/$userId/logs/events.ndjson'),
      _path('/user-logs', {'uid': userId}),
      _path('/logs', {'uid': userId}),
      _path('/log', {'uid': userId}),
    ];
    final workerHeaders = withFlavorHeader(<String, String>{});
    for (final uri in candidates) {
      try {
        final useWorkerHeaders = uri.host == workerHost;
        final res = await _http
            .get(uri, headers: useWorkerHeaders ? workerHeaders : null)
            .timeout(_timeout);
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
