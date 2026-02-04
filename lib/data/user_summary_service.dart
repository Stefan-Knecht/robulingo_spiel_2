import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class UserDaySummary {
  const UserDaySummary({
    required this.seconds,
    required this.runs,
    required this.sessions,
    this.lastEventTs,
  });

  final int seconds;
  final int runs;
  final int sessions;
  final int? lastEventTs;

  factory UserDaySummary.fromJson(Map<String, dynamic> json) {
    return UserDaySummary(
      seconds: (json['seconds'] as num?)?.toInt() ?? 0,
      runs: (json['runs'] as num?)?.toInt() ?? 0,
      sessions: (json['sessions'] as num?)?.toInt() ?? 0,
      lastEventTs: (json['lastEventTs'] as num?)?.toInt(),
    );
  }
}

class UserSummaryService {
  UserSummaryService({
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

  Future<Map<DateTime, UserDaySummary>> fetchSummary({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    if (userId.isEmpty) return const {};
    final fromKey = _dateKey(from);
    final toKey = _dateKey(to);
    try {
      final res = await _http
          .get(
            _path('/summary', {'from': fromKey, 'to': toKey}),
            headers: {'x-user-id': userId},
          )
          .timeout(_timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return const {};
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return const {};
      final days = data['days'];
      if (days is! List) return const {};
      final out = <DateTime, UserDaySummary>{};
      for (final entry in days) {
        if (entry is! Map) continue;
        final dateStr = (entry['date'] as String?)?.trim();
        if (dateStr == null || dateStr.isEmpty) continue;
        DateTime? date;
        try {
          date = DateTime.parse('${dateStr}T00:00:00Z').toUtc();
        } catch (_) {
          continue;
        }
        out[date] = UserDaySummary.fromJson(Map<String, dynamic>.from(entry));
      }
      return out;
    } catch (e) {
      debugPrint('[user-summary][fetch-error] $e');
      return const {};
    }
  }

  String _dateKey(DateTime dateUtc) {
    final utc = dateUtc.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
