import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../flavor_config.dart';
import '../data/supervisor_dashboard_service.dart';

class SupervisorResumePanel extends StatefulWidget {
  const SupervisorResumePanel({
    super.key,
    required this.userId,
    required this.workerHost,
    required this.apiPrefix,
    this.refreshInterval = const Duration(seconds: 15),
    this.onVisibilityChanged,
    this.onSelectedEmojiChanged,
  });

  final String? userId;
  final String workerHost;
  final String apiPrefix;
  final Duration refreshInterval;
  final ValueChanged<bool>? onVisibilityChanged;
  final ValueChanged<String?>? onSelectedEmojiChanged;

  @override
  State<SupervisorResumePanel> createState() => _SupervisorResumePanelState();
}

class _SupervisorResumePanelState extends State<SupervisorResumePanel>
    with SingleTickerProviderStateMixin {
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
  late final AudioPlayer _voicePlayer;
  bool _lastReportedVisible = false;
  String? _lastReportedEmojiId;
  bool _voiceLoading = false;
  bool _voicePlaying = false;
  String? _voiceError;
  String? _voiceStateFeedbackId;

  @override
  void initState() {
    super.initState();
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
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
    if (uid.isEmpty || feedbackId.isEmpty || _voiceLoading) return;
    final service = SupervisorDashboardService(
      workerHost: widget.workerHost,
      apiPrefix: widget.apiPrefix,
    );
    setState(() {
      _voiceLoading = true;
      _voiceStateFeedbackId = feedbackId;
      _voiceError = null;
    });
    try {
      final bytes = await service.fetchFeedbackAudio(
        userId: uid,
        feedbackId: feedbackId,
      );
      if (bytes == null || bytes.isEmpty) {
        throw Exception('empty voice payload');
      }
      await _voicePlayer.stop();
      await _voicePlayer.play(BytesSource(bytes));
      if (!mounted) return;
      setState(() {
        _voicePlaying = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voicePlaying = false;
        _voiceError = 'Audio unavailable. Try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _voiceLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.userId?.trim() ?? '';
    final theme = Theme.of(context);
    if (uid.isEmpty) {
      _reportVisible(false);
      _reportSelectedEmoji(null);
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
    final selectedFeedback = _resolveQueuedFeedback(
      _pendingItems,
      fallbackItems: preview,
    );
    final queuedEmoji = selectedFeedback.emoji;
    final showEmoji = queuedEmoji.isNotEmpty;
    final selectedId = selectedFeedback.id;
    final showVoice = selectedFeedback.type == 'voice' && selectedId != null;
    final showFeedback = showEmoji || showVoice;
    _reportSelectedEmoji(showFeedback ? selectedId : null);
    final hasActiveSupervisor =
        _isTrueish(supervisor['active']) || _isTrueish(supervisor['paired']);
    final supervisorEmail = _resolveSupervisorEmail(supervisor,
            queuedItem: selectedFeedback.item) ??
        _lastKnownSupervisorEmail;
    final supervisorName = _resolveSupervisorName(
      supervisor,
      queuedItem: selectedFeedback.item,
      fallbackEmail: supervisorEmail,
    );
    final showStatusLoading = _loading && _data == null && !_loadFailed;
    final showStatusError = _loadFailed;
    final showStatus = showStatusLoading || showStatusError;
    final showName = supervisorName.isNotEmpty &&
        (hasActiveSupervisor || showFeedback || _loadFailed);
    if (!showName && !showFeedback && !showStatus) {
      _reportVisible(false);
      _reportSelectedEmoji(null);
      return const SizedBox.shrink();
    }
    _reportVisible(true);

    return Container(
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
          if (showEmoji)
            Center(
              child: AnimatedBuilder(
                animation: _wiggleController,
                child: Text(
                  queuedEmoji,
                  style: const TextStyle(
                    fontSize: 64,
                    height: 1,
                  ),
                ),
                builder: (context, child) {
                  final t = _wiggleController.value * 2 * math.pi;
                  final angle = math.sin(t * 1.7) * 0.13;
                  final y = math.sin(t * 3.4) * 1.8;
                  return Transform.translate(
                    offset: Offset(0, y),
                    child: Transform.rotate(angle: angle, child: child),
                  );
                },
              ),
            ),
          if (showVoice) ...[
            Row(
              children: [
                const Icon(Icons.volume_up, size: 20, color: Colors.black87),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Voice feedback message',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: OutlinedButton.icon(
                onPressed: _voiceLoading
                    ? null
                    : () => _playVoiceFeedback(selectedFeedback),
                icon: Icon(
                  _voicePlaying ? Icons.replay : Icons.play_arrow,
                  size: 18,
                ),
                label: Text(_voiceLoading
                    ? 'Loading...'
                    : (_voicePlaying ? 'Replay voice' : 'Play voice')),
              ),
            ),
            if (_voiceError != null &&
                _voiceError!.isNotEmpty &&
                _voiceStateFeedbackId == selectedId) ...[
              const SizedBox(height: 6),
              Text(
                _voiceError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8B5E00),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
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
    if (queuedItem != null) {
      final fromItem = _resolveSupervisorNameFromItem(queuedItem);
      if (fromItem.isNotEmpty) return fromItem;
    }
    return _normalizeSupervisorEmail(fallbackEmail ?? '');
  }

  _SelectedFeedback _resolveQueuedFeedback(
    List<Map<String, dynamic>> items, {
    List<Map<String, dynamic>> fallbackItems = const [],
  }) {
    final primary = _pickBestFeedbackItem(items);
    if (primary != null) {
      final type = (primary['type'] ?? 'emoji').toString().trim().toLowerCase();
      final emoji = (primary['emoji'] ?? '').toString().trim();
      final id = (primary['id'] ?? '').toString().trim();
      if (type == 'voice' || emoji.isNotEmpty) {
        return _SelectedFeedback(
          type: type == 'voice' ? 'voice' : 'emoji',
          emoji: type == 'voice' ? '' : emoji,
          id: id.isEmpty ? null : id,
          item: primary,
        );
      }
    }
    final fallback = _pickBestFeedbackItem(fallbackItems);
    if (fallback != null) {
      final type =
          (fallback['type'] ?? 'emoji').toString().trim().toLowerCase();
      final emoji = (fallback['emoji'] ?? '').toString().trim();
      final id = (fallback['id'] ?? '').toString().trim();
      if (type == 'voice' || emoji.isNotEmpty) {
        return _SelectedFeedback(
          type: type == 'voice' ? 'voice' : 'emoji',
          emoji: type == 'voice' ? '' : emoji,
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

  bool _isTrueish(dynamic raw) {
    if (raw is bool) return raw;
    final value = (raw ?? '').toString().trim().toLowerCase();
    return value == 'true' || value == '1' || value == 'yes';
  }

  String _normalizeSupervisorName(String raw) {
    var value = raw.trim();
    if (value.isEmpty || value == '-') return '';
    if (_blockedBannerText.hasMatch(value)) return '';
    value = value.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    value = value
        .replaceFirst(
            RegExp(r'^\s*supervisor\s*name\s*:\s*', caseSensitive: false), '')
        .trim();
    if (value.isEmpty || value == '-') return '';
    if (_blockedBannerText.hasMatch(value)) return '';
    return value;
  }

  String _normalizeSupervisorEmail(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (!_emailPattern.hasMatch(value)) return '';
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
      List<Map<String, dynamic>> items) {
    if (items.isEmpty) return null;
    final candidates = items.where((item) {
      final type = (item['type'] ?? 'emoji').toString().trim().toLowerCase();
      if (type == 'voice') {
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
