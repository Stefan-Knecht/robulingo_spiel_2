// ------------------------------------------------------------
// Ziel (Laien): Lokale NDJSON-Logs komprimiert an den Worker schicken (R2-Backend).
// Verbindung: Wird vom EventLogger getriggert; erwartet gültigen Worker-Host/API-Prefix.
// Tücken: Läuft asynchron und schweigt bei Fehlern; Upload-Frequenz wird im Logger gesteuert.
// ------------------------------------------------------------
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Schickt NDJSON-Batches (komprimiert) an den Worker, der nach R2 schreibt.
class LogUploader {
  LogUploader({required this.workerHost, required this.apiPrefix, http.Client? client})
      : _http = client ?? http.Client();

  final String workerHost;
  final String apiPrefix;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 12);

  Uri _path(String path) => Uri.https(workerHost, '$apiPrefix$path');

  Future<bool> upload({
    required String userId,
    required List<String> lines,
  }) async {
    if (lines.isEmpty) return true;
    final body = '${lines.join('\n')}\n';
    final gz = gzip.encode(utf8.encode(body));
    try {
      final res = await _http
          .post(
            _path('/log'),
            headers: {
              'content-type': 'application/x-ndjson',
              'content-encoding': 'gzip',
              'x-user-id': userId,
            },
            body: gz,
          )
          .timeout(_timeout);
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (!ok) {
        debugPrint('[log-upload] status=${res.statusCode} body=${res.body}');
      }
      return ok;
    } catch (e) {
      debugPrint('[log-upload][error] $e');
      return false;
    }
  }
}
