import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/supervisor_dashboard_service.dart';

class SupervisorResumePanel extends StatefulWidget {
  const SupervisorResumePanel({
    super.key,
    required this.userId,
    required this.workerHost,
    required this.apiPrefix,
    this.refreshInterval = const Duration(seconds: 20),
  });

  final String? userId;
  final String workerHost;
  final String apiPrefix;
  final Duration refreshInterval;

  @override
  State<SupervisorResumePanel> createState() => _SupervisorResumePanelState();
}

class _SupervisorResumePanelState extends State<SupervisorResumePanel>
    with SingleTickerProviderStateMixin {
  Timer? _refreshTimer;
  bool _loading = false;
  Map<String, dynamic>? _data;
  late final AnimationController _wiggleController;

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
      final payload = await service.fetchDashboardInfo(userId: uid);
      if (!mounted) return;
      setState(() {
        _data = payload;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = null;
      });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.userId?.trim() ?? '';
    final theme = Theme.of(context);
    if (uid.isEmpty) return const SizedBox.shrink();

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
    final hasActiveSupervisor =
        supervisor['active'] == true || supervisor['paired'] == true;
    final supervisorName = _resolveSupervisorName(supervisor);
    final queuedEmoji = _resolveQueuedEmoji(preview);
    final showName = hasActiveSupervisor && supervisorName.isNotEmpty;
    final showEmoji = hasActiveSupervisor && queuedEmoji.isNotEmpty;
    if (!showName && !showEmoji) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.08),
          width: 1,
        ),
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

  String _resolveSupervisorName(Map<String, dynamic> supervisor) {
    final registrationName =
        (supervisor['registrationName'] ?? '').toString().trim();
    if (registrationName.isNotEmpty) return registrationName;
    for (final key in const [
      'supervisorName',
      'registeredName',
      'displayName',
      'name',
    ]) {
      final value = (supervisor[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _resolveQueuedEmoji(List<Map<String, dynamic>> preview) {
    for (final item in preview) {
      final emoji = (item['emoji'] ?? '').toString().trim();
      if (emoji.isNotEmpty) return emoji;
    }
    return '';
  }
}
