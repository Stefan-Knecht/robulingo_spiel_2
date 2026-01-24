import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

// ------------------------------------------------------------
// RobuLingo Viewer (Flutter/Dart)
// ------------------------------------------------------------
// Ziel: Sprache wählen, Curriculum vom Worker laden, nur Items mit
// JSON + WebP + MP3 (gewählte Sprache) anzeigen. Sequenzielles UI
// mit Bild, Text, Audio-Button und Next-Button.
// ------------------------------------------------------------
const String defaultWorkerHost = 'robulingo-worker.knechtipad-aec.workers.dev';
const String defaultApiPrefix = '/api';
const List<String> langChoices = ['de', 'en', 'ar', 'fr', 'es', 'it', 'ru', 'hi', 'el', 'zh'];
const int batchSize = 10;
const double advanceThreshold = 0.4; // ab 40% wird der nächste Batch angestoßen

class CurriculumEntry {
  final String uuid;
  final String index;
  CurriculumEntry({required this.uuid, required this.index});
}

class ItemData {
  final String uuid;
  final String index;
  final String text;
  final Uint8List imageBytes;
  final Uri audioUri;
  ItemData({
    required this.uuid,
    required this.index,
    required this.text,
    required this.imageBytes,
    required this.audioUri,
  });
}

/// API-Client: holt Curriculum, Items und prüft/verarbeitet Assets.
class ApiClient {
  ApiClient({required this.workerHost, required this.apiPrefix});

  final String workerHost;
  final String apiPrefix;
  final http.Client _http = http.Client();
  static const Duration _getTimeout = Duration(seconds: 30);
  static const Duration _headTimeout = Duration(seconds: 20);

  Uri _path(String path, [Map<String, String>? query]) {
    return Uri.https(workerHost, '$apiPrefix$path', query);
  }

  Future<http.Response> _get(Uri uri) {
    return _http.get(uri).timeout(_getTimeout);
  }

  Future<http.Response> _head(Uri uri) {
    return _http.head(uri).timeout(_headTimeout);
  }

  Future<List<CurriculumEntry>> loadCurriculum(String lang) async {
    final uri = _path('/curriculum', {'lang': lang});
    final res = await _get(uri);
    if (res.statusCode != 200) throw Exception('Curriculum failed ${res.statusCode} url=$uri');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final items = (data['items'] as List?) ?? (data is List ? data : (data['item_order'] as List? ?? []));
    return items
        .map((e) => CurriculumEntry(
              uuid: (e['uuid'] ?? e['id'] ?? '').toString(),
              index: (e['index'] ?? '') as String,
            ))
        .where((e) => e.uuid.isNotEmpty)
        .toList();
  }

  Future<(bool ok, int status)> _urlOk(Uri url) async {
    try {
      final r = await _head(url);
      if (r.statusCode == 200) return (true, r.statusCode);
    } catch (_) {
      // ignore and fall back to GET
    }
    try {
      final req = http.Request('GET', url)..headers['range'] = 'bytes=0-0';
      final res = await _http.send(req).timeout(_headTimeout);
      await res.stream.drain();
      final status = res.statusCode;
      return (status == 200 || status == 206, status);
    } catch (_) {
      return (false, -1);
    }
  }

  Future<ItemData> loadItem(CurriculumEntry entry, String lang) async {
    // JSON
    final metaUri = _path('/file', {'key': '${entry.uuid}.json'});
    final metaRes = await _get(metaUri);
    if (metaRes.statusCode != 200) {
      throw Exception('Meta missing ${entry.uuid} url=$metaUri status=${metaRes.statusCode}');
    }
    final meta = jsonDecode(utf8.decode(metaRes.bodyBytes)) as Map<String, dynamic>;
    final text = (meta['display_$lang'] ?? meta['text_$lang'] ?? meta['text'] ?? '').toString();

    // WebP (muss existieren)
    final imgUri = _path('/file', {'key': '${entry.uuid}.webp'});
    final imgRes = await _get(imgUri);
    if (imgRes.statusCode != 200) {
      throw Exception('Image missing ${entry.uuid} url=$imgUri status=${imgRes.statusCode}');
    }
    final imgBytes = imgRes.bodyBytes;

    // MP3 (muss existieren)
    final audioUri = _path('/file', {'key': '${entry.uuid}_$lang.mp3'});
    final (ok, status) = await _urlOk(audioUri);
    if (!ok) throw Exception('Audio missing ${entry.uuid} lang=$lang url=$audioUri status=$status');

    return ItemData(
      uuid: entry.uuid,
      index: entry.index,
      text: text.isEmpty ? jsonEncode(meta) : text,
      imageBytes: imgBytes,
      audioUri: audioUri,
    );
  }
}

class RobuLingoApp extends StatefulWidget {
  const RobuLingoApp({super.key});
  @override
  State<RobuLingoApp> createState() => _RobuLingoAppState();
}

class _RobuLingoAppState extends State<RobuLingoApp> {
  late ApiClient api;
  String workerHost = defaultWorkerHost;
  String apiPrefix = defaultApiPrefix;
  final AudioPlayer player = AudioPlayer();

  String lang = 'de';
  List<CurriculumEntry> curriculum = [];
  final List<ItemData> items = [];
  final List<String> loadErrors = [];
  int pos = 0;
  bool loading = true;
  bool batchLoading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    api = ApiClient(workerHost: workerHost, apiPrefix: apiPrefix);
    WidgetsBinding.instance.addPostFrameCallback((_) => _chooseLangAndLoad());
  }

  Future<void> _chooseLangAndLoad() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sprache wählen'),
        children: langChoices
            .map((l) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, l),
                  child: Text(l),
                ))
            .toList(),
      ),
    );
    lang = selected ?? lang;
    _loadInitial();
  }

  Future<void> _openSettings() async {
    final hostCtrl = TextEditingController(text: workerHost);
    final prefixCtrl = TextEditingController(text: apiPrefix);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Worker-URL anpassen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostCtrl,
              decoration: const InputDecoration(labelText: 'Host (ohne Schema)', hintText: 'example.com'),
            ),
            TextField(
              controller: prefixCtrl,
              decoration: const InputDecoration(labelText: 'API-Prefix', hintText: '/api'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'host': hostCtrl.text.trim(),
              'prefix': prefixCtrl.text.trim(),
            }),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    if (result != null && result['host'] != null && result['host']!.isNotEmpty) {
      final newHost = result['host']!;
      final newPrefix = result['prefix']?.isNotEmpty == true ? result['prefix']! : '/api';
      final normalizedPrefix = newPrefix.startsWith('/') ? newPrefix : '/$newPrefix';
      setState(() {
        workerHost = newHost;
        apiPrefix = normalizedPrefix;
        api = ApiClient(workerHost: workerHost, apiPrefix: apiPrefix);
      });
      _loadInitial();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      loading = true;
      error = null;
      pos = 0;
      items.clear();
      loadErrors.clear();
    });
    try {
      curriculum = await api.loadCurriculum(lang);
      if (curriculum.isEmpty) {
        setState(() {
          loading = false;
          error = 'Leeres Curriculum.';
        });
        return;
      }

      // Mehrere Batches vorladen, bis wenigstens 1 Item erfolgreich ist
      var offset = 0;
      while (items.isEmpty && offset < curriculum.length) {
        await _loadBatch(offset);
        offset += batchSize;
      }

      if (items.isEmpty) {
        setState(() {
          loading = false;
          error = 'Kein Item mit vollständigen Assets (JSON/WebP/MP3 für $lang) gefunden.';
        });
      } else {
        setState(() {
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _loadBatch(int offset) async {
    if (batchLoading) return;
    batchLoading = true;
    final slice = curriculum.skip(offset).take(batchSize).toList();
    final List<String> batchErrors = [];
    try {
      for (final entry in slice) {
        try {
          final item = await api.loadItem(entry, lang);
          items.add(item);
        } catch (e) {
          batchErrors.add('${entry.uuid}: $e');
        }
      }
    } finally {
      batchLoading = false;
      if (mounted) {
        setState(() {
          loadErrors.addAll(batchErrors);
        });
      }
    }
  }

  void _next() {
    if (pos + 1 >= items.length) return;
    setState(() => pos++);
    if ((pos / items.length) >= advanceThreshold) {
      _loadBatch(items.length);
    }
  }

  Future<void> _playAudio() async {
    final item = items[pos];
    await player.setUrl(item.audioUri.toString());
    await player.play();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = Center(child: Text('Fehler: $error'));
    } else if (items.isEmpty) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Keine Items geladen.'),
            if (loadErrors.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Fehler beim Laden:'),
              SizedBox(
                height: 160,
                child: ListView(
                  shrinkWrap: true,
                  children: loadErrors
                      .map((e) => Text(e, style: const TextStyle(fontSize: 12)))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      final item = items[pos];
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.memory(item.imageBytes, width: 300, height: 300, fit: BoxFit.contain),
          const SizedBox(height: 12),
          Text('[${item.index}] ${item.text}', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _playAudio, child: Text('Play $lang')),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _next, child: const Text('Next')),
          const SizedBox(height: 8),
          Text('Item ${pos + 1} / ${items.length}'),
        ],
      );
    }

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('RobuLingo Viewer ($lang)'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadInitial,
              tooltip: 'Neu laden',
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _openSettings,
              tooltip: 'Worker anpassen',
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: body,
        ),
      ),
    );
  }
}

void main() {
  runApp(const RobuLingoApp());
}
