// ------------------------------------------------------------
// Ziel (Laien): Lokale NDJSON-Logs schreiben (session/trials), um Verhalten nachzuvollziehen.
// Strategie: Append-only Speicher (Datei auf IO, localStorage im Web), keine Abhängigkeit zur Hauptlogik.
// Schritte: init (Datei anlegen), startSession/endSession, log(type, data).
// Tücken: I/O-Fehler werden geschluckt; Pfad bei Plattformwechsel prüfen.
// ------------------------------------------------------------
import 'dart:convert';
import 'dart:math';

import 'data/log_uploader.dart';
import 'logic/log_storage.dart';

/// Append-only NDJSON logger for local analytics.
class EventLogger {
  static final EventLogger _instance = EventLogger._internal();
  factory EventLogger() => _instance;
  EventLogger._internal();
  static const int _maxLogBatchLines = 150;
  static const int _maxAudioMatchBatchLines = 80;
  static const Duration _retryDelay = Duration(seconds: 3);

  bool _ready = false;
  LogStorage? _storage;
  String sessionId = '';
  String userId = '';
  String workerHost = '';
  String apiPrefix = '';
  String? startKey;
  String? lang;
  String? nativeLang;
  String? storyId;
  String? mode;
  LogUploader? _uploader;
  LogUploader? _audioMatchUploader;
  final List<String> _pendingUpload =
      []; // Zeilen, die noch hochgeladen werden.
  final List<String> _pendingAudioMatchUpload = [];
  bool _uploading = false;
  bool _uploadScheduled = false;
  bool _uploadingAudioMatches = false;
  bool _uploadScheduledAudioMatches = false;

  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    _storage = LogStorage();
    await _storage!.init();
    _ready = true;
  }

  void configureRemote({
    required String userId,
    required String workerHost,
    required String apiPrefix,
  }) {
    this.userId = userId;
    this.workerHost = workerHost;
    this.apiPrefix = apiPrefix;
    _uploader = LogUploader(workerHost: workerHost, apiPrefix: apiPrefix);
    _audioMatchUploader = LogUploader(
      workerHost: workerHost,
      apiPrefix: apiPrefix,
      endpointPath: '/audio-target-matches',
    );
    _scheduleUpload();
    _scheduleAudioMatchUpload();
  }

  void setSessionContext({
    String? startKey,
    String? lang,
    String? nativeLang,
    String? storyId,
    String? mode,
  }) {
    this.startKey = startKey ?? this.startKey;
    this.lang = lang ?? this.lang;
    this.nativeLang = nativeLang ?? this.nativeLang;
    this.storyId = storyId ?? this.storyId;
    this.mode = mode ?? this.mode;
  }

  String _newSessionId() {
    final rnd = Random();
    // On web, bitwise shifts are 32-bit; (1 << 32) becomes 0 → RangeError.
    return 's${DateTime.now().microsecondsSinceEpoch}_${rnd.nextInt(0x7fffffff)}';
  }

  Future<void> startSession({required String lang}) async {
    if (!_ready) return;
    // Neue Session-ID fuer eine zusammenhaengende Trainingsrunde.
    sessionId = _newSessionId();
    setSessionContext(lang: lang);
    await log('session_start', {'lang': lang});
  }

  Future<void> endSession() async {
    await log('session_end', {});
  }

  /// Waits until pending remote uploads are drained or timeout is reached.
  Future<void> flushPendingUploads({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_uploader == null || userId.isEmpty) return;
    final deadline = DateTime.now().add(timeout);
    while (true) {
      _scheduleUpload();
      _scheduleAudioMatchUpload();
      final idle = _pendingUpload.isEmpty &&
          !_uploading &&
          !_uploadScheduled &&
          _pendingAudioMatchUpload.isEmpty &&
          !_uploadingAudioMatches &&
          !_uploadScheduledAudioMatches;
      if (idle) return;
      if (DateTime.now().isAfter(deadline)) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<void> endSessionAndFlush({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await endSession();
    await flushPendingUploads(timeout: timeout);
  }

  Future<void> log(String type, Map<String, dynamic> data) async {
    if (!_ready || _storage == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    // Eine Zeile pro Event (NDJSON), damit sie leicht lesbar und append-only ist.
    final payload = {
      'ts': now,
      'type': type,
      'session': sessionId,
      if (userId.isNotEmpty) 'user': userId,
      if (startKey != null) 'start_key': startKey,
      if (lang != null) 'lang': lang,
      if (nativeLang != null) 'native': nativeLang,
      if (storyId != null) 'story_id': storyId,
      if (mode != null) 'mode': mode,
      ...data,
    };
    final line = jsonEncode(payload);
    try {
      await _storage!.appendLine(line);
    } catch (_) {
      // swallow logging errors
    }
    // Always queue for remote upload, even if local storage failed (e.g. web storage blocked).
    _pendingUpload.add(line);
    _scheduleUpload();
    if (type == 'audio_target_match') {
      _pendingAudioMatchUpload.add(line);
      _scheduleAudioMatchUpload();
    }
  }

  void _scheduleUpload({Duration delay = Duration.zero}) {
    if (_uploadScheduled) return;
    // Upload nur wenn Remote-Konfig vorhanden ist.
    if (_uploader == null || userId.isEmpty) return;
    _uploadScheduled = true;
    if (delay <= Duration.zero) {
      Future.microtask(_flushUploads);
      return;
    }
    Future.delayed(delay, _flushUploads);
  }

  void _scheduleAudioMatchUpload({Duration delay = Duration.zero}) {
    if (_uploadScheduledAudioMatches) return;
    if (_audioMatchUploader == null || userId.isEmpty) return;
    if (_pendingAudioMatchUpload.isEmpty) return;
    _uploadScheduledAudioMatches = true;
    if (delay <= Duration.zero) {
      Future.microtask(_flushAudioMatchUploads);
      return;
    }
    Future.delayed(delay, _flushAudioMatchUploads);
  }

  Future<void> _flushUploads() async {
    _uploadScheduled = false;
    if (_uploading) return;
    if (_uploader == null || userId.isEmpty) return;
    if (_pendingUpload.isEmpty) return;
    _uploading = true;
    final sid = sessionId.isNotEmpty ? sessionId : _newSessionId();
    if (sessionId.isEmpty) {
      sessionId = sid;
    }
    // Schicke Logs im Batch; bei Erfolg entfernen.
    final batch =
        _pendingUpload.take(_maxLogBatchLines).toList(growable: false);
    final ok =
        await _uploader!.upload(userId: userId, lines: batch, sessionId: sid);
    if (ok) {
      _pendingUpload.removeRange(0, batch.length);
    }
    _uploading = false;
    if (_pendingUpload.isNotEmpty) {
      _scheduleUpload(delay: ok ? Duration.zero : _retryDelay);
    }
  }

  Future<void> _flushAudioMatchUploads() async {
    _uploadScheduledAudioMatches = false;
    if (_uploadingAudioMatches) return;
    if (_audioMatchUploader == null || userId.isEmpty) return;
    if (_pendingAudioMatchUpload.isEmpty) return;
    _uploadingAudioMatches = true;
    final sid = sessionId.isNotEmpty ? sessionId : _newSessionId();
    if (sessionId.isEmpty) {
      sessionId = sid;
    }
    final batch = _pendingAudioMatchUpload
        .take(_maxAudioMatchBatchLines)
        .toList(growable: false);
    final ok = await _audioMatchUploader!
        .upload(userId: userId, lines: batch, sessionId: sid);
    if (ok) {
      _pendingAudioMatchUpload.removeRange(0, batch.length);
    }
    _uploadingAudioMatches = false;
    if (_pendingAudioMatchUpload.isNotEmpty) {
      _scheduleAudioMatchUpload(delay: ok ? Duration.zero : _retryDelay);
    }
  }
}
