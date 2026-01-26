import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'track_painter.dart';

// ------------------------------------------------------------
// RobuLingo Viewer (Flutter)
// ------------------------------------------------------------
// Zweck (für Nicht-Techies):
// - Kleiner Desktop-/Mobile-Viewer, der Lernkarten aus dem Cloudflare-Worker lädt
//   und nur Karten mit vollständigen Assets (JSON, Bild, Audio) anzeigt.
// Strategie & Schritte:
// 1) Sprache per Dialog wählen.
// 2) Curriculum vom Worker holen.
// 3) In Batches laden, bis mindestens 1 Karte mit allen Assets gefunden ist.
// 4) Weitere Batches nachladen, sobald man ~40% der geladenen Karten gesehen hat.
// Flutter-Besonderheiten:
// - setState() löst UI-Updates aus; wir halten UI responsiv.
// - Audio via just_audio; Bilder aus Bytes.
// - Der Worker antwortet bei HEAD-Anfragen auf MP3 teils mit 404,
//   deshalb prüfen wir Audio zusätzlich mit einer minimalen GET-Range.
// ------------------------------------------------------------
const String defaultWorkerHost = 'robulingo-worker.knechtipad-aec.workers.dev';
const String defaultApiPrefix = '/api';
const List<String> langChoices = ['de', 'en', 'ar', 'fr', 'es', 'it', 'ru', 'hi', 'el', 'zh'];
const int batchSize = 12; // Wie viele Items wir in einem Rutsch vom Worker holen
const double advanceThreshold = 0.4; // ab 40% Nutzung laden wir vorsorglich nach
const int minTrials = 10; // Mindestens so viele Übungsrunden wollen wir initial haben

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

class Trial {
  final ItemData target;
  final ItemData distractor;
  final bool targetOnLeft;
  Trial({
    required this.target,
    required this.distractor,
    required this.targetOnLeft,
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

  // Hilfsfunktion: baut eine HTTPS-URL zum Worker inkl. Query-Parametern
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
    if (res.statusCode != 200) throw Exception('Curriculum failed ${res.statusCode}');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final items = (data['items'] as List?) ?? [];
    return items
        .map((e) => CurriculumEntry(
              uuid: e['uuid'] as String,
              index: (e['index'] ?? '') as String,
            ))
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
      // Einige Worker liefern auf HEAD 404. Range-GET testet Audio minimal.
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
  final List<Trial> trials = [];
  final List<String> loadErrors = [];
  int trialIndex = 0;
  bool loading = true;
  bool batchLoading = false;
  String? error;
  bool hasAnswered = false;
  bool? lastCorrect;
  bool? lastSelectionIsLeft;
  // HexaMatch Mini-State
  static const int trackLength = 12;
  int youX = 0;
  int youLane = 0; // 0 = oben, 1 = unten
  int rivalX = 0;
  int rivalLane = 1;
  bool youLastSide = false;
  bool rivalLastSide = false;
  int selectionEpoch = 0;
  bool sessionReady = false;
  StreamSubscription? playbackSub;

  @override
  void initState() {
    super.initState();
    player.setReleaseMode(ReleaseMode.stop);
    playbackSub = player.onPlayerStateChanged.listen((state) {
      debugPrint('[audio] state=$state playing=${state == PlayerState.playing}');
    }, onError: (Object e, StackTrace st) {
      debugPrint('[audio][error-state] $e');
    });
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
    // Initialer Ladepfad: UI zurücksetzen, Curriculum holen,
    // dann so viele Batches laden, bis mindestens 1 valides Item da ist
    // oder nichts Brauchbares gefunden wird.
    setState(() {
      loading = true;
      error = null;
      trialIndex = 0;
      trials.clear();
      hasAnswered = false;
      lastCorrect = null;
      lastSelectionIsLeft = null;
      items.clear();
      loadErrors.clear();
      youX = 0;
      youLane = 0;
      rivalX = 0;
      rivalLane = 1;
      youLastSide = false;
      rivalLastSide = false;
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

      // Mehrere Batches vorladen, bis mindestens minTrials Trials erzeugt oder Curriculum erschöpft
      var offset = 0;
      while (trials.length < minTrials && offset < curriculum.length) {
        await _loadBatch(offset);
        offset += batchSize;
      }

      if (items.isEmpty) {
        setState(() {
          loading = false;
          error = 'Kein Item mit vollständigen Assets (JSON/PNG/MP3 für $lang) gefunden.';
        });
      } else {
        setState(() {
          loading = false;
        });
        // Ersten Trial automatisch mit Audio starten, sobald UI steht.
        if (mounted && trials.isNotEmpty) {
          final currentEpoch = selectionEpoch;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _playNextTrialAudio(currentEpoch);
          });
        }
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
    final startCount = items.length;
    // Lade einen Teilbereich des Curriculums (offset..offset+batchSize),
    // sammle valide Items und protokolliere Fehler separat.
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
          final newItems = items.sublist(startCount);
          _appendTrials(newItems);
        });
      }
    }
  }

  void _appendTrials(List<ItemData> newItems) {
    if (newItems.isEmpty || items.length < 2) return;
    final rand = Random();
    for (final target in newItems) {
      final distractor = _pickDistractor(target, rand);
      if (distractor == null) continue;
      trials.add(Trial(
        target: target,
        distractor: distractor,
        targetOnLeft: rand.nextBool(),
      ));
    }
  }

  ItemData? _pickDistractor(ItemData target, Random rand) {
    if (items.length < 2) return null;
    ItemData candidate = target;
    var attempts = 0;
    while (candidate.uuid == target.uuid && attempts < 10) {
      candidate = items[rand.nextInt(items.length)];
      attempts++;
    }
    if (candidate.uuid == target.uuid) return null;
    return candidate;
  }

  Future<void> _playAudioForItem(ItemData item) async {
    try {
      await player.stop();
      await player.play(UrlSource(item.audioUri.toString()));
    } catch (e) {
      debugPrint('[audio][error] url=${item.audioUri} err=$e');
    }
  }

  Future<void> _playNextTrialAudio(int epoch) async {
    if (!mounted || epoch != selectionEpoch) return;
    if (trialIndex >= trials.length) return;
    final item = trials[trialIndex].target;
    debugPrint('[audio][play] idx=$trialIndex epoch=$epoch url=${item.audioUri}');
    await _playAudioForItem(item);
  }

  void _select(bool choseLeft) {
    if (trials.isEmpty || hasAnswered) return;
    final trial = trials[trialIndex];
    final correct = choseLeft == trial.targetOnLeft;
    selectionEpoch++;
    final currentEpoch = selectionEpoch;
    _advanceLadder(correct);
    final bool hasNext = trialIndex + 1 < trials.length;
    setState(() {
      hasAnswered = true;
      lastCorrect = correct;
      lastSelectionIsLeft = choseLeft;
    });
    if (!mounted || currentEpoch != selectionEpoch) return;
    if (!hasNext) {
      debugPrint('[audio][no-next] trials=${trials.length} idx=$trialIndex');
      _loadBatch(items.length); // versuche nachzuladen, falls Curriculum noch mehr hat
      return;
    }
    // Kurz Feedback zeigen (Borders bleiben sichtbar), dann weiter.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || currentEpoch != selectionEpoch) return;
      setState(() {
        trialIndex++;
        hasAnswered = false;
        lastCorrect = null;
        lastSelectionIsLeft = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playNextTrialAudio(currentEpoch);
      });
    });
  }

  void _advanceLadder(bool correct) {
    final rand = Random();
    void applyMove(bool isCorrect, {required bool isYou}) {
      int x = isYou ? youX : rivalX;
      int lane = isYou ? youLane : rivalLane;
      bool lastSide = isYou ? youLastSide : rivalLastSide;

      if (isCorrect) {
        x = (x + 1).clamp(0, trackLength - 1);
        lastSide = false;
      } else {
        if (lastSide) {
          x = (x - 1).clamp(0, trackLength - 1);
          lastSide = false;
        } else {
          lane = lane == 0 ? 1 : 0;
          lastSide = true;
        }
      }

      if (isYou) {
        youX = x;
        youLane = lane;
        youLastSide = lastSide;
      } else {
        rivalX = x;
        rivalLane = lane;
        rivalLastSide = lastSide;
      }
    }

    applyMove(correct, isYou: true);

    // Rival bewegt sich zufällig nach der gleichen Logik (50% korrekt/inkorrekt).
    final rivalCorrect = rand.nextBool();
    applyMove(rivalCorrect, isYou: false);

    setState(() {});
  }

  @override
  void dispose() {
    playbackSub?.cancel();
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Worker anpassen'),
            ),
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
    } else if (trials.isEmpty) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Zu wenige Items für Lingomatch (mind. 2 benötigt).'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadInitial,
              icon: const Icon(Icons.refresh),
              label: const Text('Neu laden'),
            ),
          ],
        ),
      );
    } else if (trialIndex >= trials.length) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Keine weiteren Trials.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadInitial,
              icon: const Icon(Icons.refresh),
              label: const Text('Neu laden'),
            ),
          ],
        ),
      );
    } else {
      final trial = trials[trialIndex];
      final left = trial.targetOnLeft ? trial.target : trial.distractor;
      final right = trial.targetOnLeft ? trial.distractor : trial.target;
      final screenHeight = MediaQuery.of(context).size.height;
      final cardMaxHeight = screenHeight * 0.45;

      Widget option(ItemData item, bool isLeft) {
        final isSelected = hasAnswered && lastSelectionIsLeft == isLeft;
        final isTargetSide = trial.targetOnLeft == isLeft;
        Color border = Colors.grey.shade400;
        if (hasAnswered) {
        if (isTargetSide) border = Colors.green;
        if (isSelected && !isTargetSide) border = Colors.red;
        }
        return Expanded(
          child: GestureDetector(
            onTap: () => _select(isLeft),
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: border, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: cardMaxHeight,
                ),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      item.imageBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            trial.target.text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildLadderTrack(),
          const SizedBox(height: 12),
          Row(
            children: [
              option(left, true),
              option(right, false),
            ],
          ),
          const SizedBox(height: 8),
          if (hasAnswered && lastCorrect != null)
            Text(lastCorrect! ? 'Richtig ✅' : 'Falsch ❌', style: TextStyle(color: lastCorrect! ? Colors.green : Colors.red)),
          const SizedBox(height: 8),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: body,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLadderTrack() {
    const laneSize = 26.0;
    const markerSize = 18.0;
    const labelWidth = 50.0;
    const strokeWidth = 1.5;

    Widget buildTrack(Color color, int pos, String label, int lane) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = (constraints.maxWidth - labelWidth).clamp(10.0, 9999.0);
          const trackHeight = laneSize + markerSize; // genug Platz für Marker ober-/unterhalb
          // Marker um einen halben Durchmesser nach unten verschieben:
          // Lane 0 startet am oberen Linienrand, Lane 1 am unteren Linienrand.
          final markerTop = lane == 0 ? 0.0 : laneSize;

          return SizedBox(
            height: trackHeight,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: label.isNotEmpty ? Text(label, style: const TextStyle(fontSize: 12)) : const SizedBox.shrink(),
                    ),
                    CustomPaint(
                      size: Size(trackWidth, laneSize),
                      painter: TrackPainter(color: color, strokeWidth: strokeWidth),
                    ),
                  ],
                ),
                Positioned(
                  left: labelWidth + pos * (trackWidth / trackLength) - (markerSize / 2),
                  top: markerTop,
                  child: Container(
                    width: markerSize,
                    height: markerSize,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          buildTrack(Colors.blue, youX, 'Du', youLane),
          const SizedBox(height: 10),
          buildTrack(Colors.orange, rivalX, 'Rival', rivalLane),
        ],
      ),
    );
  }
}

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RobuLingoApp(),
  ));
}
