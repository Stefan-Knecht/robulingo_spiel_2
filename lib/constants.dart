// ------------------------------------------------------------
// Ziel (Laien): Gemeinsame Default-Konstanten (Hosts, Sprachen, Layout) für die App.
// Strategie: Alles an einem Ort bündeln, damit main.dart und UI/Services weniger Magie haben.
// Schritte: Hosts/Prefix, Sprachliste, UI-Parameter (Batch-Größen, Seeds, Track-Länge).
// Tücken: Änderungen hier wirken überall – bei Worker-Umzug oder Track-Länge auch Logik prüfen.
// ------------------------------------------------------------
const String defaultWorkerHost = 'robulingo-api.knechtipad-aec.workers.dev';
// Item-/Asset-Worker (JSON/WEBP/MP3).
const String defaultFileHost = 'robulingo-worker.knechtipad-aec.workers.dev';
const String defaultApiPrefix = '/api';
// R2-Bucket (Cloudflare) – virtueller Host und Pfadvariante, beide probieren
const String curriculumBucketVirtualHost =
    'https://curriculum.aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com';
const String curriculumBucketPathBase =
    'https://aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com/curriculum';
// User-Daten-Bucket (Logs, User-Curriculum)
const String userDataBucketVirtualHost =
    'https://userdata.aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com';
const String userDataBucketPathBase =
    'https://aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com/userdata';
// Hint-Packs (Cloudflare R2) – virtuell und Pfad-Variante
const String hintsBucketVirtualHost =
    'https://hints.aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com';
const String hintsBucketPathBase =
    'https://aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com/hints';
// Standard-Seed (existiert im Bucket/Worker); vorheriger Default war leer.
const String defaultStartCurriculum = 'start_curriculum_a.json';
const List<String> langChoices = [
  'de',
  'en',
  'ar',
  'fr',
  'es',
  'it',
  'ru',
  'hi',
  'el',
  'zh',
  'tr',
  'ja',
];
const int batchSize = 12; // Wie viele Items wir in einem Rutsch vom Worker holen
const double prefetchThreshold = 0.6; // sobald Rest kleiner als 60% des Fensters ist, laden wir nach
const int prefetchWindowSize = 12; // Größe des Fensters, auf das sich das Verhältnis bezieht
const int minTrials = 10; // Mindestens so viele Übungsrunden wollen wir initial haben
const int initialItemDownloadLimit = minTrials; // Items, deren Assets wir sofort laden (Rest per Refresh)
const int seedCount = 0; // Anzahl Seed-Items (aus start_curriculum_a.json)
const int reviewInterval = 10; // nach jeweils ~10 Trials eine Wiederholung aus der Vergangenheit
const bool dashboardOnlyAfterSession = true; // bei true erst nach Session-Ende freischalten
const int trackLength = 12;
const int startCurriculumWindowSize = 10; // wie viele Items aus dem Start-Curriculum initial geladen werden

const Map<String, String> langFlags = {
  'de': '🇩🇪',
  'en': '🇬🇧',
  'ar': '🇸🇦',
  'fr': '🇫🇷',
  'es': '🇪🇸',
  'it': '🇮🇹',
  'ru': '🇷🇺',
  'hi': '🇮🇳',
  'el': '🇬🇷',
  'zh': '🇨🇳',
  'tr': '🇹🇷',
  'ja': '🇯🇵',
};

const Map<String, String> speechLocaleOverrides = {
  'de': 'de-DE',
  'en': 'en-US',
  'ar': 'ar-AR',
  'fr': 'fr-FR',
  'es': 'es-ES',
  'it': 'it-IT',
  'ru': 'ru-RU',
  'hi': 'hi-IN',
  'el': 'el-GR',
  'zh': 'zh-CN',
  'tr': 'tr-TR',
  'ja': 'ja-JP',
};

const Map<String, String> startCurriculumIcons = {
  'start_curriculum_a.json': 'assets/icons/cross.webp',
  'start_curriculum_b.json': 'assets/icons/toddler.webp',
  'start_curriculum_t.json': 'assets/icons/talk.webp',
  'start_curriculum_s.json': 'assets/icons/step.webp',
  'start_curriculum_l.json': 'assets/icons/glasses.webp',
};

/// File that lists available pick manifests in the curriculum bucket.
const String pickManifestIndexKey = 'pick_manifest_index.json';
