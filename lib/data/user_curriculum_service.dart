// ------------------------------------------------------------
// Ziel (Laien): User-spezifisches Curriculum-Delta (Cursor + Patches) vom Worker/R2 holen oder dorthin schreiben.
// Verbindung: robulingo_app.dart lädt Startcurriculum und legt Delta darüber; Fallback auf UserDeltaStore.
// Tücken: Mehrere Speicherorte (R2 + Worker-Endpoint) werden probiert; Netzwerkfehler werden geschluckt.
// ------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../flavor_config.dart';
import 'user_curriculum_delta.dart';

/// Holt/schreibt das User-Curriculum-Delta (schlanke Cursor+Patch-Datei).
class UserCurriculumService {
  UserCurriculumService({
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

  Future<UserCurriculumDelta?> fetchDelta({
    required String userId,
    required String startKey,
  }) async {
    final candidates = <Uri>[
      Uri.parse(
          '${activeFlavor.userDataBucketVirtualHost}/$userId/curriculum_delta.json'),
      Uri.parse(
          '${activeFlavor.userDataBucketPathBase}/$userId/curriculum_delta.json'),
      Uri.parse(
          '${activeFlavor.userDataBucketVirtualHost}/$userId/$startKey.delta.json'),
      Uri.parse(
          '${activeFlavor.userDataBucketPathBase}/$userId/$startKey.delta.json'),
      _path('/user-curriculum', {'uid': userId, 'start': startKey}),
    ];
    final workerHeaders = withFlavorHeader(<String, String>{});
    for (final uri in candidates) {
      try {
        final useWorkerHeaders = uri.host == workerHost;
        final res = await _http
            .get(uri, headers: useWorkerHeaders ? workerHeaders : null)
            .timeout(_timeout);
        if (res.statusCode != 200 || res.body.isEmpty) continue;
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        return tryParseDelta(data as Map<String, dynamic>?);
      } catch (e) {
        debugPrint('[user-delta][fetch-error] $uri $e');
      }
    }
    return null;
  }

  Future<bool> pushDelta({
    required String userId,
    required String startKey,
    required UserCurriculumDelta delta,
  }) async {
    final uri = _path('/user-curriculum');
    try {
      final res = await _http
          .post(uri,
              headers: withFlavorHeader({'content-type': 'application/json'}),
              body: jsonEncode({
                'uid': userId,
                'start': startKey,
                'delta': delta.toJson(),
              }))
          .timeout(_timeout);
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (!ok) {
        debugPrint(
            '[user-delta][push-status] ${res.statusCode} body=${res.body}');
      }
      return ok;
    } catch (e) {
      debugPrint('[user-delta][push-error] $e');
      return false;
    }
  }
}
