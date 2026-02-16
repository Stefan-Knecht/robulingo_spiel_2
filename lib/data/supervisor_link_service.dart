import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:robulingo_flutter/flavor_config.dart';

class SupervisorSyncResult {
  const SupervisorSyncResult({
    required this.attempted,
    required this.success,
    this.statusKey,
  });

  final bool attempted;
  final bool success;
  final String? statusKey;

  static const SupervisorSyncResult skipped = SupervisorSyncResult(
    attempted: false,
    success: true,
    statusKey: null,
  );
}

class SupervisorLinkService {
  SupervisorLinkService({
    required this.workerHost,
    required this.apiPrefix,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String workerHost;
  final String apiPrefix;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 10);

  Uri _path(String path) => Uri.https(workerHost, '$apiPrefix$path');

  Future<SupervisorSyncResult> sync({
    required String userId,
    required bool monitoringOn,
    required String supervisorEmail,
    required String supervisorCode,
    required String internalLearnerName,
    required String comment,
    required String uiLanguage,
    String textVersion = 'trial_v1',
  }) async {
    final uid = userId.trim();
    final email = supervisorEmail.trim();
    final code = supervisorCode.trim();
    final internalName = internalLearnerName.trim();
    final note = comment.trim();
    final uiLang = uiLanguage.trim().toLowerCase();

    if (uid.isEmpty) {
      return const SupervisorSyncResult(
        attempted: true,
        success: false,
        statusKey: 'status_supervisor_missing_userid',
      );
    }

    final hasAnyInput = monitoringOn ||
        email.isNotEmpty ||
        code.isNotEmpty ||
        internalName.isNotEmpty ||
        note.isNotEmpty;
    if (!hasAnyInput) return SupervisorSyncResult.skipped;

    if (code.isNotEmpty && !_isValidSupervisorCode(code)) {
      return const SupervisorSyncResult(
        attempted: true,
        success: false,
        statusKey: 'status_supervisor_invalid_code',
      );
    }

    try {
      final consentMinimal = <String, dynamic>{
        'monitoring_on': monitoringOn,
        'text_version': textVersion,
      };
      final consentExtended = <String, dynamic>{
        ...consentMinimal,
        if (internalName.isNotEmpty) 'internal_name': internalName,
        if (note.isNotEmpty) 'comment': note,
        if (uiLang.isNotEmpty) 'ui_language': uiLang,
      };
      final consentOk = await _postWithFallback(
        path: '/consent',
        userId: uid,
        minimalBody: consentMinimal,
        extendedBody: consentExtended,
      );
      if (!consentOk) {
        return const SupervisorSyncResult(
          attempted: true,
          success: false,
          statusKey: 'status_supervisor_consent_failed',
        );
      }

      if (!monitoringOn) {
        return const SupervisorSyncResult(
          attempted: true,
          success: true,
          statusKey: 'status_supervisor_consent_saved_only',
        );
      }

      if (email.isEmpty || code.isEmpty) {
        return const SupervisorSyncResult(
          attempted: true,
          success: false,
          statusKey: 'status_supervisor_missing_pair_fields',
        );
      }

      final pairMinimal = <String, dynamic>{
        'supervisor_email': email,
        'supervisor_code': code,
        'supervisor_code_5': code,
      };
      final pairExtended = <String, dynamic>{
        ...pairMinimal,
        if (internalName.isNotEmpty) 'internal_name': internalName,
        if (note.isNotEmpty) 'comment': note,
        if (uiLang.isNotEmpty) 'ui_language': uiLang,
      };
      final pairOk = await _postWithFallback(
        path: '/pair',
        userId: uid,
        minimalBody: pairMinimal,
        extendedBody: pairExtended,
      );
      if (!pairOk) {
        return const SupervisorSyncResult(
          attempted: true,
          success: false,
          statusKey: 'status_supervisor_pair_failed',
        );
      }

      return const SupervisorSyncResult(
        attempted: true,
        success: true,
        statusKey: 'status_supervisor_pair_saved',
      );
    } catch (e) {
      debugPrint('[supervisor-sync][error] $e');
      return const SupervisorSyncResult(
        attempted: true,
        success: false,
        statusKey: 'status_supervisor_sync_unexpected',
      );
    }
  }

  Future<bool> _postWithFallback({
    required String path,
    required String userId,
    required Map<String, dynamic> minimalBody,
    required Map<String, dynamic> extendedBody,
  }) async {
    final extendedOk =
        await _postJson(path: path, userId: userId, body: extendedBody);
    if (extendedOk) return true;
    if (_mapsEquivalent(extendedBody, minimalBody)) return false;
    return _postJson(path: path, userId: userId, body: minimalBody);
  }

  Future<bool> _postJson({
    required String path,
    required String userId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _http
        .post(
          _path(path),
          headers: withFlavorHeader(<String, String>{
            'content-type': 'application/json',
            'x-user-id': userId,
          }),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  bool _mapsEquivalent(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  bool _isValidSupervisorCode(String raw) {
    return RegExp(r'^[A-Za-z0-9]{5}$').hasMatch(raw.trim());
  }
}
