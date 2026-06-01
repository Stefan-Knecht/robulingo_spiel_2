import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:robulingo_flutter/flavor_config.dart';

class ResumeStateEntry {
  final String startKey;
  final String lang;
  final String? nativeLang;
  final int cursor;
  final DateTime date;
  final int? winsYou;
  final int? winsRival;

  ResumeStateEntry({
    required this.startKey,
    required this.lang,
    required this.nativeLang,
    required this.cursor,
    required this.date,
    this.winsYou,
    this.winsRival,
  });

  Map<String, dynamic> toJson() => {
        'startKey': startKey,
        'lang': lang,
        if (nativeLang != null) 'nativeLang': nativeLang,
        'cursor': cursor,
        'date': date.toUtc().toIso8601String(),
        if (winsYou != null) 'winsYou': winsYou,
        if (winsRival != null) 'winsRival': winsRival,
      };

  factory ResumeStateEntry.fromJson(Map<String, dynamic> json) {
    final startKey = (json['startKey'] as String?)?.trim() ?? '';
    final lang = (json['lang'] as String?)?.trim() ?? '';
    final nativeLang = (json['nativeLang'] as String?)?.trim();
    final cursor = (json['cursor'] as num?)?.toInt() ?? -1;
    final winsYou = (json['winsYou'] as num?)?.toInt();
    final winsRival = (json['winsRival'] as num?)?.toInt();
    final rawDate = (json['date'] as String?)?.trim();
    final parsed = rawDate != null ? DateTime.tryParse(rawDate) : null;
    return ResumeStateEntry(
      startKey: startKey,
      lang: lang,
      nativeLang: nativeLang?.isEmpty == true ? null : nativeLang,
      cursor: cursor,
      date: parsed ?? DateTime.now().toUtc(),
      winsYou: winsYou,
      winsRival: winsRival,
    );
  }
}

class ResumeState {
  final String userId;
  final List<ResumeStateEntry> entries;
  final String? lastLang;
  final String? lastNativeLang;
  final String? lastStartKey;
  final String? lastModuleRowId;
  final String? lastModuleMode;
  final DateTime? updatedAt;

  ResumeState({
    required this.userId,
    required this.entries,
    this.lastLang,
    this.lastNativeLang,
    this.lastStartKey,
    this.lastModuleRowId,
    this.lastModuleMode,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'entries': entries.map((e) => e.toJson()).toList(),
        if (lastLang != null) 'lastLang': lastLang,
        if (lastNativeLang != null) 'lastNativeLang': lastNativeLang,
        if (lastStartKey != null) 'lastStartKey': lastStartKey,
        if (lastModuleRowId != null) 'lastModuleRowId': lastModuleRowId,
        if (lastModuleMode != null) 'lastModuleMode': lastModuleMode,
        if (updatedAt != null)
          'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };

  factory ResumeState.fromJson(Map<String, dynamic> json) {
    final userId = (json['userId'] as String?)?.trim() ?? 'unknown';
    final rawEntries = json['entries'];
    final entries = <ResumeStateEntry>[];
    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is Map<String, dynamic>) {
          entries.add(ResumeStateEntry.fromJson(item));
        } else if (item is Map) {
          entries
              .add(ResumeStateEntry.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final rawUpdatedAt = (json['updatedAt'] as String?)?.trim();
    return ResumeState(
      userId: userId,
      entries: entries,
      lastLang: _clean(json['lastLang']),
      lastNativeLang: _clean(json['lastNativeLang']),
      lastStartKey: _clean(json['lastStartKey']),
      lastModuleRowId: _clean(json['lastModuleRowId']),
      lastModuleMode: _clean(json['lastModuleMode']),
      updatedAt: rawUpdatedAt != null ? DateTime.tryParse(rawUpdatedAt) : null,
    );
  }

  static String? _clean(Object? value) {
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  bool get hasLanguagePreferences =>
      (lastLang != null && lastLang!.trim().isNotEmpty) ||
      (lastNativeLang != null && lastNativeLang!.trim().isNotEmpty);

  ResumeState copyWith({
    String? userId,
    List<ResumeStateEntry>? entries,
    String? lastLang,
    String? lastNativeLang,
    String? lastStartKey,
    String? lastModuleRowId,
    String? lastModuleMode,
    DateTime? updatedAt,
  }) =>
      ResumeState(
        userId: userId ?? this.userId,
        entries: entries ?? this.entries,
        lastLang: lastLang ?? this.lastLang,
        lastNativeLang: lastNativeLang ?? this.lastNativeLang,
        lastStartKey: lastStartKey ?? this.lastStartKey,
        lastModuleRowId: lastModuleRowId ?? this.lastModuleRowId,
        lastModuleMode: lastModuleMode ?? this.lastModuleMode,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  ResumeStateEntry? mostRecentEntry() {
    if (entries.isEmpty) return null;
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries.first;
  }

  ResumeStateEntry? entryForStartKey(String startKey) {
    for (final e in entries) {
      if (e.startKey == startKey) return e;
    }
    return null;
  }
}

class ResumeStateService {
  ResumeStateService({
    required this.workerHost,
    required this.apiPrefix,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String workerHost;
  final String apiPrefix;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 10);

  Uri _path(String path) => Uri.https(workerHost, '$apiPrefix$path');

  Future<ResumeState?> fetch({required String userId}) async {
    if (userId.isEmpty) return null;
    try {
      final res = await _http
          .get(
            _path('/resume-state'),
            headers: withFlavorHeader({'x-user-id': userId}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200 || res.body.isEmpty) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      return ResumeState.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('[resume-state][fetch-error] $e');
      return null;
    }
  }

  Future<bool> push({
    required String userId,
    required ResumeState state,
  }) async {
    if (userId.isEmpty) return false;
    try {
      final res = await _http
          .post(
            _path('/resume-state'),
            headers: withFlavorHeader({
              'content-type': 'application/json',
              'x-user-id': userId,
            }),
            body: jsonEncode(state.toJson()),
          )
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[resume-state][push-error] $e');
      return false;
    }
  }
}
