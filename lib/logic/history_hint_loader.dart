import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants.dart';

class HistoryHintLoader {
  HistoryHintLoader({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final Map<String, String> _cacheByLang = {};

  Future<String> loadHint(String lang) async {
    const fallback =
        'Keep a copy of your progress reference in case your device loses it, so you can pick up where you left off.';
    final norm = lang.trim().toLowerCase();
    if (norm.isEmpty) return fallback;
    final cached = _cacheByLang[norm];
    if (cached != null) return cached;
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
              final value = text.trim();
              _cacheByLang[norm] = value;
              return value;
            }
          }
        } else if (body.trim().isNotEmpty) {
          final value = body.trim();
          _cacheByLang[norm] = value;
          return value;
        }
      } catch (_) {
        // ignore
      }
    }
    return fallback;
  }
}
