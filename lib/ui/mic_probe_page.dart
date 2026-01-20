import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:robulingo_flutter/app/robulingo_app.dart';

class MicProbePage extends StatefulWidget {
  const MicProbePage({super.key});

  @override
  State<MicProbePage> createState() => _MicProbePageState();
}

class _MicProbePageState extends State<MicProbePage> {
  PermissionStatus? _status;
  String? _lastRequest;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final current = await Permission.microphone.status;
    if (!mounted) return;
    setState(() {
      _status = current;
    });
  }

  Future<void> _requestPermission() async {
    setState(() {
      _busy = true;
      _lastRequest = null;
    });
    final result = await Permission.microphone.request();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastRequest = result.toString();
      _status = result;
    });
  }

  Future<void> _openSettings() async {
    setState(() => _busy = true);
    await openAppSettings();
    await _refreshStatus();
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  void _openRobuLingo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RobuLingoApp(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = _statusLabel(_status);
    final isPermanentlyDenied =
        _status != null && _status!.isPermanentlyDenied;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mic Probe'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Prüft, ob iOS die Mikrofon-Permission vergibt. '
                  'Tippe „Request“ für den Systemdialog und gehe dann weiter in die App.',
                  textAlign: TextAlign.center,
                ),
                if (isPermanentlyDenied) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Die Anfrage wurde dauerhaft abgelehnt. Öffne die iOS-Einstellungen, '
                    'um das Mikro manuell freizugeben.',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                _StatusRow(label: 'Status', value: statusLabel),
                const SizedBox(height: 8),
                _StatusRow(
                  label: 'Letzte Anfrage',
                  value: _lastRequest ?? '—',
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _refreshStatus,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _requestPermission,
                  icon: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mic),
                  label: const Text('Request'),
                ),
                if (isPermanentlyDenied) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _openSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Einstellungen öffnen'),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _openRobuLingo,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Weiter zur App'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

String _statusLabel(PermissionStatus? status) {
  switch (status) {
    case PermissionStatus.denied:
      return 'Abgelehnt';
    case PermissionStatus.granted:
      return 'Erteilt';
    case PermissionStatus.limited:
      return 'Eingeschränkt';
    case PermissionStatus.provisional:
      return 'Vorläufig erteilt';
    case PermissionStatus.permanentlyDenied:
      return 'Dauerhaft abgelehnt';
    case PermissionStatus.restricted:
      return 'Eingeschränkt (System)';
    case null:
      return 'Unbekannt';
  }
}
