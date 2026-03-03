import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../flavor_config.dart';
import '../data/supervisor_dashboard_service.dart';
import 'voice_feedback_web_player_stub.dart'
    if (dart.library.html) 'voice_feedback_web_player_web.dart' as voice_web;

class SupervisorResumePanel extends StatefulWidget {
  const SupervisorResumePanel({
    super.key,
    required this.userId,
    required this.workerHost,
    required this.apiPrefix,
    this.refreshInterval = const Duration(seconds: 15),
    this.onVisibilityChanged,
    this.onSelectedEmojiChanged,
    this.onSelectedFeedbackIdsChanged,
  });

  final String? userId;
  final String workerHost;
  final String apiPrefix;
  final Duration refreshInterval;
  final ValueChanged<bool>? onVisibilityChanged;
  final ValueChanged<String?>? onSelectedEmojiChanged;
  final ValueChanged<List<String>>? onSelectedFeedbackIdsChanged;

  @override
  State<SupervisorResumePanel> createState() => _SupervisorResumePanelState();
}

class _SupervisorResumePanelState extends State<SupervisorResumePanel>
    with TickerProviderStateMixin {
  static const String _diagBuildTag = '2026-03-01T01:05Z-r3';
  static const String _voicePlayAsset = 'assets/icons/Play.webp';
  static final RegExp _blockedBannerText =
      RegExp(r'(?=.*\bdownload\b)(?=.*\bandroid\b)', caseSensitive: false);
  static final RegExp _emailPattern =
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$', caseSensitive: false);
  Timer? _refreshTimer;
  bool _loading = false;
  bool _loadFailed = false;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _pendingItems = const [];
  String? _lastKnownSupervisorEmail;
  late final AnimationController _wiggleController;
  late final AnimationController _voicePulseController;
  late final AudioPlayer _voicePlayer;
  bool _lastReportedVisible = false;
  String? _lastReportedEmojiId;
  String _lastReportedFeedbackIdsKey = '';
  bool _voiceLoading = false;
  bool _voicePlaying = false;
  Uri? _voiceFallbackOpenUri;
  String? _voiceFallbackFeedbackId;
  final Set<String> _playedVoiceFeedbackIds = <String>{};
  final Set<String> _autoPlayAttemptedVoiceFeedbackIds = <String>{};

  @override
  void initState() {
    super.initState();
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _voicePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _voicePlayer = AudioPlayer();
    _voicePlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _voicePlaying = false;
      });
    });
    _load();
    if (widget.refreshInterval > Duration.zero) {
      _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _load());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wiggleController.dispose();
    _voicePulseController.dispose();
    voice_web.stopVoiceFeedbackWeb();
    _voicePlayer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SupervisorResumePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.workerHost != widget.workerHost ||
        oldWidget.apiPrefix != widget.apiPrefix) {
      _load();
    }
  }

  void _reportVisible(bool visible) {
    if (_lastReportedVisible == visible) return;
    _lastReportedVisible = visible;
    final callback = widget.onVisibilityChanged;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(visible);
    });
  }

  void _reportSelectedEmoji(String? emojiId) {
    final normalized =
        (emojiId != null && emojiId.trim().isNotEmpty) ? emojiId.trim() : null;
    if (_lastReportedEmojiId == normalized) return;
    _lastReportedEmojiId = normalized;
    final callback = widget.onSelectedEmojiChanged;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(normalized);
    });
  }

  void _reportSelectedFeedbackIds(List<String> ids) {
    final normalized = ids
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final key = normalized.join('|');
    if (_lastReportedFeedbackIdsKey == key) return;
    _lastReportedFeedbackIdsKey = key;
    final callback = widget.onSelectedFeedbackIdsChanged;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(normalized);
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    final uid = widget.userId?.trim() ?? '';
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = false;
        _data = null;
        _pendingItems = const [];
      });
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
      });
    } else {
      _loading = true;
    }
    try {
      final service = SupervisorDashboardService(
        workerHost: widget.workerHost,
        apiPrefix: widget.apiPrefix,
      );
      final results = await Future.wait<dynamic>([
        service.fetchDashboardInfo(userId: uid),
        service.fetchEmojiQueue(userId: uid, status: 'pending', limit: 50),
      ]);
      final payload = results[0] as Map<String, dynamic>?;
      final dashboardOk = payload != null;
      final pendingRaw = (results[1] as List<Map<String, dynamic>>);
      final pending = pendingRaw
          .where((item) => !_isAppGeneratedEmoji(item))
          .toList(growable: false);
      final sample = pending.take(3).map((item) {
        final type = (item['type'] ?? 'emoji').toString().trim();
        final emoji = (item['emoji'] ?? '').toString().trim();
        final source = (item['source'] ?? '').toString().trim();
        final reason = (item['reason'] ?? '').toString().trim();
        final id = (item['id'] ?? '').toString().trim();
        return '[$type emoji=$emoji src=$source reason=$reason id=${id.isEmpty ? '-' : id}]';
      }).join(', ');
      debugPrint(
        '[supervisor-resume] flavor=${activeFlavor.id} uid=$uid host=${widget.workerHost} pendingRaw=${pendingRaw.length} pendingFiltered=${pending.length} sample=$sample',
      );
      if (!mounted) return;
      final supervisor = payload?['supervisor'];
      final supervisorMap = supervisor is Map
          ? Map<String, dynamic>.from(supervisor)
          : const <String, dynamic>{};
      final email = _resolveSupervisorEmail(supervisorMap);
      setState(() {
        _loading = false;
        _loadFailed = !dashboardOk;
        _data = payload;
        _pendingItems = pending;
        if (email != null && email.isNotEmpty) {
          _lastKnownSupervisorEmail = email;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      debugPrint(
        '[supervisor-resume] load-error uid=$uid host=${widget.workerHost}: $e',
      );
    }
  }

  Future<void> _playVoiceFeedback(_SelectedFeedback feedback) async {
    final uid = widget.userId?.trim() ?? '';
    final feedbackId = (feedback.id ?? '').trim();
    final mimeType = _normalizeAudioMimeType(
      (feedback.item?['mimeType'] ?? '').toString(),
    );
    final uri = _buildFeedbackAudioUri(userId: uid, feedbackId: feedbackId);
    debugPrint(
      '[supervisor-resume] voice-play-request uid=$uid id=$feedbackId loading=$_voiceLoading type=${feedback.type}',
    );
    debugPrint(
      '[supervisor-resume] voice-build tag=$_diagBuildTag clientHost=${Uri.base.host} href=${Uri.base}',
    );
    if (uid.isEmpty || feedbackId.isEmpty || _voiceLoading) return;
    setState(() {
      _voiceLoading = true;
      _voicePlaying = false;
      _voiceFallbackOpenUri = null;
      _voiceFallbackFeedbackId = null;
    });
    try {
      if (kIsWeb) {
        debugPrint(
          '[supervisor-resume] voice-play-url uid=$uid id=$feedbackId uri=$uri',
        );
        debugPrint(
          '[supervisor-resume] voice-web-helper-enter id=$feedbackId uid=$uid',
        );
        final played = await voice_web.playVoiceFeedbackWeb(
          url: uri.toString(),
          mimeType: mimeType.isNotEmpty ? mimeType : null,
          onLog: debugPrint,
        );
        debugPrint(
          '[supervisor-resume] voice-web-helper-result id=$feedbackId uid=$uid played=$played',
        );
        if (!mounted) return;
        if (played) {
          setState(() {
            _voicePlaying = true;
            _playedVoiceFeedbackIds.add(feedbackId);
          });
          _syncVoicePulse(feedbackId: feedbackId, showVoice: true);
          return;
        }
        setState(() {
          _voicePlaying = false;
          _voiceFallbackOpenUri = uri;
          _voiceFallbackFeedbackId = feedbackId;
        });
        debugPrint(
          '[supervisor-resume] voice-open-fallback-ready id=$feedbackId uri=$uri',
        );
        return;
      }
      final service = SupervisorDashboardService(
        workerHost: widget.workerHost,
        apiPrefix: widget.apiPrefix,
      );
      await _voicePlayer.stop();
      await _voicePlayer.setVolume(1.0);
      final bytes = await service.fetchFeedbackAudio(
        userId: uid,
        feedbackId: feedbackId,
      );
      if (bytes == null || bytes.isEmpty) {
        throw Exception('empty voice payload');
      }
      // Native path: avoid forcing MIME from queue metadata. Let the platform
      // decoder inspect bytes directly (safer across Android codec variants).
      bool played = false;
      Object? bytesErrorWithMime;
      Object? bytesErrorWithoutMime;
      try {
        if (mimeType.isNotEmpty) {
          await _voicePlayer.play(BytesSource(bytes, mimeType: mimeType));
        } else {
          await _voicePlayer.play(BytesSource(bytes));
        }
        played = await _waitForVoiceStart();
      } catch (e) {
        bytesErrorWithMime = e;
      }
      if (!played) {
        try {
          await _voicePlayer.stop();
          await _voicePlayer.play(BytesSource(bytes));
          played = await _waitForVoiceStart();
        } catch (e) {
          bytesErrorWithoutMime = e;
        }
      }
      if (!played) {
        debugPrint(
          '[supervisor-resume] voice-native-bytes-fallback-url id=$feedbackId uid=$uid errMime=${bytesErrorWithMime ?? '-'} errRaw=${bytesErrorWithoutMime ?? '-'}',
        );
        await _voicePlayer.stop();
        await _voicePlayer.play(UrlSource(uri.toString()));
        played = await _waitForVoiceStart(timeout: const Duration(seconds: 6));
      }
      if (!played) {
        throw Exception('native voice playback did not start');
      }
      if (!mounted) return;
      setState(() {
        _voicePlaying = true;
        _playedVoiceFeedbackIds.add(feedbackId);
      });
      _syncVoicePulse(feedbackId: feedbackId, showVoice: true);
    } catch (e) {
      debugPrint(
        '[supervisor-resume] voice-playback-error id=$feedbackId uid=$uid: $e',
      );
      if (!mounted) return;
      setState(() {
        _voicePlaying = false;
        _voiceFallbackOpenUri = uri;
        _voiceFallbackFeedbackId = feedbackId;
      });
    } finally {
      if (mounted) {
        setState(() {
          _voiceLoading = false;
        });
      }
    }
  }

  Future<bool> _waitForVoiceStart({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final pos = await _voicePlayer.getCurrentPosition();
      if (_voicePlayer.state == PlayerState.playing) return true;
      if (pos != null && pos > Duration.zero) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    final pos = await _voicePlayer.getCurrentPosition();
    return _voicePlayer.state == PlayerState.playing ||
        (pos != null && pos > Duration.zero);
  }

  void _syncVoicePulse({
    required String? feedbackId,
    required bool showVoice,
  }) {
    final id = (feedbackId ?? '').trim();
    final shouldPulse =
        showVoice && id.isNotEmpty && !_playedVoiceFeedbackIds.contains(id);
    if (shouldPulse) {
      if (!_voicePulseController.isAnimating) {
        _voicePulseController.repeat(reverse: true);
      }
      return;
    }
    if (_voicePulseController.isAnimating) {
      _voicePulseController.stop();
      _voicePulseController.value = 0;
    }
  }

  void _maybeAutoPlayVoiceFeedback(
    _SelectedFeedback feedback, {
    required bool showVoice,
  }) {
    if (kIsWeb) return;
    if (!showVoice || _voiceLoading) return;
    final feedbackId = (feedback.id ?? '').trim();
    if (feedbackId.isEmpty) return;
    if (_autoPlayAttemptedVoiceFeedbackIds.contains(feedbackId)) return;
    _autoPlayAttemptedVoiceFeedbackIds.add(feedbackId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      debugPrint('[supervisor-resume] voice-autoplay-attempt id=$feedbackId');
      _playVoiceFeedback(feedback);
    });
  }

  Future<void> _openVoiceFallback() async {
    final uri = _voiceFallbackOpenUri;
    if (uri == null) return;
    final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
    debugPrint(
      '[supervisor-resume] voice-open-fallback-tap uri=$uri opened=$opened',
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.userId?.trim() ?? '';
    final theme = Theme.of(context);
    if (uid.isEmpty) {
      _reportVisible(false);
      _reportSelectedEmoji(null);
      _reportSelectedFeedbackIds(const []);
      return const SizedBox.shrink();
    }

    final supervisor = _data?['supervisor'] is Map
        ? Map<String, dynamic>.from(_data!['supervisor'])
        : const <String, dynamic>{};
    final queue = _data?['emojiQueue'] is Map
        ? Map<String, dynamic>.from(_data!['emojiQueue'])
        : const <String, dynamic>{};
    final preview = queue['itemsPreview'] is List
        ? List<Map<String, dynamic>>.from(
            (queue['itemsPreview'] as List).whereType<Map>(),
          )
        : const <Map<String, dynamic>>[];
    final selectedVoice = _resolveQueuedFeedbackByType(
      _pendingItems,
      fallbackItems: preview,
      type: 'voice',
    );
    final selectedEmoji = _resolveQueuedFeedbackByType(
      _pendingItems,
      fallbackItems: preview,
      type: 'emoji',
    );
    final queuedEmoji = selectedEmoji.emoji;
    final showEmoji = queuedEmoji.isNotEmpty;
    final selectedVoiceId = selectedVoice.id;
    final showVoice = selectedVoiceId != null;
    final selectedItemsForAck = <Map<String, dynamic>>[
      if (selectedVoice.item != null) selectedVoice.item!,
      if (selectedEmoji.item != null) selectedEmoji.item!,
    ];
    final selectedFeedbackIds =
        _collectSelectedFeedbackIds(selectedItemsForAck);
    final legacySelectedId =
        selectedFeedbackIds.isNotEmpty ? selectedFeedbackIds.first : null;
    debugPrint(
      '[supervisor-resume] selected voice=${selectedVoice.id ?? '-'} emoji=${selectedEmoji.id ?? '-'} ids=${selectedFeedbackIds.join(",")}',
    );
    final showVoiceFallbackOpen = showVoice &&
        _voiceFallbackOpenUri != null &&
        _voiceFallbackFeedbackId == selectedVoiceId;
    _syncVoicePulse(feedbackId: selectedVoiceId, showVoice: showVoice);
    _maybeAutoPlayVoiceFeedback(selectedVoice, showVoice: showVoice);
    final showFeedback = showEmoji || showVoice;
    _reportSelectedEmoji(showFeedback ? legacySelectedId : null);
    _reportSelectedFeedbackIds(showFeedback ? selectedFeedbackIds : const []);
    final selectedMetadataItem = selectedVoice.item ?? selectedEmoji.item;
    final supervisorEmail =
        _resolveSupervisorEmail(supervisor, queuedItem: selectedMetadataItem) ??
            _lastKnownSupervisorEmail;
    final supervisorName = _resolveSupervisorName(
      supervisor,
      queuedItem: selectedMetadataItem,
      fallbackEmail: supervisorEmail,
    );
    debugPrint(
      '[supervisor-resume] name-resolve result="$supervisorName" email="${supervisorEmail ?? '-'}" itemSource="${(selectedMetadataItem?['source'] ?? '').toString()}" supervisorSource="${(supervisor['source'] ?? '').toString()}" displayName="${(supervisor['displayName'] ?? '').toString()}"',
    );
    final showStatusLoading = _loading && _data == null && !_loadFailed;
    final showStatusError = _loadFailed;
    final showStatus = showStatusLoading || showStatusError;
    final showName = supervisorName.isNotEmpty && (showFeedback || showStatus);
    if (!showName && !showFeedback && !showStatus) {
      _reportVisible(false);
      _reportSelectedEmoji(null);
      _reportSelectedFeedbackIds(const []);
      return const SizedBox.shrink();
    }
    _reportVisible(true);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        if (showVoice) {
          debugPrint(
            '[supervisor-resume] voice-panel-pointer-down id=${selectedVoice.id ?? '-'}',
          );
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: (showVoice && !_voiceLoading)
            ? () {
                debugPrint(
                  '[supervisor-resume] voice-panel-tap-play id=${selectedVoice.id ?? '-'}',
                );
                _playVoiceFeedback(selectedVoice);
              }
            : null,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showStatus)
                _StatusLine(
                  loading: showStatusLoading,
                  hasError: showStatusError,
                ),
              if (showStatus && (showName || showFeedback))
                const SizedBox(height: 6),
              if (showName)
                Text(
                  supervisorName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (showName && showFeedback) const SizedBox(height: 6),
              if (showEmoji || showVoice)
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showEmoji)
                        AnimatedBuilder(
                          animation: _wiggleController,
                          child: Text(
                            queuedEmoji,
                            style: const TextStyle(
                              fontSize: 56,
                              height: 1,
                            ),
                          ),
                          builder: (context, child) {
                            final t = _wiggleController.value * 2 * math.pi;
                            final angle = math.sin(t * 1.7) * 0.13;
                            final y = math.sin(t * 3.4) * 1.8;
                            return Transform.translate(
                              offset: Offset(0, y),
                              child:
                                  Transform.rotate(angle: angle, child: child),
                            );
                          },
                        ),
                      if (showEmoji && showVoice) const SizedBox(width: 10),
                      if (showVoice)
                        AnimatedBuilder(
                          animation: _voicePulseController,
                          builder: (context, child) {
                            final pulse = 1.0 +
                                (0.07 *
                                    Curves.easeInOut.transform(
                                        _voicePulseController.value));
                            return Transform.scale(scale: pulse, child: child);
                          },
                          child: Semantics(
                            button: true,
                            label: _voiceLoading
                                ? 'Loading voice feedback'
                                : (_voicePlaying
                                    ? 'Replay voice feedback'
                                    : 'Play voice feedback'),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _voiceLoading
                                    ? null
                                    : () {
                                        debugPrint(
                                          '[supervisor-resume] voice-play-tap id=${selectedVoice.id ?? '-'} type=${selectedVoice.type}',
                                        );
                                        _playVoiceFeedback(selectedVoice);
                                      },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          Colors.black.withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.08),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: _voiceLoading
                                        ? const CircularProgressIndicator(
                                            strokeWidth: 2)
                                        : Image.asset(
                                            _voicePlayAsset,
                                            fit: BoxFit.contain,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (showVoice) ...[
                if (showVoiceFallbackOpen) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: _openVoiceFallback,
                      child: const Text('Open audio'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _resolveSupervisorName(
    Map<String, dynamic> supervisor, {
    Map<String, dynamic>? queuedItem,
    String? fallbackEmail,
  }) {
    // Canonical contract key for display name.
    final canonical =
        _normalizeSupervisorName((supervisor['displayName'] ?? '').toString());
    if (canonical.isNotEmpty) return canonical;
    if (queuedItem != null) {
      final fromItem = _resolveSupervisorNameFromItem(queuedItem);
      if (fromItem.isNotEmpty) return fromItem;
    }
    final sourceName =
        _normalizeSupervisorSourceName((supervisor['source'] ?? '').toString());
    if (sourceName.isNotEmpty) return sourceName;
    // Legacy key fallback (supports old payloads).
    for (final key in const [
      'display_name',
      'supervisor_display_name',
      'supervisorDisplayName',
      'registrationName',
      'registration_name',
      'supervisorName',
      'supervisor_name',
      'registeredName',
      'name',
    ]) {
      final value =
          _normalizeSupervisorName((supervisor[key] ?? '').toString());
      if (value.isNotEmpty) return value;
    }
    return _normalizeSupervisorEmail(fallbackEmail ?? '');
  }

  _SelectedFeedback _resolveQueuedFeedbackByType(
    List<Map<String, dynamic>> items, {
    List<Map<String, dynamic>> fallbackItems = const [],
    required String type,
  }) {
    final normalizedType = type.trim().toLowerCase();
    final primary = _pickBestFeedbackItem(
      items,
      type: normalizedType,
    );
    if (primary != null) {
      final itemType =
          (primary['type'] ?? 'emoji').toString().trim().toLowerCase();
      final emoji = (primary['emoji'] ?? '').toString().trim();
      final id = (primary['id'] ?? '').toString().trim();
      if (itemType == 'voice' || emoji.isNotEmpty) {
        return _SelectedFeedback(
          type: itemType == 'voice' ? 'voice' : 'emoji',
          emoji: itemType == 'voice' ? '' : emoji,
          id: id.isEmpty ? null : id,
          item: primary,
        );
      }
    }
    final fallback = _pickBestFeedbackItem(
      fallbackItems,
      type: normalizedType,
    );
    if (fallback != null) {
      final itemType =
          (fallback['type'] ?? 'emoji').toString().trim().toLowerCase();
      final emoji = (fallback['emoji'] ?? '').toString().trim();
      final id = (fallback['id'] ?? '').toString().trim();
      if (itemType == 'voice' || emoji.isNotEmpty) {
        return _SelectedFeedback(
          type: itemType == 'voice' ? 'voice' : 'emoji',
          emoji: itemType == 'voice' ? '' : emoji,
          id: id.isEmpty ? null : id,
          item: fallback,
        );
      }
    }
    return const _SelectedFeedback(
        type: 'emoji', emoji: '', id: null, item: null);
  }

  String _resolveSupervisorNameFromItem(Map<String, dynamic> item) {
    final meta = item['meta'];
    final metaMap = meta is Map ? Map<String, dynamic>.from(meta) : null;
    final canonical = _normalizeSupervisorName(
      (item['displayName'] ?? metaMap?['displayName'] ?? '').toString(),
    );
    if (canonical.isNotEmpty) return canonical;
    for (final key in const [
      'supervisor_display_name',
      'supervisorDisplayName',
      'display_name',
      'registrationName',
      'registration_name',
      'supervisor_name',
      'supervisorName',
      'registeredName',
      'name',
    ]) {
      final topLevel = _normalizeSupervisorName((item[key] ?? '').toString());
      if (topLevel.isNotEmpty) {
        return topLevel;
      }
      final nested = _normalizeSupervisorName((metaMap?[key] ?? '').toString());
      if (nested.isNotEmpty) {
        return nested;
      }
    }
    final sourceName = _normalizeSupervisorSourceName(
      (item['source'] ?? metaMap?['source'] ?? '').toString(),
    );
    if (sourceName.isNotEmpty) return sourceName;
    return '';
  }

  String? _resolveSupervisorEmail(
    Map<String, dynamic> supervisor, {
    Map<String, dynamic>? queuedItem,
  }) {
    for (final key in const ['supervisorEmail', 'email', 'supervisor_email']) {
      final value =
          _normalizeSupervisorEmail((supervisor[key] ?? '').toString());
      if (value.isNotEmpty) return value;
    }
    if (queuedItem != null) {
      final meta = queuedItem['meta'];
      final metaMap = meta is Map ? Map<String, dynamic>.from(meta) : null;
      for (final key in const [
        'supervisorEmail',
        'email',
        'supervisor_email',
      ]) {
        final topLevel =
            _normalizeSupervisorEmail((queuedItem[key] ?? '').toString());
        if (topLevel.isNotEmpty) return topLevel;
        final nested =
            _normalizeSupervisorEmail((metaMap?[key] ?? '').toString());
        if (nested.isNotEmpty) return nested;
      }
    }
    return null;
  }

  String _normalizeSupervisorName(String raw) {
    var value = raw.trim();
    if (value.isEmpty || value == '-') return '';
    if (_blockedBannerText.hasMatch(value)) return '';
    if (_emailPattern.hasMatch(value)) return '';
    value = value.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    value = value
        .replaceFirst(
            RegExp(r'^\s*supervisor\s*name\s*:\s*', caseSensitive: false), '')
        .trim();
    if (value.isEmpty || value == '-') return '';
    if (_blockedBannerText.hasMatch(value)) return '';
    if (_emailPattern.hasMatch(value)) return '';
    return value;
  }

  Uri _buildFeedbackAudioUri({
    required String userId,
    required String feedbackId,
  }) {
    return Uri.https(
      widget.workerHost,
      '${widget.apiPrefix}/feedback-audio',
      {
        'feedbackId': feedbackId,
        'uid': userId,
        'app_flavor': activeFlavor.id,
      },
    );
  }

  String _normalizeAudioMimeType(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    switch (value) {
      case 'audio/m4a':
      case 'audio/x-m4a':
      case 'audio/x-mp4':
        return 'audio/mp4';
      case 'audio/mp3':
      case 'audio/x-mp3':
        return 'audio/mpeg';
      case 'audio/x-wav':
        return 'audio/wav';
      default:
        return value.startsWith('audio/') ? value : '';
    }
  }

  String _normalizeSupervisorEmail(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (!_emailPattern.hasMatch(value)) return '';
    return value;
  }

  String _normalizeSupervisorSourceName(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    final lower = value.toLowerCase();
    if (lower == 'app' || lower == 'system') return '';
    value = value.replaceAll(RegExp(r'[_\-\.]+'), ' ').trim();
    value = value.replaceFirst(
      RegExp(r'\s+(ipad|iphone|android|phone|tablet)\s*$',
          caseSensitive: false),
      '',
    );
    value = value.replaceFirst(RegExp(r'\s+\d+$'), '').trim();
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty || value == '-') return '';
    if (_blockedBannerText.hasMatch(value)) return '';
    return value;
  }

  DateTime _itemTs(Map<String, dynamic> item) {
    final updated = DateTime.tryParse((item['updatedAt'] ?? '').toString());
    if (updated != null) return updated;
    final created = DateTime.tryParse((item['createdAt'] ?? '').toString());
    if (created != null) return created;
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  bool _isAppGeneratedEmoji(Map<String, dynamic> item) {
    final type = (item['type'] ?? 'emoji').toString().trim().toLowerCase();
    if (type == 'voice') return false;
    final source = (item['source'] ?? '').toString().trim().toLowerCase();
    if (source != 'app') return false;
    final reason = (item['reason'] ?? '').toString().trim().toLowerCase();
    if (reason == 'player_win' || reason == 'rival_win') return true;
    final emoji = (item['emoji'] ?? '').toString().trim();
    if (emoji == '🤖' || emoji == '🏆') return true;
    return false;
  }

  Map<String, dynamic>? _pickBestFeedbackItem(
    List<Map<String, dynamic>> items, {
    required String type,
  }) {
    if (items.isEmpty) return null;
    final normalizedType = type.trim().toLowerCase();
    final candidates = items.where((item) {
      final itemType =
          (item['type'] ?? 'emoji').toString().trim().toLowerCase();
      if (normalizedType == 'voice' && itemType != 'voice') return false;
      if (normalizedType == 'emoji' && itemType == 'voice') return false;
      if (itemType == 'voice') {
        final id = (item['id'] ?? '').toString().trim();
        return id.isNotEmpty;
      }
      return (item['emoji'] ?? '').toString().trim().isNotEmpty;
    }).toList(growable: false);
    if (candidates.isEmpty) return null;
    final sorted = <Map<String, dynamic>>[...candidates]..sort((a, b) {
        final rankDiff =
            _feedbackPriorityRank(a).compareTo(_feedbackPriorityRank(b));
        if (rankDiff != 0) return rankDiff;
        return _itemTs(b).compareTo(_itemTs(a));
      });
    return sorted.first;
  }

  List<String> _collectSelectedFeedbackIds(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const <String>[];
    final sorted = <Map<String, dynamic>>[...items]..sort((a, b) {
        final rankDiff =
            _feedbackPriorityRank(a).compareTo(_feedbackPriorityRank(b));
        if (rankDiff != 0) return rankDiff;
        return _itemTs(b).compareTo(_itemTs(a));
      });
    final ids = <String>[];
    for (final item in sorted) {
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty || ids.contains(id)) continue;
      ids.add(id);
    }
    return ids;
  }

  int _feedbackPriorityRank(Map<String, dynamic> item) {
    final type = (item['type'] ?? 'emoji').toString().trim().toLowerCase();
    if (type == 'voice') return 0;
    final source = (item['source'] ?? '').toString().trim().toLowerCase();
    final reason = (item['reason'] ?? '').toString().trim().toLowerCase();
    final emoji = (item['emoji'] ?? '').toString().trim();
    final appGenerated = _isAppGeneratedEmoji(item);
    final isGameReason = reason == 'player_win' || reason == 'rival_win';
    final isWinLossEmoji = emoji == '🤖' || emoji == '🏆';
    if (source != 'app' && !isGameReason && !isWinLossEmoji) return 0;
    if (!isGameReason && !isWinLossEmoji) return 1;
    if (!isGameReason) return 2;
    if (!appGenerated) return 3;
    return 4;
  }
}

class _SelectedFeedback {
  const _SelectedFeedback({
    required this.type,
    required this.emoji,
    required this.id,
    required this.item,
  });

  final String type;
  final String emoji;
  final String? id;
  final Map<String, dynamic>? item;
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.loading,
    required this.hasError,
  });

  final bool loading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final icon = hasError ? Icons.cloud_off : Icons.sync;
    final text = hasError ? 'Feedback unavailable' : 'Loading feedback...';
    final color = hasError ? const Color(0xFF8B5E00) : Colors.black54;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        if (loading && !hasError) ...[
          const SizedBox(width: 6),
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          ),
        ],
      ],
    );
  }
}
