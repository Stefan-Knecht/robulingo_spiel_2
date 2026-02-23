// ------------------------------------------------------------
// Ziel (Laien): App-Update-Infos vom Worker laden und "neue Version?" prüfen.
// Verbindung: Wird beim App-Start genutzt, um optional einen Download-Hinweis zu zeigen.
// Tücken: Android-only (APK-Flow); robust gegen fehlende/alte Felder im JSON.
// ------------------------------------------------------------
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../flavor_config.dart';
import '../utils/platform_info.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.flavor,
    required this.downloadUrl,
    this.versionCode,
    this.versionName,
    this.apkFile,
    this.uploadedAtUtc,
  });

  final String flavor;
  final int? versionCode;
  final String? versionName;
  final String downloadUrl;
  final String? apkFile;
  final String? uploadedAtUtc;

  String get versionLabel {
    final code = versionCode;
    final name = versionName?.trim();
    if (name != null && name.isNotEmpty && code != null && code > 0) {
      return '$name ($code)';
    }
    if (name != null && name.isNotEmpty) return name;
    if (code != null && code > 0) return code.toString();
    return 'unknown';
  }
}

class AppUpdateService {
  AppUpdateService({
    required this.workerHost,
    required this.apiPrefix,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String workerHost;
  final String apiPrefix;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 8);

  Future<AppUpdateInfo?> checkForAndroidUpdate({
    required int? localVersionCode,
    required String? localVersionName,
  }) async {
    if (operatingSystem != 'android') return null;
    final uri = Uri.https(
      workerHost,
      '${_normalizedApiPrefix(apiPrefix)}/android-release/latest',
      <String, String>{
        'flavor': activeFlavor.id,
        'source': 'app_start',
      },
    );
    try {
      final res = await _http
          .get(
            uri,
            headers: withFlavorHeader(<String, String>{
              'accept': 'application/json',
            }),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map) return null;
      final root = Map<String, dynamic>.from(body);
      final download = _cleanStr(root['download_url']) ??
          _cleanStr(root['tracked_download_url']) ??
          _cleanStr(root['apk_url']);
      if (download == null || download.isEmpty) return null;
      final remoteCode = _toInt(root['version_code']);
      final remoteName =
          _cleanStr(root['version_name']) ?? _cleanStr(root['version']);
      final isNewer = _isRemoteNewer(
        localVersionCode: localVersionCode,
        localVersionName: localVersionName,
        remoteVersionCode: remoteCode,
        remoteVersionName: remoteName,
      );
      if (!isNewer) return null;
      return AppUpdateInfo(
        flavor: _cleanStr(root['flavor']) ?? activeFlavor.id,
        versionCode: remoteCode,
        versionName: remoteName,
        downloadUrl: download,
        apkFile: _cleanStr(root['apk_file']),
        uploadedAtUtc: _cleanStr(root['uploaded_at_utc']),
      );
    } catch (_) {
      return null;
    }
  }

  static String _normalizedApiPrefix(String raw) {
    final p = raw.trim().isEmpty ? '/api' : raw.trim();
    return p.startsWith('/') ? p : '/$p';
  }

  static String? _cleanStr(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return s;
  }

  static int? _toInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    final parsed = int.tryParse(raw.toString().trim());
    return parsed;
  }

  static bool _isRemoteNewer({
    required int? localVersionCode,
    required String? localVersionName,
    required int? remoteVersionCode,
    required String? remoteVersionName,
  }) {
    if (remoteVersionCode != null && localVersionCode != null) {
      return remoteVersionCode > localVersionCode;
    }
    final localParts = _parseVersionName(localVersionName);
    final remoteParts = _parseVersionName(remoteVersionName);
    if (localParts.isEmpty || remoteParts.isEmpty) return false;
    final maxLen = localParts.length > remoteParts.length
        ? localParts.length
        : remoteParts.length;
    for (var i = 0; i < maxLen; i++) {
      final local = i < localParts.length ? localParts[i] : 0;
      final remote = i < remoteParts.length ? remoteParts[i] : 0;
      if (remote > local) return true;
      if (remote < local) return false;
    }
    return false;
  }

  static List<int> _parseVersionName(String? raw) {
    final v = _cleanStr(raw);
    if (v == null) return const <int>[];
    final onlyNumbersAndDots = v.replaceAll(RegExp(r'[^0-9.]'), '.');
    return onlyNumbersAndDots
        .split('.')
        .where((p) => p.trim().isNotEmpty)
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList(growable: false);
  }
}
