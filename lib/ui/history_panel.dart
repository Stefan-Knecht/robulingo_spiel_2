import 'package:flutter/material.dart';

import '../data/resume_state_service.dart';
import '../logic/history_hint_loader.dart';

Future<void> showHistoryPanel({
  required BuildContext context,
  required String? userId,
  required String? nativeLang,
  required ResumeState? resumeState,
  required ResumeStateService resumeStateService,
  required HistoryHintLoader hintLoader,
  required Future<void> Function(String id, ResumeState? state) onApplyUserId,
  required Future<void> Function() onRemoveUserId,
}) async {
  final controller = TextEditingController(text: userId ?? '');
  String status = '';
  bool loading = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final l1 = (nativeLang ??
                  resumeState?.mostRecentEntry()?.nativeLang ??
                  'en')
              .trim()
              .toLowerCase();
          final reloadLabel = _labelFor('reload', l1);
          final removeLabel = _labelFor('remove', l1);
          final Widget cell2 = IconButton(
            icon: Icon(
              Icons.refresh,
              size: 30,
              color: Colors.green.shade700,
              weight: 800,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(),
          );
          final Widget cell3 = GestureDetector(
            onTap: loading
                ? null
                : () async {
                    final id = controller.text.trim();
                    if (id.isEmpty) return;
                    setDialogState(() {
                      loading = true;
                      status = '';
                    });
                    final state =
                        await resumeStateService.fetch(userId: id);
                    await onApplyUserId(id, state);
                    if (!ctx.mounted) return;
                    setDialogState(() {
                      loading = false;
                      status = (state == null || state.entries.isEmpty)
                          ? 'User ID übernommen (kein Verlauf gefunden).'
                          : 'User ID aktualisiert.';
                    });
                  },
            child: Column(
              children: [
                Image.asset(
                  'assets/icons/reload.webp',
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          );
          final Widget cell4 = GestureDetector(
            onTap: loading
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: ctx,
                      builder: (confirmCtx) {
                        return AlertDialog(
                          title: const Text('Are you sure?'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(confirmCtx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(confirmCtx).pop(true),
                              child: const Text('Remove'),
                            ),
                          ],
                        );
                      },
                    );
                    if (confirmed != true) return;
                    await onRemoveUserId();
                    if (!ctx.mounted) return;
                    setDialogState(() {
                      status = 'User ID entfernt.';
                    });
                    Navigator.of(dialogCtx).pop();
                  },
            child: Column(
              children: [
                Image.asset(
                  'assets/icons/remove.webp',
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          );
          final Widget cell5 = GestureDetector(
            onTap: loading
                ? null
                : () async {
                    setDialogState(() {
                      loading = true;
                      status = '';
                    });
                    final text = await hintLoader.loadHint(l1);
                    if (!ctx.mounted) return;
                    setDialogState(() {
                      loading = false;
                    });
                    if (!ctx.mounted) return;
                    showDialog<void>(
                      context: ctx,
                      builder: (hintCtx) => AlertDialog(
                        content: Text(text),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(hintCtx).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
            child: Image.asset(
              'assets/icons/Magnifying_glass.webp',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
            ),
          );
          final Widget cell6 = Center(child: Text(reloadLabel));
          final Widget cell7 = Center(child: Text(removeLabel));
          final Widget cell8 = const SizedBox.shrink();
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Progress Reference',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(flex: 1, child: Center(child: cell2)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(flex: 2, child: Center(child: cell3)),
                      Expanded(flex: 2, child: Center(child: cell4)),
                      Expanded(flex: 1, child: Center(child: cell5)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(flex: 2, child: cell6),
                      Expanded(flex: 2, child: cell7),
                      Expanded(flex: 1, child: Center(child: cell8)),
                    ],
                  ),
                  if (status.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(status, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String _labelFor(String key, String l1) {
  const labels = <String, Map<String, String>>{
    'reload': {
      'en': 'reload',
      'de': 'neu laden',
    },
    'remove': {
      'en': 'remove',
      'de': 'entfernen',
    },
  };
  final normalized = l1.trim().toLowerCase();
  final map = labels[key];
  if (map == null) return key;
  return map[normalized] ?? map['en'] ?? key;
}
