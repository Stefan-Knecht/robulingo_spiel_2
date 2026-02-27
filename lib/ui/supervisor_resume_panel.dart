import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../flavor_config.dart';
import '../data/supervisor_dashboard_service.dart';

class SupervisorResumePanel extends StatefulWidget {
  const SupervisorResumePanel({
    super.key,
    required this.userId,
    required this.workerHost,
    required this.apiPrefix,
    this.refreshInterval = const Duration(seconds: 20),
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
  Timer? _refreshTimer;
  bool _loading = false;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _pendingItems = const [];
  late final AnimationController _wiggleController;
  bool _lastReportedVisible = false;
  String? _lastReportedEmojiId;

  @override
  void initState() {
    super.initState();
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _load();
    if (widget.refreshInterval > Duration.zero) {
      _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _load());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wiggleController.dispose();
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
        _data = null;
      });
      return;
    }
    _loading = true;
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
      final pendingRaw = (results[1] as List<Map<String, dynamic>>);
      final pending = pendingRaw
          .where((item) => !_isAppGeneratedEmoji(item))
          .toList(growable: false);
      final sample = pending.take(3).map((item) {
        final emoji = (item['emoji'] ?? '').toString().trim();
        final source = (item['source'] ?? '').toString().trim();
        final reason = (item['reason'] ?? '').toString().trim();
        final id = (item['id'] ?? '').toString().trim();
        return '[$emoji src=$source reason=$reason id=${id.isEmpty ? '-' : id}]';
      }).join(', ');
      debugPrint(
        '[supervisor-resume] flavor=${activeFlavor.id} uid=$uid host=${widget.workerHost} pendingRaw=${pendingRaw.length} pendingFiltered=${pending.length} sample=$sample',
      );
      if (!mounted) return;
      setState(() {
        _data = payload;
        _pendingItems = pending;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = null;
        _pendingItems = const [];
      });
    } finally {
      _loading = false;
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
    final selectedEmoji = _resolveQueuedEmoji(
      _pendingItems,
      fallbackItems: preview,
    );
    final queuedEmoji = selectedEmoji.emoji;
    final showEmoji = queuedEmoji.isNotEmpty;
    final selectedId = selectedEmoji.id;
    _reportSelectedEmoji(showEmoji ? selectedId : null);
    final hasActiveSupervisor =
        _isTrueish(supervisor['active']) || _isTrueish(supervisor['paired']);
    final supervisorName = _resolveSupervisorName(
      supervisor,
      queuedItem: selectedEmoji.item,
    );
    final showName =
        supervisorName.isNotEmpty && (hasActiveSupervisor || showEmoji);
    if (!showName && !showEmoji) {
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
          if (showName && showEmoji) const SizedBox(height: 6),
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
        ],
      ),
    );
  }

  String _resolveSupervisorName(
    Map<String, dynamic> supervisor, {
    Map<String, dynamic>? queuedItem,
  }) {
    for (final key in const [
      'registrationName',
      'registration_name',
      'display_name',
      'displayName',
      'supervisor_display_name',
      'supervisorDisplayName',
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
    return '';
  }

  _SelectedEmoji _resolveQueuedEmoji(
    List<Map<String, dynamic>> items, {
    List<Map<String, dynamic>> fallbackItems = const [],
  }) {
    final primary = _pickBestEmojiItem(items);
    if (primary != null) {
      final emoji = (primary['emoji'] ?? '').toString().trim();
      final id = (primary['id'] ?? '').toString().trim();
      if (emoji.isNotEmpty) {
        return _SelectedEmoji(
          emoji: emoji,
          id: id.isEmpty ? null : id,
          item: primary,
        );
      }
    }
    final fallback = _pickBestEmojiItem(fallbackItems);
    if (fallback != null) {
      final emoji = (fallback['emoji'] ?? '').toString().trim();
      final id = (fallback['id'] ?? '').toString().trim();
      if (emoji.isNotEmpty) {
        return _SelectedEmoji(
          emoji: emoji,
          id: id.isEmpty ? null : id,
          item: fallback,
        );
      }
    }
    return const _SelectedEmoji(emoji: '', id: null, item: null);
  }

  String _resolveSupervisorNameFromItem(Map<String, dynamic> item) {
    final meta = item['meta'];
    final metaMap = meta is Map ? Map<String, dynamic>.from(meta) : null;
    for (final key in const [
      'registrationName',
      'registration_name',
      'supervisor_display_name',
      'supervisorDisplayName',
      'display_name',
      'displayName',
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

  DateTime _itemTs(Map<String, dynamic> item) {
    final updated = DateTime.tryParse((item['updatedAt'] ?? '').toString());
    if (updated != null) return updated;
    final created = DateTime.tryParse((item['createdAt'] ?? '').toString());
    if (created != null) return created;
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  bool _isAppGeneratedEmoji(Map<String, dynamic> item) {
    final source = (item['source'] ?? '').toString().trim().toLowerCase();
    if (source != 'app') return false;
    final reason = (item['reason'] ?? '').toString().trim().toLowerCase();
    if (reason == 'player_win' || reason == 'rival_win') return true;
    final emoji = (item['emoji'] ?? '').toString().trim();
    if (emoji == '🤖' || emoji == '🏆') return true;
    return false;
  }

  Map<String, dynamic>? _pickBestEmojiItem(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return null;
    final candidates = items
        .where((item) => (item['emoji'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    final sorted = <Map<String, dynamic>>[...candidates]..sort((a, b) {
        final rankDiff = _emojiPriorityRank(a).compareTo(_emojiPriorityRank(b));
        if (rankDiff != 0) return rankDiff;
        return _itemTs(b).compareTo(_itemTs(a));
      });
    return sorted.first;
  }

  int _emojiPriorityRank(Map<String, dynamic> item) {
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

class _SelectedEmoji {
  const _SelectedEmoji({
    required this.emoji,
    required this.id,
    required this.item,
  });

  final String emoji;
  final String? id;
  final Map<String, dynamic>? item;
}
