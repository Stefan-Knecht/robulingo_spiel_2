// ------------------------------------------------------------
// Ziel (Laien): Minimaler Standalone-Screen zum Testen von Mikro/ASR (ohne Haupt-Flow).
// Verbindung: Nutzt dieselben Plugins wie NamingController; hilfreich für Gerätesmoke-Tests.
// Tücken: Locale hart auf de_DE; speichert nichts, nur Laufzeittranskript.
// ------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Minimaler Benenn-Demo-Screen: Bild, Transkript, Start/Stop.
class NamingDemoScreen extends StatefulWidget {
  const NamingDemoScreen({super.key});

  @override
  State<NamingDemoScreen> createState() => _NamingDemoScreenState();
}

class _NamingDemoScreenState extends State<NamingDemoScreen> {
  late final stt.SpeechToText _speech;
  bool _hasPermission = false;
  bool _permanentlyDenied = false;
  bool _isListening = false;
  String _status = 'Bereit';
  String _transcript = '';
  String _debugPerm = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _ensurePermission();
  }

  Future<void> _ensurePermission() async {
    // Erst Status lesen, dann nur bei Bedarf nachfragen
    var micStatus = await Permission.microphone.status;
    var speechStatus = await Permission.speech.status;

    if (!micStatus.isGranted && !micStatus.isPermanentlyDenied) {
      micStatus = await Permission.microphone.request();
    }
    if (!speechStatus.isGranted && !speechStatus.isPermanentlyDenied) {
      speechStatus = await Permission.speech.request();
    }

    _permanentlyDenied = micStatus.isPermanentlyDenied || speechStatus.isPermanentlyDenied;

    if (micStatus.isGranted && speechStatus.isGranted) {
      final ok = await _speech.initialize(
        onStatus: (s) => setState(() => _status = 'Status: $s'),
        onError: (e) => setState(() => _status = 'Fehler: ${e.errorMsg}'),
      );
      _hasPermission = ok;
      _status = ok ? 'Berechtigt – Aufnahme starten.' : 'Spracherkennung nicht initialisiert';
    } else {
      _hasPermission = false;
      _status = 'Mikrofon/Sprache nicht freigegeben';
    }

    setState(() {
      _debugPerm = 'Mic: $micStatus, Speech: $speechStatus';
    });
  }

  Future<void> _startListening() async {
    if (!_hasPermission || _isListening) {
      if (!_hasPermission) {
        await _ensurePermission();
      }
      if (!_hasPermission) return;
    }
    setState(() {
      _isListening = true;
      _status = '🎙 Aufnahme läuft...';
      _transcript = '';
    });

    await _speech.listen(
      localeId: 'de_DE',
      listenFor: const Duration(seconds: 8),
      onResult: (result) {
        setState(() {
          _transcript = result.recognizedWords.trim();
        });
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
      _status = '🔇 Aufnahme gestoppt';
    });
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benenn-Demo'),
        backgroundColor: Colors.deepOrange,
        actions: [
          IconButton(
            onPressed: _ensurePermission,
            icon: const Icon(Icons.refresh),
            tooltip: 'Berechtigung neu prüfen',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.insert_photo, size: 120, color: Colors.orange),
            const SizedBox(height: 12),
            const Text(
              'Benenn-Test',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: TextStyle(
                fontSize: 14,
                color: _hasPermission ? Colors.black87 : Colors.red.shade700,
              ),
            ),
            if (_debugPerm.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  _debugPerm,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _transcript.isEmpty ? 'Noch nichts erkannt.' : _transcript,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isListening ? null : _startListening,
                  icon: const Icon(Icons.mic),
                  label: const Text('Aufnahme starten'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isListening ? _stopListening : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_hasPermission) ...[
              ElevatedButton(
                onPressed: _ensurePermission,
                child: const Text('Berechtigung erlauben'),
              ),
              const SizedBox(height: 8),
              Text(
                _permanentlyDenied
                    ? 'Bitte in den Systemeinstellungen Mikrofon für diese App erlauben.'
                    : 'Mikrofonberechtigung erforderlich. Bitte erlauben.',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              if (_permanentlyDenied)
                const TextButton(
                  onPressed: openAppSettings,
                  child: Text('Systemeinstellungen öffnen'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
