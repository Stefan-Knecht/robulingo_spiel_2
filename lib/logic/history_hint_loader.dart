import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants.dart';

class HistoryHintLoader {
  HistoryHintLoader({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  String? _cache;

  Future<String> loadHint(String l1) async {
    if (_cache != null) return _cache!;
    const fallback =
        'Copy and store the number of your user history so that you can reload it and do not have to start from the very beginning again if your electronic device loses the history.';
    final norm = l1.trim().toLowerCase();
    if (norm.isEmpty) return fallback;
    final keyTxt = 'history_hint_$norm.txt';
    final keyJson = 'history_hint_$norm.json';
    final urls = [
      '$hintsBucketVirtualHost/$keyTxt',
      '$hintsBucketPathBase/$keyTxt',
      '$hintsBucketVirtualHost/$keyJson',
      '$hintsBucketPathBase/$keyJson',
    ];
    for (final url in urls) {
      try {
        final res = await _http.get(Uri.parse(url));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) continue;
        final body = utf8.decode(res.bodyBytes);
        if (url.endsWith('.json')) {
          final data = jsonDecode(body);
          if (data is Map) {
            final text =
                (data['text'] ?? data['hint'] ?? data['message'])?.toString();
            if (text != null && text.trim().isNotEmpty) {
              _cache = text.trim();
              return _cache!;
            }
          }
        } else if (body.trim().isNotEmpty) {
          _cache = body.trim();
          return _cache!;
        }
      } catch (_) {
        // ignore
      }
    }
    return fallback;
  }
}
