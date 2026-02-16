// ------------------------------------------------------------
// Ziel (Laien): Lokale NDJSON-Logs komprimiert an den Worker schicken (R2-Backend).
// Verbindung: Wird vom EventLogger getriggert; erwartet gültigen Worker-Host/API-Prefix.
// Tücken: Läuft asynchron und schweigt bei Fehlern; Upload-Frequenz wird im Logger gesteuert.
// ------------------------------------------------------------
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:robulingo_flutter/flavor_config.dart';

/// Schickt NDJSON-Batches (komprimiert) an den Worker, der nach R2 schreibt.
class LogUploader {
  LogUploader({
    required this.workerHost,
    required this.apiPrefix,
    this.endpointPath = '/log',
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String workerHost;
  final String apiPrefix;
  final String endpointPath;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 12);

  Uri _path(String path) => Uri.https(workerHost, '$apiPrefix$path');

  Future<bool> upload({
    required String userId,
    required List<String> lines,
    String? sessionId,
  }) async {
    if (lines.isEmpty) return true;
    final body = '${lines.join('\n')}\n';
    final rawBytes = utf8.encode(body);
    List<int> payload = rawBytes;
    String? contentEncoding;
    if (!kIsWeb) {
      try {
        payload = gzip.encode(rawBytes);
        contentEncoding = 'gzip';
      } catch (e) {
        debugPrint('[log-upload][compress-error] $e');
        payload = rawBytes;
        contentEncoding = null;
      }
    }
    try {
      final uri = _path(endpointPath);
      final headers = <String, String>{
        'content-type': 'application/x-ndjson',
        if (contentEncoding != null) 'content-encoding': contentEncoding,
        'x-user-id': userId,
      };
      if (sessionId != null && sessionId.isNotEmpty) {
        headers['x-session-id'] = sessionId;
      }
      final requestHeaders = withFlavorHeader(headers);
      final res = await _http
          .post(
            uri,
            headers: requestHeaders,
            body: payload,
          )
          .timeout(_timeout);
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (!ok) {
        debugPrint(
            '[log-upload] endpoint=$endpointPath status=${res.statusCode} body=${res.body}');
      }
      return ok;
    } catch (e) {
      final uri = _path(endpointPath);
      debugPrint('[log-upload][error] endpoint=$endpointPath uri=$uri err=$e');
      return false;
    }
  }
}
