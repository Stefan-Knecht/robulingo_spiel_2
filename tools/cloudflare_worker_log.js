// Cloudflare Worker for RobuLingo logs + user curriculum delta.
// Bindings: R2 bucket named USERDATA -> bucket "userdata"
// Bindings: R2 bucket named HINTS -> bucket "hints"

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    try {
      if (path.endsWith('/hints')) {
        return await handleHints(request, env);
      }
      if (path.endsWith('/android-release/latest')) {
        return await handleAndroidReleaseLatest(request, env);
      }
      if (path.endsWith('/android-release/download')) {
        return await handleAndroidReleaseDownload(request, env);
      }
      if (path.endsWith('/android-release/download-stats')) {
        return await handleAndroidReleaseDownloadStats(request, env);
      }
      if (path.endsWith('/start-curriculum')) {
        return await handleStartCurriculum(request, env);
      }
      if (path.endsWith('/file')) {
        return await handleCurriculumFile(request, env);
      }
      if (path.endsWith('/log')) {
        return await handleLog(request, env);
      }
      if (path.endsWith('/summary')) {
        return await handleSummary(request, env);
      }
      if (path.endsWith('/audio-target-matches')) {
        return await handleAudioTargetMatches(request, env);
      }
      if (path.endsWith('/resume-state')) {
        return await handleResumeState(request, env);
      }
      if (path.endsWith('/consent')) {
        return await handleConsent(request, env);
      }
      if (path.endsWith('/pair')) {
        return await handlePair(request, env);
      }
      if (path.endsWith('/emoji-queue')) {
        return await handleEmojiQueue(request, env);
      }
      if (path.endsWith('/emoji-queue-ack')) {
        return await handleEmojiQueueAck(request, env);
      }
      if (path.endsWith('/dashboard-info')) {
        return await handleDashboardInfo(request, env);
      }
      if (path.endsWith('/learner-profile')) {
        return await handleLearnerProfile(request, env);
      }
      if (path.endsWith('/supervisor-users')) {
        return await handleSupervisorUsers(request, env);
      }
      if (path.endsWith('/user-curriculum')) {
        return await handleCurriculum(request, env);
      }
      return new Response('not found', { status: 404 });
    } catch (err) {
      return new Response(`error: ${err instanceof Error ? err.message : String(err)}`, {
        status: 500,
      });
    }
  },
};

const CORS_HEADERS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,HEAD,POST,DELETE,OPTIONS',
  'access-control-allow-headers':
    'content-type,if-none-match,x-user-id,x-session-id,content-encoding,x-app-flavor,x-supervisor-email,x-supervisor-code',
};

// ---------- /hints ----------
async function handleHints(request, env) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const url = new URL(request.url);
  const l1 = normalizeLang(url.searchParams.get('l1'));
  const l2 = normalizeLang(url.searchParams.get('l2'));
  if (!l1 || !l2) {
    return new Response('missing l1/l2', {
      status: 400,
      headers: { ...CORS_HEADERS, 'cache-control': 'no-store' },
    });
  }
  const key = `hints_${l1}_${l2}.json`;
  const obj = await env.HINTS.get(key);
  console.log('[hints]', { l1, l2, key, hit: !!obj });
  if (!obj) {
    return new Response('not found', {
      status: 404,
      headers: { ...CORS_HEADERS, 'cache-control': 'no-store' },
    });
  }
  const etag = obj.etag;
  const ifNoneMatch = request.headers.get('if-none-match');
  if (ifNoneMatch && etag && ifNoneMatch === etag) {
    return new Response(null, {
      status: 304,
      headers: { ...CORS_HEADERS, etag, 'cache-control': 'public, max-age=300' },
    });
  }
  const headers = {
    ...CORS_HEADERS,
    'cache-control': 'public, max-age=300',
    'content-type': obj.httpMetadata?.contentType || 'application/json',
  };
  if (etag) headers.etag = etag;
  if (request.method === 'HEAD') {
    return new Response(null, { status: 200, headers });
  }
  return new Response(obj.body, { status: 200, headers });
}

// ---------- /android-release/* ----------
const APK_RELEASE_PREFIX_DAILYWORDS = 'releases/android/dailywords';
const APK_RELEASE_LATEST_KEY_DAILYWORDS = `${APK_RELEASE_PREFIX_DAILYWORDS}/latest.json`;
const APK_DOWNLOAD_EVENTS_PREFIX = 'system/apk_downloads';
const DEFAULT_DAILYWORDS_APK_MANIFEST_URL =
  'https://pub-64932e0bdd094618872a67d7b1ff3c50.r2.dev/releases/android/dailywords/latest.json';

async function handleAndroidReleaseLatest(request, env) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const flavor = resolveAndroidReleaseFlavor(request);
  if (!flavor) {
    return jsonResponse({ error: 'unsupported flavor' }, 400);
  }
  const manifest = await loadAndroidReleaseManifest(request, env, flavor);
  if (!manifest || !manifest.apkUrl) {
    return jsonResponse({ error: 'release manifest not found or missing apk_url' }, 404);
  }
  const payload = {
    flavor,
    version: manifest.version,
    version_name: manifest.versionName,
    version_code: manifest.versionCode,
    uploaded_at_utc: manifest.uploadedAtUtc,
    apk_file: manifest.apkFile,
    sha256: manifest.sha256,
    size_bytes: manifest.sizeBytes,
    apk_url: manifest.apkUrl,
    tracked_download_url: buildAndroidReleaseDownloadUrl(request, flavor, 'update_check'),
    download_url: buildAndroidReleaseDownloadUrl(request, flavor, 'update_check'),
  };
  if (request.method === 'HEAD') {
    return new Response(null, {
      status: 200,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json', 'cache-control': 'no-store' },
    });
  }
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: { ...CORS_HEADERS, 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}

async function handleAndroidReleaseDownload(request, env) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const flavor = resolveAndroidReleaseFlavor(request);
  if (!flavor) {
    return new Response('unsupported flavor', { status: 400, headers: CORS_HEADERS });
  }
  const manifest = await loadAndroidReleaseManifest(request, env, flavor);
  if (!manifest || !manifest.apkUrl) {
    return new Response('release not found', { status: 404, headers: CORS_HEADERS });
  }
  if (request.method === 'GET') {
    const source = cleanOptionalString(new URL(request.url).searchParams.get('source'), 64) || 'unknown';
    const bucket = resolveSupervisorDashboardBucket(env);
    if (bucket) {
      try {
        await writeAndroidReleaseDownloadEvent(bucket, request, flavor, source, manifest);
      } catch (err) {
        console.log('[apk-download][track-error]', err instanceof Error ? err.message : String(err));
      }
    }
  }
  return new Response(null, {
    status: 302,
    headers: {
      ...CORS_HEADERS,
      location: manifest.apkUrl,
      'cache-control': 'no-store',
    },
  });
}

async function handleAndroidReleaseDownloadStats(request, env) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const flavor = resolveAndroidReleaseFlavor(request);
  if (!flavor) {
    return jsonResponse({ error: 'unsupported flavor' }, 400);
  }
  const bucket = resolveSupervisorDashboardBucket(env);
  if (!bucket) {
    return jsonResponse({ error: 'missing storage binding' }, 500);
  }
  const url = new URL(request.url);
  const now = new Date();
  const today = dateKey(now);
  const toRaw = cleanOptionalString(url.searchParams.get('to'), 32) || today;
  const fromRaw = cleanOptionalString(url.searchParams.get('from'), 32) || toRaw;
  const fromDate = parseDateKey(fromRaw);
  const toDate = parseDateKey(toRaw);
  if (!fromDate || !toDate || fromDate > toDate) {
    return jsonResponse({ error: 'invalid from/to date range' }, 400);
  }
  const diffDays = Math.floor((toDate.getTime() - fromDate.getTime()) / 86400000);
  if (diffDays > 366) {
    return jsonResponse({ error: 'max range is 366 days' }, 400);
  }
  const days = [];
  let total = 0;
  const cursor = new Date(Date.UTC(fromDate.getUTCFullYear(), fromDate.getUTCMonth(), fromDate.getUTCDate()));
  const end = new Date(Date.UTC(toDate.getUTCFullYear(), toDate.getUTCMonth(), toDate.getUTCDate()));
  while (cursor <= end) {
    const day = dateKey(cursor);
    const prefix = `${APK_DOWNLOAD_EVENTS_PREFIX}/${flavor}/events/${day}/`;
    const count = await countObjectsWithPrefix(bucket, prefix);
    days.push({ date: day, count });
    total += count;
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  const payload = {
    flavor,
    from: fromRaw,
    to: toRaw,
    total,
    days,
    generated_at_utc: new Date().toISOString(),
  };
  if (request.method === 'HEAD') {
    return new Response(null, {
      status: 200,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json', 'cache-control': 'no-store' },
    });
  }
  return jsonResponse(payload, 200);
}

function resolveAndroidReleaseFlavor(request) {
  const url = new URL(request.url);
  const requested =
    cleanOptionalString(url.searchParams.get('flavor'), 32) ||
    cleanOptionalString(url.searchParams.get('app_flavor'), 32) ||
    cleanOptionalString(request.headers.get('x-app-flavor'), 32) ||
    APP_FLAVOR_DAILYWORDS;
  const normalized = requested.toLowerCase();
  if (normalized !== APP_FLAVOR_DAILYWORDS) return null;
  return normalized;
}

function resolveAndroidReleaseLatestKey(flavor) {
  if (flavor === APP_FLAVOR_DAILYWORDS) {
    return APK_RELEASE_LATEST_KEY_DAILYWORDS;
  }
  return null;
}

async function loadAndroidReleaseManifest(request, env, flavor) {
  const key = resolveAndroidReleaseLatestKey(flavor);
  if (!key) return null;
  const bucket = env.DAILYWORDSAPK;
  let raw = null;
  if (bucket) {
    const obj = await bucket.get(key);
    if (obj) {
      try {
        raw = await obj.json();
      } catch (_) {
        raw = null;
      }
    }
  }
  if (!raw) {
    const manifestUrl = cleanOptionalString(env.DAILYWORDS_APK_MANIFEST_URL, 2048) || DEFAULT_DAILYWORDS_APK_MANIFEST_URL;
    try {
      const res = await fetch(manifestUrl, {
        method: 'GET',
        headers: { accept: 'application/json' },
      });
      if (res.ok) {
        raw = await res.json();
      }
    } catch (_) {
      raw = null;
    }
  }
  if (!raw) {
    return null;
  }
  const baseUrl = cleanOptionalString(env.DAILYWORDS_APK_PUBLIC_BASE_URL, 1024) || null;
  return normalizeAndroidReleaseManifest(raw, baseUrl);
}

function normalizeAndroidReleaseManifest(raw, publicBaseUrl = null) {
  if (!raw || typeof raw !== 'object') return null;
  const version = cleanOptionalString(raw.version, 64);
  const versionName = cleanOptionalString(raw.version_name, 64) || version;
  const versionCodeRaw = raw.version_code;
  let versionCode = Number(versionCodeRaw);
  if (!Number.isFinite(versionCode)) versionCode = 0;
  versionCode = Math.max(0, Math.floor(versionCode));
  const uploadedAtUtc = cleanOptionalString(raw.uploaded_at_utc, 64);
  const apkFile = cleanOptionalString(raw.apk_file, 256);
  const sha256 = cleanOptionalString(raw.sha256, 128);
  const r2Key = cleanOptionalString(raw.r2_key, 1024);
  const apkUrlRaw = cleanOptionalString(raw.apk_url, 2048);
  let apkUrl = apkUrlRaw;
  if (!apkUrl && publicBaseUrl && r2Key) {
    const base = publicBaseUrl.replace(/\/+$/, '');
    const path = r2Key.replace(/^\/+/, '');
    apkUrl = `${base}/${path}`;
  }
  const sizeRaw = Number(raw.size_bytes);
  const sizeBytes = Number.isFinite(sizeRaw) ? Math.max(0, Math.floor(sizeRaw)) : null;
  return {
    version,
    versionName,
    versionCode: versionCode > 0 ? versionCode : null,
    uploadedAtUtc,
    apkFile,
    sha256,
    sizeBytes,
    r2Key,
    apkUrl,
  };
}

function buildAndroidReleaseDownloadUrl(request, flavor, source = 'update_check') {
  const current = new URL(request.url);
  const next = new URL(request.url);
  next.pathname = current.pathname.replace(/\/android-release\/latest$/, '/android-release/download');
  next.search = '';
  next.searchParams.set('flavor', flavor);
  if (source) next.searchParams.set('source', source);
  return next.toString();
}

async function writeAndroidReleaseDownloadEvent(bucket, request, flavor, source, manifest) {
  const now = new Date();
  const day = dateKey(now);
  const eventId = `${now.toISOString().replace(/[:.]/g, '')}-${randomHex(4)}`;
  const key = `${APK_DOWNLOAD_EVENTS_PREFIX}/${flavor}/events/${day}/${eventId}.json`;
  const cf = request.cf || {};
  const ipRaw = cleanOptionalString(request.headers.get('cf-connecting-ip'), 64);
  const referer = cleanOptionalString(request.headers.get('referer'), 1024);
  const userAgent = cleanOptionalString(request.headers.get('user-agent'), 512);
  const payload = {
    ts: now.toISOString(),
    flavor,
    source: cleanOptionalString(source, 64) || 'unknown',
    apk_file: manifest.apkFile || null,
    version_name: manifest.versionName || null,
    version_code: manifest.versionCode ?? null,
    referer: referer || null,
    user_agent: userAgent || null,
    country: cleanCountryCode(cf.country) || null,
    region_code: cleanOptionalString(cf.regionCode, 32) || null,
    colo: cleanOptionalString(cf.colo, 32) || null,
    ip_hash: ipRaw ? await sha256Hex(ipRaw) : null,
  };
  await putJsonObject(bucket, key, payload);
}

function randomHex(bytes = 4) {
  const arr = new Uint8Array(bytes);
  crypto.getRandomValues(arr);
  return Array.from(arr)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function countObjectsWithPrefix(bucket, prefix) {
  let total = 0;
  let cursor = undefined;
  for (;;) {
    const list = await bucket.list({
      prefix,
      cursor,
      limit: 1000,
    });
    const chunk = Array.isArray(list?.objects) ? list.objects.length : 0;
    total += chunk;
    if (!list?.truncated) break;
    cursor = list.cursor;
    if (!cursor) break;
  }
  return total;
}

// ---------- /start-curriculum ----------
async function handleStartCurriculum(request, env) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  if (!env.CURRICULUM) {
    return new Response('missing CURRICULUM binding', {
      status: 500,
      headers: { ...CORS_HEADERS, 'cache-control': 'no-store' },
    });
  }
  const url = new URL(request.url);
  const key = url.searchParams.get('key');
  if (!key) {
    return new Response('missing key', {
      status: 400,
      headers: { ...CORS_HEADERS, 'cache-control': 'no-store' },
    });
  }
  const obj = await env.CURRICULUM.get(key);
  if (!obj) {
    return new Response('not found', {
      status: 404,
      headers: { ...CORS_HEADERS, 'cache-control': 'no-store' },
    });
  }
  const headers = {
    ...CORS_HEADERS,
    'cache-control': 'public, max-age=300',
    'content-type': obj.httpMetadata?.contentType || 'application/json',
  };
  if (request.method === 'HEAD') {
    return new Response(null, { status: 200, headers });
  }
  return new Response(obj.body, { status: 200, headers });
}

// ---------- /file (curriculum bucket) ----------
async function handleCurriculumFile(request, env) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  if (!env.CURRICULUM) {
    return new Response('missing CURRICULUM binding', {
      status: 500,
      headers: { ...CORS_HEADERS, 'cache-control': 'no-store' },
    });
  }
  const url = new URL(request.url);
  const key = url.searchParams.get('key');
  if (!key) {
    return new Response('missing key', {
      status: 400,
      headers: { ...CORS_HEADERS, 'cache-control': 'no-store' },
    });
  }
  const obj = await env.CURRICULUM.get(key);
  if (!obj) {
    return new Response('not found', {
      status: 404,
      headers: { ...CORS_HEADERS, 'cache-control': 'no-store' },
    });
  }
  const headers = {
    ...CORS_HEADERS,
    'cache-control': 'public, max-age=300',
    'content-type': obj.httpMetadata?.contentType || 'application/octet-stream',
  };
  if (request.method === 'HEAD') {
    return new Response(null, { status: 200, headers });
  }
  return new Response(obj.body, { status: 200, headers });
}

function normalizeLang(raw) {
  if (!raw) return '';
  const trimmed = raw.trim().toLowerCase();
  if (!trimmed) return '';
  return trimmed.split(/[-_]/)[0];
}

// ---------- /log ----------
const LOG_MAX_BYTES = 5 * 1024 * 1024; // rotate around 5MB (compressed)
const SUMMARY_IDLE_CAP_SECONDS = 20;
const SUMMARY_START_BONUS_SECONDS = 5;
const EMOJI_QUEUE_MAX_ITEMS = 500;
const EMOJI_QUEUE_MAX_PENDING_ITEMS = 2;
const TRAINING_PROFILE_MAX_ITEMS = 500;
const DASHBOARD_QUEUE_POLLING_MS = 15000;
const APP_FLAVOR_DAILYWORDS = 'dailywords';
const APP_FLAVOR_DEFAULT = 'robulingo';

function resolveAppFlavor(request) {
  const headerFlavor = cleanOptionalString(request.headers.get('x-app-flavor'), 64)?.toLowerCase();
  if (headerFlavor) return headerFlavor;
  const url = new URL(request.url);
  const queryFlavor =
    cleanOptionalString(url.searchParams.get('app_flavor'), 64)?.toLowerCase() ||
    cleanOptionalString(url.searchParams.get('flavor'), 64)?.toLowerCase() ||
    cleanOptionalString(url.searchParams.get('app'), 64)?.toLowerCase();
  return queryFlavor || APP_FLAVOR_DEFAULT;
}

function resolveUserDataBucket(request, env) {
  const flavor = resolveAppFlavor(request);
  if (flavor === APP_FLAVOR_DAILYWORDS && env.DAILYWORDSUSERDATA) {
    return env.DAILYWORDSUSERDATA;
  }
  return env.USERDATA;
}

// Supervisor dashboard data must stay isolated in DailyWords storage.
// This intentionally ignores x-app-flavor and query flavor hints.
function resolveSupervisorDashboardBucket(env) {
  if (env.DAILYWORDSUSERDATA) {
    return env.DAILYWORDSUSERDATA;
  }
  return env.USERDATA;
}

async function handleLog(request, env) {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const uid = request.headers.get('x-user-id');
  const sessionId = request.headers.get('x-session-id');
  if (!uid) {
    return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
  }
  if (!sessionId) {
    return new Response('missing x-session-id', { status: 400, headers: CORS_HEADERS });
  }
  const chunk = await request.arrayBuffer();
  const bucket = resolveUserDataBucket(request, env);
  const geo = extractGeoMetadata(request);

  const bodyText = await readRequestBody(request, chunk);
  const lines = bodyText
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const sessions = new Map();
  const legacyLines = [];
  const trainingProfileDelta = createTrainingProfileDelta();
  for (const line of lines) {
    let data;
    try {
      data = JSON.parse(line);
      data = enrichLogEventWithGeo(data, geo);
    } catch (_) {
      legacyLines.push(line);
      continue;
    }
    const normalizedLine = JSON.stringify(data);
    legacyLines.push(normalizedLine);
    const tsMs = parseTsMs(data.ts);
    const sid = data.session || data.session_id;
    collectTrainingProfileDelta(trainingProfileDelta, data, tsMs);
    if (tsMs == null || !sid) continue;
    if (!sessions.has(sid)) {
      sessions.set(sid, { events: [], rawLines: [] });
    }
    const entry = sessions.get(sid);
    entry.events.push({ tsMs, type: data.type });
    entry.rawLines.push(normalizedLine);
  }

  for (const [sid, entry] of sessions.entries()) {
    const state = await loadSessionState(bucket, uid, sid);
    const sorted = entry.events.sort((a, b) => a.tsMs - b.tsMs);
    if (sorted.length === 0) continue;
    const sessionStartMs = resolveSessionStartMs(sorted, state);
    const dayKey = state.dayKey || dayKeyFromMs(sessionStartMs);
    const activeSeconds = computeActiveSeconds(
      sorted,
      state.lastTsMs,
      SUMMARY_IDLE_CAP_SECONDS
    );
    const hasNonStart = sorted.some((e) => e.type && e.type !== 'session_start');
    const addBonus = hasNonStart && !state.bonusApplied;
    const bonus = addBonus ? SUMMARY_START_BONUS_SECONDS : 0;
    const runCount = sorted.filter((e) => e.type === 'trial_result' || e.type === 'naming_result').length;
    const shouldCountSession = !state.countedSession;
    await appendRawSession(bucket, uid, dayKey, sid, entry.rawLines);
    await updateUserSummary(bucket, uid, dayKey, activeSeconds + bonus, runCount, shouldCountSession ? 1 : 0, sorted[sorted.length - 1].tsMs);
    await saveSessionState(bucket, uid, sid, {
      sessionStartMs,
      dayKey,
      lastTsMs: sorted[sorted.length - 1].tsMs,
      bonusApplied: state.bonusApplied || addBonus,
      countedSession: state.countedSession || shouldCountSession,
    });
  }

  await updateUserGeoProfile(bucket, uid, geo, sessionId);
  await updateUserTrainingProfile(bucket, uid, trainingProfileDelta, sessionId);

  // Keep legacy gzip log for audit/debug (optional).
  await appendLegacyRun(bucket, uid, sessionId, legacyLines, chunk);

  return new Response('ok', { status: 200, headers: CORS_HEADERS });
}

// ---------- /audio-target-matches ----------
const AUDIO_MATCH_MAX_BYTES = 5 * 1024 * 1024; // rotate around 5MB (compressed)

async function handleAudioTargetMatches(request, env) {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const uid = request.headers.get('x-user-id');
  const sessionId = request.headers.get('x-session-id');
  if (!uid) {
    return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
  }
  if (!sessionId) {
    return new Response('missing x-session-id', { status: 400, headers: CORS_HEADERS });
  }
  const chunk = await request.arrayBuffer();
  const key = `${uid}/audio_target_matches/${sessionId}.ndjson.gz`;
  const bucket = resolveUserDataBucket(request, env);

  const existing = await bucket.get(key);
  if (!existing) {
    await bucket.put(key, chunk, { httpMetadata: { contentType: 'application/gzip' } });
    return new Response('ok', { status: 200, headers: CORS_HEADERS });
  }

  const oldBytes = await existing.arrayBuffer();
  const total = oldBytes.byteLength + chunk.byteLength;
  if (total > AUDIO_MATCH_MAX_BYTES) {
    const stamp = new Date().toISOString().replace(/[:.]/g, '').replace('T', '-').replace('Z', '');
    const rotatedKey = `${uid}/audio_target_matches/${sessionId}-${stamp}.ndjson.gz`;
    await bucket.copy(key, rotatedKey);
    await bucket.put(key, chunk, { httpMetadata: { contentType: 'application/gzip' } });
    return new Response('ok-rotated', { status: 200, headers: CORS_HEADERS });
  }

  const merged = new Uint8Array(total);
  merged.set(new Uint8Array(oldBytes), 0);
  merged.set(new Uint8Array(chunk), oldBytes.byteLength);
  await bucket.put(key, merged.buffer, { httpMetadata: { contentType: 'application/gzip' } });
  return new Response('ok', { status: 200, headers: CORS_HEADERS });
}

// ---------- /summary ----------
async function handleSummary(request, env) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const uid = request.headers.get('x-user-id');
  if (!uid) {
    return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
  }
  const url = new URL(request.url);
  const from = url.searchParams.get('from');
  const to = url.searchParams.get('to');
  if (!from || !to) {
    return new Response('missing from/to', { status: 400, headers: CORS_HEADERS });
  }
  const fromDate = parseDateKey(from);
  const toDate = parseDateKey(to);
  if (!fromDate || !toDate || fromDate > toDate) {
    return new Response('invalid range', { status: 400, headers: CORS_HEADERS });
  }
  const bucket = resolveUserDataBucket(request, env);
  const days = [];
  const cursor = new Date(Date.UTC(fromDate.getUTCFullYear(), fromDate.getUTCMonth(), fromDate.getUTCDate()));
  const end = new Date(Date.UTC(toDate.getUTCFullYear(), toDate.getUTCMonth(), toDate.getUTCDate()));
  while (cursor <= end) {
    const key = dateKey(cursor);
    const obj = await bucket.get(`${uid}/summary/${key}.json`);
    if (obj) {
      try {
        const payload = await obj.json();
        days.push({ date: key, ...payload });
      } catch (_) {
        // ignore parse errors
      }
    }
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  const body = JSON.stringify({ userId: uid, from, to, days });
  if (request.method === 'HEAD') {
    return new Response(null, { status: 200, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } });
  }
  return new Response(body, { status: 200, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } });
}

// ---------- /user-curriculum ----------
async function handleCurriculum(request, env) {
  const url = new URL(request.url);
  const uid = url.searchParams.get('uid');
  const start = url.searchParams.get('start') || 'start_curriculum_a.json';
  if (!uid) {
    return new Response('missing uid', { status: 400 });
  }
  const bucket = resolveUserDataBucket(request, env);
  const primaryKey = `${uid}/curriculum_delta.json`;
  const fallbackKey = `${uid}/${start}.delta.json`;

  if (request.method === 'GET') {
    const obj = await bucket.get(primaryKey) || (await bucket.get(fallbackKey));
    if (!obj) return new Response('not found', { status: 404 });
    return new Response(obj.body, {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  }

  if (request.method === 'POST') {
    const body = await request.json().catch(() => null);
    if (!body || !body.delta) {
      return new Response('invalid body', { status: 400 });
    }
    const delta = JSON.stringify(body.delta);
    await bucket.put(primaryKey, delta, { httpMetadata: { contentType: 'application/json' } });
    await bucket.put(fallbackKey, delta, { httpMetadata: { contentType: 'application/json' } });
    return new Response('saved', { status: 200 });
  }

  return new Response('method not allowed', { status: 405 });
}

// ---------- /resume-state ----------
async function handleResumeState(request, env) {
  const uid = request.headers.get('x-user-id');
  if (!uid) {
    return new Response('missing x-user-id', { status: 400 });
  }
  const bucket = resolveUserDataBucket(request, env);
  const key = `${uid}/resume_state.json`;

  if (request.method === 'GET') {
    const obj = await bucket.get(key);
    if (!obj) return new Response('not found', { status: 404, headers: CORS_HEADERS });
    return new Response(obj.body, {
      status: 200,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    });
  }

  if (request.method === 'POST') {
    const body = await request.json().catch(() => null);
    if (!body) {
      return new Response('invalid body', { status: 400, headers: CORS_HEADERS });
    }
    const payload = JSON.stringify(body);
    await bucket.put(key, payload, { httpMetadata: { contentType: 'application/json' } });
    return new Response('saved', { status: 200, headers: CORS_HEADERS });
  }

  return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
}

// ---------- /consent ----------
async function handleConsent(request, env) {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const body = await readJsonBody(request);
  if (!body) {
    return new Response('invalid body', { status: 400, headers: CORS_HEADERS });
  }
  const uid = resolveUserId(request, body);
  if (!uid) {
    return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
  }
  const bucket = resolveSupervisorDashboardBucket(env);
  const now = new Date().toISOString();
  const key = consentKey(uid);
  const previous = await getJsonObject(bucket, key);
  const monitoringOn = body.monitoring_on === true;
  const internalName = cleanOptionalString(body.internal_name, 128);
  const comment = cleanOptionalString(body.comment, 1024);
  const uiLanguage = cleanOptionalString(body.ui_language, 32);
  const next = {
    userId: uid,
    monitoringOn,
    textVersion: cleanOptionalString(body.text_version, 64) || 'trial_v1',
    internalName,
    comment,
    uiLanguage,
    consentedAt: monitoringOn ? previous?.consentedAt || now : previous?.consentedAt || null,
    revokedAt: monitoringOn ? null : now,
    updatedAt: now,
  };
  await putJsonObject(bucket, key, next);
  if (!monitoringOn) {
    const pairing = await getJsonObject(bucket, pairingKey(uid));
    if (pairing && pairing.active) {
      pairing.active = false;
      pairing.updatedAt = now;
      await putJsonObject(bucket, pairingKey(uid), pairing);
      await removeLearnerFromSupervisorIndex(bucket, uid, pairing);
    }
  }
  return jsonResponse({ ok: true, consent: next });
}

// ---------- /pair ----------
async function handlePair(request, env) {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const body = await readJsonBody(request);
  if (!body) {
    return new Response('invalid body', { status: 400, headers: CORS_HEADERS });
  }
  const uid = resolveUserId(request, body);
  if (!uid) {
    return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
  }
  const bucket = resolveSupervisorDashboardBucket(env);
  const consent = await getJsonObject(bucket, consentKey(uid));
  if (!consent || consent.monitoringOn !== true) {
    return jsonResponse(
      { ok: false, error: 'consent_required', message: 'consent monitoring_on=true required' },
      409
    );
  }
  const emailRaw = String(body.supervisor_email || '').trim();
  const codeRaw = normalizeSupervisorCode(body.supervisor_code_5 || body.supervisor_code);
  if (!emailRaw) {
    return jsonResponse({ ok: false, error: 'missing_supervisor_email' }, 400);
  }
  if (codeRaw.length !== 5) {
    return jsonResponse({ ok: false, error: 'invalid_supervisor_code', expectedLength: 5 }, 400);
  }

  const now = new Date().toISOString();
  const previous = await getJsonObject(bucket, pairingKey(uid));
  const internalName = cleanOptionalString(body.internal_name, 128);
  const comment = cleanOptionalString(body.comment, 1024);
  const uiLanguage = cleanOptionalString(body.ui_language, 32);
  const emailNormalized = emailRaw.toLowerCase();
  const supervisorCodeHash = await sha256Hex(codeRaw);
  const supervisorEmailHash = await sha256Hex(emailNormalized);
  const resolvedSupervisorName =
    cleanOptionalString(body.print_name, 128) ||
    cleanOptionalString(body.printName, 128) ||
    cleanOptionalString(body.displayName, 128) ||
    cleanOptionalString(body.supervisor_display_name, 128) ||
    cleanOptionalString(body.display_name, 128) ||
    cleanOptionalString(previous?.displayName, 128) ||
    cleanOptionalString(previous?.registrationName, 128) ||
    cleanOptionalString(previous?.display_name, 128) ||
    (await resolveSupervisorDisplayNameByIdentity(
      bucket,
      supervisorEmailHash,
      supervisorCodeHash
    ));
  const next = {
    userId: uid,
    active: true,
    supervisorEmailNormalized: emailNormalized,
    supervisorEmailHash,
    supervisorEmailMasked: maskEmail(emailRaw),
    supervisorCodeHash,
    supervisorCodeLast2: codeRaw.slice(-2),
    internalName,
    comment,
    uiLanguage,
    displayName: resolvedSupervisorName || null,
    registrationName: resolvedSupervisorName || null,
    display_name: resolvedSupervisorName || null,
    linkedAt: previous?.linkedAt || now,
    updatedAt: now,
  };
  await putJsonObject(bucket, pairingKey(uid), next);
  await moveLearnerBetweenSupervisorIndexes(bucket, uid, previous, next);

  return jsonResponse({
    ok: true,
    pairing: {
      userId: next.userId,
      active: next.active,
      supervisorEmailMasked: next.supervisorEmailMasked,
      supervisorCodeLast2: next.supervisorCodeLast2,
      displayName: next.displayName,
      registrationName: next.registrationName,
      display_name: next.display_name,
      linkedAt: next.linkedAt,
      updatedAt: next.updatedAt,
    },
  });
}

// ---------- /emoji-queue ----------
async function handleEmojiQueue(request, env) {
  if (request.method !== 'GET' && request.method !== 'POST' && request.method !== 'DELETE') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const url = new URL(request.url);
  if (request.method === 'GET') {
    const uid = resolveUserId(request, null) || cleanOptionalString(url.searchParams.get('uid'), 128);
    if (!uid) {
      return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
    }
    const bucket = resolveSupervisorDashboardBucket(env);
    return await getEmojiQueue(request, bucket, uid, url);
  }
  if (request.method === 'DELETE') {
    const body = await readJsonBody(request);
    const uid = resolveUserId(request, body);
    if (!uid) {
      return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
    }
    const bucket = resolveSupervisorDashboardBucket(env);
    const queue = await loadEmojiQueue(bucket, uid);
    queue.items = [];
    queue.updatedAt = new Date().toISOString();
    await saveEmojiQueue(bucket, uid, queue);
    return jsonResponse({
      ok: true,
      userId: uid,
      queue: summarizeEmojiQueue(queue),
    });
  }
  const body = await readJsonBody(request);
  if (!body) {
    return new Response('invalid body', { status: 400, headers: CORS_HEADERS });
  }
  const uid = resolveUserId(request, body);
  if (!uid) {
    return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
  }
  const bucket = resolveSupervisorDashboardBucket(env);
  const source = cleanOptionalString(body.source, 64) || 'app';
  const fallbackReason = cleanOptionalString(body.reason, 64);
  const fallbackNote = cleanOptionalString(body.note, 512);
  const fallbackMeta = normalizeMeta(body.meta);
  const now = new Date().toISOString();
  const queue = await loadEmojiQueue(bucket, uid);
  const pendingNow = queue.items.filter((item) => item.status === 'pending').length;
  const availablePendingSlots = Math.max(0, EMOJI_QUEUE_MAX_PENDING_ITEMS - pendingNow);

  const rawItems = Array.isArray(body.items) ? body.items : [body];
  const candidates = [];
  for (const raw of rawItems) {
    const emoji = cleanOptionalString(raw?.emoji, 16);
    if (!emoji) continue;
    const reason = cleanOptionalString(raw?.reason, 64) || fallbackReason;
    const note = cleanOptionalString(raw?.note, 512) || fallbackNote;
    const meta = normalizeMeta(raw?.meta) || fallbackMeta;
    const priority = normalizePriority(raw?.priority);
    candidates.push({
      id: crypto.randomUUID(),
      emoji,
      status: 'pending',
      source: cleanOptionalString(raw?.source, 64) || source,
      reason,
      note,
      priority,
      meta,
      // Use server timestamp to keep queue ordering deterministic.
      createdAt: now,
      updatedAt: now,
      consumedAt: null,
    });
  }
  if (candidates.length === 0) {
    return jsonResponse(
      { ok: false, error: 'no_valid_items', message: 'provide emoji or items[].emoji' },
      400
    );
  }
  const accepted = candidates.slice(0, availablePendingSlots);
  const rejectedDueToPendingLimit = Math.max(0, candidates.length - accepted.length);
  if (accepted.length === 0) {
    return jsonResponse(
      {
        ok: false,
        error: 'pending_queue_limit_reached',
        message: `maximum ${EMOJI_QUEUE_MAX_PENDING_ITEMS} pending queue items per learner`,
        maxPending: EMOJI_QUEUE_MAX_PENDING_ITEMS,
        currentPending: pendingNow,
        rejectedDueToPendingLimit,
      },
      409
    );
  }

  queue.items.push(...accepted);
  trimEmojiQueue(queue);
  queue.updatedAt = now;
  await saveEmojiQueue(bucket, uid, queue);

  return jsonResponse({
    ok: true,
    userId: uid,
    accepted: accepted.length,
    rejectedDueToPendingLimit,
    pendingLimit: EMOJI_QUEUE_MAX_PENDING_ITEMS,
    limitReached: rejectedDueToPendingLimit > 0,
    queue: summarizeEmojiQueue(queue),
  });
}

// ---------- /emoji-queue-ack ----------
async function handleEmojiQueueAck(request, env) {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const body = await readJsonBody(request);
  if (!body) {
    return new Response('invalid body', { status: 400, headers: CORS_HEADERS });
  }
  const uid = resolveUserId(request, body);
  if (!uid) {
    return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
  }
  const bucket = resolveSupervisorDashboardBucket(env);
  const ids = Array.isArray(body.ids) ? body.ids.map((v) => String(v)) : [];
  if (ids.length === 0) {
    return jsonResponse({ ok: false, error: 'missing_ids' }, 400);
  }
  const now = new Date().toISOString();
  const queue = await loadEmojiQueue(bucket, uid);
  const idSet = new Set(ids);
  const mode = body.mode === 'remove' ? 'remove' : 'status';
  const nextStatus = mode === 'status' ? normalizeStatus(body.status) || 'delivered' : null;
  let changed = 0;
  let rejectedDueToPendingLimit = 0;
  let pendingCount = queue.items.filter((item) => item.status === 'pending').length;
  if (mode === 'remove') {
    const before = queue.items.length;
    queue.items = queue.items.filter((item) => !idSet.has(item.id));
    changed = before - queue.items.length;
  } else {
    for (const item of queue.items) {
      if (!idSet.has(item.id)) continue;
      const previousStatus = item.status;
      if (
        nextStatus === 'pending' &&
        previousStatus !== 'pending' &&
        pendingCount >= EMOJI_QUEUE_MAX_PENDING_ITEMS
      ) {
        rejectedDueToPendingLimit += 1;
        continue;
      }
      item.status = nextStatus;
      item.updatedAt = now;
      if (nextStatus !== 'pending') {
        item.consumedAt = item.consumedAt || now;
      }
      if (previousStatus === 'pending' && nextStatus !== 'pending') {
        pendingCount = Math.max(0, pendingCount - 1);
      } else if (previousStatus !== 'pending' && nextStatus === 'pending') {
        pendingCount += 1;
      }
      changed += 1;
    }
  }
  trimEmojiQueue(queue);
  queue.updatedAt = now;
  await saveEmojiQueue(bucket, uid, queue);
  return jsonResponse({
    ok: true,
    userId: uid,
    changed,
    rejectedDueToPendingLimit,
    pendingLimit: EMOJI_QUEUE_MAX_PENDING_ITEMS,
    queue: summarizeEmojiQueue(queue),
  });
}

// ---------- /dashboard-info ----------
async function handleDashboardInfo(request, env) {
  if (request.method !== 'GET') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const url = new URL(request.url);
  const uid = resolveUserId(request, null) || cleanOptionalString(url.searchParams.get('uid'), 128);
  if (!uid) {
    return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
  }
  const bucket = resolveSupervisorDashboardBucket(env);
  const [consent, pairing, queue, resume, registration] = await Promise.all([
    getJsonObject(bucket, consentKey(uid)),
    getJsonObject(bucket, pairingKey(uid)),
    loadEmojiQueue(bucket, uid),
    getJsonObject(bucket, `${uid}/resume_state.json`),
    loadSupervisorRegistration(bucket, uid),
  ]);
  const queueSummary = summarizeEmojiQueue(queue);
  const recent = recentPending(queue.items, 8);
  const resumeInfo = summarizeResumeState(resume);
  let displayName = resolveSupervisorRegistrationName({
    pairing,
    consent,
    registration,
  });
  if (!displayName) {
    displayName = await resolveSupervisorDisplayNameFromPairingIdentity(
      bucket,
      pairing
    );
  }
  if (
    displayName &&
    pairing &&
    !firstNonEmptyString(
      pairing.displayName,
      pairing.registrationName,
      pairing.display_name
    )
  ) {
    pairing.displayName = displayName;
    pairing.registrationName = displayName;
    pairing.display_name = displayName;
    pairing.updatedAt = new Date().toISOString();
    await putJsonObject(bucket, pairingKey(uid), pairing);
  }
  return jsonResponse({
    ok: true,
    userId: uid,
    generatedAt: new Date().toISOString(),
    supervisor: {
      paired: !!pairing?.active,
      active: !!pairing?.active,
      supervisorEmailMasked: pairing?.supervisorEmailMasked || null,
      supervisorEmail: pairing?.supervisorEmailNormalized || null,
      email: pairing?.supervisorEmailNormalized || null,
      supervisorCodeLast2: pairing?.supervisorCodeLast2 || null,
      linkedAt: pairing?.linkedAt || null,
      updatedAt: pairing?.updatedAt || null,
      displayName: displayName || null,
      registrationName: displayName || null,
      display_name: displayName || null,
      internalName: pairing?.internalName || consent?.internalName || null,
      comment: pairing?.comment || consent?.comment || null,
      uiLanguage: pairing?.uiLanguage || consent?.uiLanguage || null,
    },
    consent: {
      monitoringOn: consent?.monitoringOn === true,
      textVersion: consent?.textVersion || null,
      consentedAt: consent?.consentedAt || null,
      revokedAt: consent?.revokedAt || null,
      updatedAt: consent?.updatedAt || null,
    },
    emojiQueue: {
      ...queueSummary,
      itemsPreview: recent,
      recommendedSort: ['status', '-priority', 'createdAt'],
    },
    resumeState: resumeInfo,
    dashboardHints: {
      queuePollingMs: DASHBOARD_QUEUE_POLLING_MS,
      queueAckEndpoint: '/api/emoji-queue-ack',
      queueReadEndpoint: '/api/emoji-queue?status=pending&limit=50',
      apkLatestEndpoint: '/api/android-release/latest?flavor=dailywords',
      apkDownloadEndpoint: '/api/android-release/download?flavor=dailywords&source=dashboard',
      apkDownloadStatsEndpoint:
        '/api/android-release/download-stats?flavor=dailywords&from=YYYY-MM-DD&to=YYYY-MM-DD',
      dataContractVersion: 3,
    },
  });
}

// ---------- /learner-profile ----------
// Enriched per-learner profile for dashboard backends.
async function handleLearnerProfile(request, env) {
  if (request.method !== 'GET') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const url = new URL(request.url);
  const uid = resolveUserId(request, null) || cleanOptionalString(url.searchParams.get('uid'), 128);
  if (!uid) {
    return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
  }
  const bucket = resolveUserDataBucket(request, env);
  const learner = await enrichSupervisorLearner(bucket, {
    userId: uid,
    active: true,
    linkedAt: null,
    updatedAt: null,
    internalName: null,
    comment: null,
    uiLanguage: null,
  });
  return jsonResponse({
    ok: true,
    userId: uid,
    generatedAt: new Date().toISOString(),
    profile: {
      l1: learner?.l1 ?? null,
      l2: learner?.l2 ?? null,
      country_code: learner?.country_code ?? null,
      region_code: learner?.region_code ?? null,
      region: learner?.region ?? null,
      city: learner?.city ?? null,
      module: learner?.module ?? null,
      module_label: learner?.module_label ?? null,
      module_raw: learner?.module_raw ?? null,
      wins_you: learner?.wins_you ?? null,
      wins_rival: learner?.wins_rival ?? null,
      victories: learner?.victories ?? null,
      defeats: learner?.defeats ?? null,
      item_ids: Array.isArray(learner?.item_ids) ? learner.item_ids : [],
      item_count: learner?.item_count ?? 0,
      items: Array.isArray(learner?.items) ? learner.items : [],
      resume_state: learner?.resume_state ?? null,
    },
  });
}

// ---------- /supervisor-users ----------
// Canonical learner listing for a supervisor identity (email + code).
// Reads only DailyWords supervisor data.
async function handleSupervisorUsers(request, env) {
  if (request.method !== 'GET') {
    return new Response('method not allowed', { status: 405, headers: CORS_HEADERS });
  }
  const url = new URL(request.url);
  const emailRaw =
    cleanOptionalString(request.headers.get('x-supervisor-email'), 256) ||
    cleanOptionalString(url.searchParams.get('supervisor_email'), 256) ||
    cleanOptionalString(url.searchParams.get('email'), 256);
  const codeRawRaw =
    cleanOptionalString(request.headers.get('x-supervisor-code'), 64) ||
    cleanOptionalString(url.searchParams.get('supervisor_code'), 64) ||
    cleanOptionalString(url.searchParams.get('code'), 64);
  const codeRaw = normalizeSupervisorCode(codeRawRaw);
  if (!emailRaw || !codeRaw) {
    return jsonResponse(
      { ok: false, error: 'missing_supervisor_credentials', message: 'provide supervisor_email and supervisor_code' },
      400
    );
  }
  if (!/^[A-Za-z0-9]{5}$/.test(codeRaw)) {
    return jsonResponse({ ok: false, error: 'invalid_supervisor_code', expectedLength: 5 }, 400);
  }
  if (!emailRaw.includes('@')) {
    return jsonResponse({ ok: false, error: 'invalid_supervisor_email' }, 400);
  }
  const bucket = resolveSupervisorDashboardBucket(env);
  const emailNormalized = emailRaw.toLowerCase();
  const emailHash = await sha256Hex(emailNormalized);
  const codeHash = await sha256Hex(codeRaw);
  let index = await loadSupervisorIndex(bucket, emailHash, codeHash);
  if (Object.keys(index.learners).length === 0) {
    index = await rebuildSupervisorIndexFromPairings(bucket, emailHash, codeHash);
  }
  const rawLearners = Object.values(index.learners).sort((a, b) =>
    Date.parse(b.updatedAt || b.linkedAt || 0) - Date.parse(a.updatedAt || a.linkedAt || 0)
  );
  const learners = await Promise.all(rawLearners.map((learner) => enrichSupervisorLearner(bucket, learner)));
  return jsonResponse({
    ok: true,
    supervisor: {
      emailMasked: maskEmail(emailRaw),
      codeLast2: codeRaw.slice(-2),
      learnerCount: learners.length,
      updatedAt: index.updatedAt || null,
    },
    learners,
  });
}

async function readRequestBody(request, chunk) {
  const encoding = request.headers.get('content-encoding');
  if (encoding && encoding.toLowerCase() === 'gzip') {
    try {
      const ds = new DecompressionStream('gzip');
      const stream = new Response(chunk).body.pipeThrough(ds);
      return await new Response(stream).text();
    } catch (_) {
      // fall through to plain decode
    }
  }
  return new TextDecoder().decode(chunk);
}

async function readJsonBody(request) {
  try {
    return await request.json();
  } catch (_) {
    return null;
  }
}

function extractGeoMetadata(request) {
  const cf = request.cf || {};
  const countryCode = cleanCountryCode(
    cf.country ||
      request.headers.get('cf-ipcountry') ||
      request.headers.get('x-vercel-ip-country') ||
      request.headers.get('x-country-code')
  );
  const regionCode = cleanOptionalString(cf.regionCode, 32);
  const region = cleanOptionalString(cf.region, 128);
  const city = cleanOptionalString(cf.city, 128);
  const continent = cleanOptionalString(cf.continent, 32);
  const timezone = cleanOptionalString(cf.timezone, 64);
  const colo = cleanOptionalString(cf.colo, 32);
  return {
    country_code: countryCode,
    region_code: regionCode,
    region,
    city,
    continent,
    timezone,
    colo,
    source: cf && Object.keys(cf).length > 0 ? 'cf' : 'header',
  };
}

function enrichLogEventWithGeo(event, geo) {
  if (!event || typeof event !== 'object' || Array.isArray(event)) return event;
  const enriched = { ...event };
  if (!cleanCountryCode(enriched.country_code || enriched.cc) && geo.country_code) {
    enriched.country_code = geo.country_code;
  }
  if (!cleanOptionalString(enriched.region_code, 32) && geo.region_code) {
    enriched.region_code = geo.region_code;
  }
  if (!cleanOptionalString(enriched.region, 128) && geo.region) {
    enriched.region = geo.region;
  }
  if (!cleanOptionalString(enriched.city, 128) && geo.city) {
    enriched.city = geo.city;
  }
  if (!cleanOptionalString(enriched.continent, 32) && geo.continent) {
    enriched.continent = geo.continent;
  }
  if (!cleanOptionalString(enriched.timezone, 64) && geo.timezone) {
    enriched.timezone = geo.timezone;
  }
  if (!cleanOptionalString(enriched.colo, 32) && geo.colo) {
    enriched.colo = geo.colo;
  }
  if (!cleanOptionalString(enriched.geo_source, 32) && geo.source) {
    enriched.geo_source = geo.source;
  }
  return enriched;
}

function createTrainingProfileDelta() {
  return {
    l1: null,
    l2: null,
    moduleRaw: null,
    winsYouDelta: 0,
    winsRivalDelta: 0,
    runEvents: 0,
    itemIds: [],
    _itemIdSet: new Set(),
    lastEventTsMs: null,
  };
}

function collectTrainingProfileDelta(delta, event, tsMs) {
  if (!delta || !event || typeof event !== 'object' || Array.isArray(event)) return;
  const l1 = firstNonEmptyString(event.l1, event.native, event.nativeLang, event.native_lang);
  const l2 = firstNonEmptyString(event.l2, event.lang, event.language, event.l2Lang, event.l2_lang);
  const moduleRaw = firstNonEmptyString(
    event.module,
    event.module_raw,
    event.start_key,
    event.startKey
  );
  if (l1) delta.l1 = cleanOptionalString(l1, 32) || delta.l1;
  if (l2) delta.l2 = cleanOptionalString(l2, 32) || delta.l2;
  if (moduleRaw) delta.moduleRaw = cleanOptionalString(moduleRaw, 128) || delta.moduleRaw;

  const type = cleanOptionalString(event.type, 64);
  if (type === 'trial_result' || type === 'naming_result') {
    delta.runEvents += 1;
  }
  if (type === 'win') {
    const side = cleanOptionalString(event.side || event.winner, 32)?.toLowerCase();
    if (side === 'you') delta.winsYouDelta += 1;
    if (side === 'rival') delta.winsRivalDelta += 1;
  }

  const itemId = cleanOptionalString(event.item_id || event.uuid, 128);
  if (itemId && !delta._itemIdSet.has(itemId)) {
    delta._itemIdSet.add(itemId);
    delta.itemIds.push(itemId);
  }

  if (Number.isFinite(tsMs)) {
    delta.lastEventTsMs = Math.max(Number(delta.lastEventTsMs || 0), Math.floor(tsMs));
  }
}

function toNonNegativeInt(raw) {
  const value = Number(raw);
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.floor(value));
}

function mergeRecentItemIds(previousRaw, incomingRaw, maxItems = TRAINING_PROFILE_MAX_ITEMS) {
  const out = [];
  const seen = new Set();
  const apply = (raw) => {
    const id = cleanOptionalString(raw, 128);
    if (!id) return;
    const existingIdx = out.indexOf(id);
    if (existingIdx >= 0) {
      out.splice(existingIdx, 1);
    } else {
      seen.add(id);
    }
    out.push(id);
    while (out.length > maxItems) {
      const removed = out.shift();
      if (removed) seen.delete(removed);
    }
  };
  if (Array.isArray(previousRaw)) {
    for (const raw of previousRaw) apply(raw);
  }
  if (Array.isArray(incomingRaw)) {
    for (const raw of incomingRaw) apply(raw);
  }
  return out;
}

function moduleDisplayName(raw) {
  const value = cleanOptionalString(raw, 128);
  if (!value) return null;
  const lowered = value.toLowerCase();
  if (lowered === 'start_curriculum_a' || lowered === 'start_curriculum_a.json') {
    return 'Daily Words';
  }
  if (lowered === 'start_curriculum_b' || lowered === 'start_curriculum_b.json') {
    return 'Foundational Words';
  }
  return value;
}

async function updateUserTrainingProfile(bucket, uid, delta, sessionId) {
  if (!bucket || !uid || !delta || typeof delta !== 'object') return;
  const key = `${uid}/profile/training.json`;
  const previous = (await getJsonObject(bucket, key)) || {};
  const now = new Date().toISOString();

  const l1 = cleanOptionalString(delta.l1, 32) || cleanOptionalString(previous.l1, 32) || null;
  const l2 = cleanOptionalString(delta.l2, 32) || cleanOptionalString(previous.l2, 32) || null;
  const moduleRaw =
    cleanOptionalString(delta.moduleRaw, 128) ||
    cleanOptionalString(previous.module_raw, 128) ||
    cleanOptionalString(previous.module, 128) ||
    null;
  const moduleLabel = moduleDisplayName(moduleRaw) || cleanOptionalString(previous.module_label, 128) || null;
  const mergedItems = mergeRecentItemIds(previous.itemIds, delta.itemIds);

  const winsYou = toNonNegativeInt(previous.winsYou) + toNonNegativeInt(delta.winsYouDelta);
  const winsRival = toNonNegativeInt(previous.winsRival) + toNonNegativeInt(delta.winsRivalDelta);
  const runsSeen = toNonNegativeInt(previous.runsSeen) + toNonNegativeInt(delta.runEvents);

  const previousLastTs = Number(previous.lastEventTsMs);
  const deltaLastTs = Number(delta.lastEventTsMs);
  const lastEventTsMs = Math.max(
    Number.isFinite(previousLastTs) ? Math.floor(previousLastTs) : 0,
    Number.isFinite(deltaLastTs) ? Math.floor(deltaLastTs) : 0
  );

  const next = {
    userId: uid,
    l1,
    l2,
    module_raw: moduleRaw,
    module_label: moduleLabel,
    module: moduleLabel || moduleRaw || null,
    winsYou,
    winsRival,
    runsSeen,
    itemIds: mergedItems,
    itemCount: mergedItems.length,
    lastItemId: mergedItems.length > 0 ? mergedItems[mergedItems.length - 1] : null,
    lastSessionId:
      cleanOptionalString(sessionId, 128) || cleanOptionalString(previous.lastSessionId, 128) || null,
    lastEventTsMs: lastEventTsMs > 0 ? lastEventTsMs : null,
    updatedAt: now,
  };
  await putJsonObject(bucket, key, next);
}

function resolveUserId(request, body) {
  const fromHeader = cleanOptionalString(request.headers.get('x-user-id'), 128);
  if (fromHeader) return fromHeader;
  if (!body || typeof body !== 'object') return null;
  return (
    cleanOptionalString(body.userId, 128) ||
    cleanOptionalString(body.learnerId, 128) ||
    cleanOptionalString(body.uid, 128)
  );
}

function cleanOptionalString(raw, maxLen = 256) {
  if (raw == null) return null;
  const value = String(raw).trim();
  if (!value) return null;
  return value.slice(0, maxLen);
}

function cleanCountryCode(raw) {
  const value = cleanOptionalString(raw, 16);
  if (!value) return null;
  const upper = value.toUpperCase();
  if (!/^[A-Z0-9]{2,8}$/.test(upper)) return null;
  return upper;
}

function normalizePriority(raw) {
  const value = Number(raw);
  if (!Number.isFinite(value)) return 0;
  return Math.max(-10, Math.min(10, Math.round(value)));
}

function normalizeStatus(raw) {
  const value = cleanOptionalString(raw, 32);
  if (!value) return null;
  const lowered = value.toLowerCase();
  if (lowered === 'pending' || lowered === 'delivered' || lowered === 'archived') {
    return lowered;
  }
  return null;
}

function normalizeMeta(raw) {
  if (raw == null) return null;
  if (typeof raw !== 'object' || Array.isArray(raw)) return null;
  try {
    const clean = JSON.parse(JSON.stringify(raw));
    return clean && typeof clean === 'object' && !Array.isArray(clean) ? clean : null;
  } catch (_) {
    return null;
  }
}

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
  });
}

function consentKey(uid) {
  return `${uid}/supervisor/consent.json`;
}

function pairingKey(uid) {
  return `${uid}/supervisor/pairing.json`;
}

function supervisorRegistrationKey(uid) {
  return `${uid}/supervisor/registration.json`;
}

function supervisorIndexKey(emailHash, codeHash) {
  return `supervisors/${emailHash}/${codeHash}/learners.json`;
}

function emojiQueueKey(uid) {
  return `${uid}/supervisor/emoji_queue.json`;
}

async function getJsonObject(bucket, key) {
  const obj = await bucket.get(key);
  if (!obj) return null;
  try {
    return await obj.json();
  } catch (_) {
    return null;
  }
}

async function putJsonObject(bucket, key, value) {
  await bucket.put(key, JSON.stringify(value), {
    httpMetadata: { contentType: 'application/json' },
  });
}

function emptySupervisorIndex(emailHash, codeHash) {
  return {
    version: 1,
    supervisorEmailHash: emailHash,
    supervisorCodeHash: codeHash,
    updatedAt: null,
    learners: {},
  };
}

function normalizeSupervisorLearner(raw, fallbackUserId = null) {
  if (!raw || typeof raw !== 'object') return null;
  const userId = cleanOptionalString(raw.userId || fallbackUserId, 128);
  if (!userId) return null;
  return {
    userId,
    active: raw.active !== false,
    linkedAt: cleanOptionalString(raw.linkedAt, 64) || null,
    updatedAt: cleanOptionalString(raw.updatedAt, 64) || null,
    internalName: cleanOptionalString(raw.internalName, 128) || null,
    comment: cleanOptionalString(raw.comment, 1024) || null,
    uiLanguage: cleanOptionalString(raw.uiLanguage, 32) || null,
  };
}

async function loadSupervisorIndex(bucket, emailHash, codeHash) {
  const key = supervisorIndexKey(emailHash, codeHash);
  const raw = await getJsonObject(bucket, key);
  const base = emptySupervisorIndex(emailHash, codeHash);
  if (!raw || typeof raw !== 'object') return base;
  const normalized = {
    ...base,
    version: Number(raw.version) || 1,
    updatedAt: cleanOptionalString(raw.updatedAt, 64) || null,
    learners: {},
  };
  const learnersRaw = raw.learners;
  if (Array.isArray(learnersRaw)) {
    for (const item of learnersRaw) {
      const learner = normalizeSupervisorLearner(item);
      if (!learner) continue;
      normalized.learners[learner.userId] = learner;
    }
    return normalized;
  }
  if (!learnersRaw || typeof learnersRaw !== 'object') {
    return normalized;
  }
  for (const [uid, item] of Object.entries(learnersRaw)) {
    const learner = normalizeSupervisorLearner(item, uid);
    if (!learner) continue;
    normalized.learners[learner.userId] = learner;
  }
  return normalized;
}

async function saveSupervisorIndex(bucket, emailHash, codeHash, index) {
  const payload = {
    version: 1,
    supervisorEmailHash: emailHash,
    supervisorCodeHash: codeHash,
    updatedAt: cleanOptionalString(index.updatedAt, 64) || new Date().toISOString(),
    learners: index.learners || {},
  };
  await putJsonObject(bucket, supervisorIndexKey(emailHash, codeHash), payload);
}

async function supervisorIdentityFromPairing(pairing) {
  if (!pairing || typeof pairing !== 'object') return null;
  const codeHash = cleanOptionalString(pairing.supervisorCodeHash, 128);
  if (!codeHash) return null;
  const emailHash =
    cleanOptionalString(pairing.supervisorEmailHash, 128) ||
    (cleanOptionalString(pairing.supervisorEmailNormalized, 256)
      ? await sha256Hex(cleanOptionalString(pairing.supervisorEmailNormalized, 256).toLowerCase())
      : null);
  if (!emailHash) return null;
  return { emailHash, codeHash };
}

async function removeLearnerFromSupervisorIndex(bucket, userId, pairing) {
  const identity = await supervisorIdentityFromPairing(pairing);
  if (!identity) return;
  const index = await loadSupervisorIndex(bucket, identity.emailHash, identity.codeHash);
  if (!index.learners[userId]) return;
  delete index.learners[userId];
  index.updatedAt = new Date().toISOString();
  await saveSupervisorIndex(bucket, identity.emailHash, identity.codeHash, index);
}

async function upsertLearnerInSupervisorIndex(bucket, userId, pairing) {
  const identity = await supervisorIdentityFromPairing(pairing);
  if (!identity) return;
  const now = new Date().toISOString();
  const index = await loadSupervisorIndex(bucket, identity.emailHash, identity.codeHash);
  index.learners[userId] = {
    userId,
    active: pairing?.active !== false,
    linkedAt: cleanOptionalString(pairing?.linkedAt, 64) || now,
    updatedAt: cleanOptionalString(pairing?.updatedAt, 64) || now,
    internalName: cleanOptionalString(pairing?.internalName, 128) || null,
    comment: cleanOptionalString(pairing?.comment, 1024) || null,
    uiLanguage: cleanOptionalString(pairing?.uiLanguage, 32) || null,
  };
  index.updatedAt = now;
  await saveSupervisorIndex(bucket, identity.emailHash, identity.codeHash, index);
}

async function moveLearnerBetweenSupervisorIndexes(bucket, userId, previousPairing, nextPairing) {
  const previousIdentity = await supervisorIdentityFromPairing(previousPairing);
  const nextIdentity = await supervisorIdentityFromPairing(nextPairing);
  if (
    previousIdentity &&
    nextIdentity &&
    previousIdentity.emailHash === nextIdentity.emailHash &&
    previousIdentity.codeHash === nextIdentity.codeHash
  ) {
    await upsertLearnerInSupervisorIndex(bucket, userId, nextPairing);
    return;
  }
  if (previousIdentity) {
    await removeLearnerFromSupervisorIndex(bucket, userId, previousPairing);
  }
  if (nextIdentity) {
    await upsertLearnerInSupervisorIndex(bucket, userId, nextPairing);
  }
}

async function rebuildSupervisorIndexFromPairings(bucket, emailHash, codeHash) {
  const rebuilt = emptySupervisorIndex(emailHash, codeHash);
  const now = new Date().toISOString();
  let cursor = undefined;
  let guard = 0;
  do {
    const page = await bucket.list({ cursor, limit: 1000 });
    const objects = Array.isArray(page?.objects) ? page.objects : [];
    for (const obj of objects) {
      const key = cleanOptionalString(obj?.key, 1024);
      if (!key || !key.endsWith('/supervisor/pairing.json')) continue;
      const uid = cleanOptionalString(key.slice(0, -'/supervisor/pairing.json'.length), 128);
      if (!uid) continue;
      const pairing = await getJsonObject(bucket, key);
      if (!pairing || pairing.active === false) continue;
      const identity = await supervisorIdentityFromPairing(pairing);
      if (!identity) continue;
      if (identity.emailHash !== emailHash || identity.codeHash !== codeHash) continue;
      rebuilt.learners[uid] = {
        userId: uid,
        active: true,
        linkedAt: cleanOptionalString(pairing.linkedAt, 64) || now,
        updatedAt: cleanOptionalString(pairing.updatedAt, 64) || now,
        internalName: cleanOptionalString(pairing.internalName, 128) || null,
        comment: cleanOptionalString(pairing.comment, 1024) || null,
        uiLanguage: cleanOptionalString(pairing.uiLanguage, 32) || null,
      };
    }
    cursor = page?.truncated ? page?.cursor : undefined;
    guard += 1;
  } while (cursor && guard < 200);
  rebuilt.updatedAt = now;
  await saveSupervisorIndex(bucket, emailHash, codeHash, rebuilt);
  return rebuilt;
}

async function loadSupervisorRegistration(bucket, uid) {
  const candidateKeys = [
    supervisorRegistrationKey(uid),
    `${uid}/supervisor/register.json`,
    `${uid}/supervisor_registration.json`,
  ];
  for (const key of candidateKeys) {
    const value = await getJsonObject(bucket, key);
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value;
    }
  }
  return null;
}

async function resolveSupervisorDisplayNameFromPairingIdentity(bucket, pairing) {
  const identity = await supervisorIdentityFromPairing(pairing);
  if (!identity) return null;
  return resolveSupervisorDisplayNameByIdentity(
    bucket,
    identity.emailHash,
    identity.codeHash
  );
}

async function resolveSupervisorDisplayNameByIdentity(
  bucket,
  emailHash,
  codeHash
) {
  if (!emailHash || !codeHash) return null;
  const registration = await loadSupervisorRegistrationByIdentity(
    bucket,
    emailHash,
    codeHash
  );
  if (!registration) return null;
  return resolveSupervisorRegistrationName({
    pairing: null,
    consent: null,
    registration,
  });
}

async function loadSupervisorRegistrationByIdentity(bucket, emailHash, codeHash) {
  const prefix = `supervisors/${emailHash}/${codeHash}`;
  const directKeys = [
    `${prefix}/registration.json`,
    `${prefix}/register.json`,
    `${prefix}/profile.json`,
    `${prefix}/supervisor.json`,
    `${prefix}/account.json`,
    `${prefix}/metadata.json`,
  ];
  for (const key of directKeys) {
    const value = await getJsonObject(bucket, key);
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value;
    }
  }

  const index = await getJsonObject(bucket, supervisorIndexKey(emailHash, codeHash));
  if (index && typeof index === 'object' && !Array.isArray(index)) {
    const nameFromIndex = resolveSupervisorRegistrationName({
      pairing: null,
      consent: null,
      registration: index,
    });
    if (nameFromIndex) return index;
  }

  try {
    const page = await bucket.list({ prefix: `${prefix}/`, limit: 50 });
    const objects = Array.isArray(page?.objects) ? page.objects : [];
    const keys = objects
      .map((obj) => cleanOptionalString(obj?.key, 1024))
      .filter((key) => key && key.endsWith('.json') && !key.endsWith('/learners.json'))
      .sort((a, b) => {
        const score = (key) => (/display|profile|register|supervisor|meta|account/i.test(key) ? 0 : 1);
        return score(a) - score(b);
      });
    for (const key of keys) {
      const value = await getJsonObject(bucket, key);
      if (!value || typeof value !== 'object' || Array.isArray(value)) continue;
      const name = resolveSupervisorRegistrationName({
        pairing: null,
        consent: null,
        registration: value,
      });
      if (name) return value;
    }
  } catch (_) {
    // best-effort lookup
  }
  return null;
}

function resolveSupervisorRegistrationName({ pairing, consent, registration }) {
  return firstNonEmptyString(
    // Canonical contract key:
    registration?.displayName,
    pairing?.displayName,
    consent?.displayName,
    // DailyWords registration page field:
    // "Display name (shown to participants)" -> display_name
    registration?.print_name,
    registration?.printName,
    registration?.profile?.print_name,
    registration?.profile?.printName,
    registration?.display_name,
    registration?.displayName,
    registration?.profile?.display_name,
    registration?.profile?.displayName,
    registration?.participant_display_name,
    registration?.participantDisplayName,
    registration?.registration_name,
    registration?.supervisorName,
    registration?.registeredName,
    registration?.registrationName,
    registration?.name,
    pairing?.supervisor_display_name,
    pairing?.print_name,
    pairing?.printName,
    pairing?.supervisorDisplayName,
    pairing?.display_name,
    pairing?.registration_name,
    pairing?.registrationName,
    pairing?.supervisorName,
    pairing?.name,
    consent?.supervisor_display_name,
    consent?.print_name,
    consent?.printName,
    consent?.supervisorDisplayName,
    consent?.display_name,
    consent?.registration_name,
    consent?.registrationName,
    consent?.supervisorName,
    consent?.name
  );
}

function normalizeSupervisorCode(raw) {
  return String(raw || '').trim().toUpperCase();
}

function firstNonEmptyString(...values) {
  for (const raw of values) {
    const value = cleanOptionalString(raw, 128);
    if (value) return value;
  }
  return null;
}

function emptyEmojiQueue() {
  return {
    version: 1,
    updatedAt: null,
    items: [],
  };
}

async function loadEmojiQueue(bucket, uid) {
  const payload = await getJsonObject(bucket, emojiQueueKey(uid));
  if (!payload || typeof payload !== 'object') {
    return emptyEmojiQueue();
  }
  const items = Array.isArray(payload.items) ? payload.items : [];
  return {
    version: Number(payload.version) || 1,
    updatedAt: cleanOptionalString(payload.updatedAt, 64),
    items: items
      .map((item) => normalizeQueueItem(item))
      .filter((item) => !!item),
  };
}

function normalizeQueueItem(item) {
  if (!item || typeof item !== 'object') return null;
  const id = cleanOptionalString(item.id, 128);
  const emoji = cleanOptionalString(item.emoji, 16);
  if (!id || !emoji) return null;
  const status = normalizeStatus(item.status) || 'pending';
  return {
    id,
    emoji,
    status,
    source: cleanOptionalString(item.source, 64),
    reason: cleanOptionalString(item.reason, 64),
    note: cleanOptionalString(item.note, 512),
    priority: normalizePriority(item.priority),
    meta: normalizeMeta(item.meta),
    createdAt: cleanOptionalString(item.createdAt, 64) || null,
    updatedAt: cleanOptionalString(item.updatedAt, 64) || null,
    consumedAt: cleanOptionalString(item.consumedAt, 64) || null,
  };
}

function trimEmojiQueue(queue) {
  if (!Array.isArray(queue.items)) queue.items = [];
  const pendingItems = queue.items.filter((item) => item.status === 'pending');
  if (pendingItems.length > EMOJI_QUEUE_MAX_PENDING_ITEMS) {
    const keepPendingIds = new Set(
      pendingItems
        .slice()
        .sort((a, b) => {
          const pa = normalizePriority(a.priority);
          const pb = normalizePriority(b.priority);
          if (pa !== pb) return pb - pa;
          const at = Date.parse(a.createdAt || a.updatedAt || 0);
          const bt = Date.parse(b.createdAt || b.updatedAt || 0);
          return bt - at;
        })
        .slice(0, EMOJI_QUEUE_MAX_PENDING_ITEMS)
        .map((item) => item.id)
    );
    queue.items = queue.items.filter(
      (item) => item.status !== 'pending' || keepPendingIds.has(item.id)
    );
  }
  if (queue.items.length <= EMOJI_QUEUE_MAX_ITEMS) return;
  queue.items.sort((a, b) => {
    const as = a.status === 'pending' ? 0 : 1;
    const bs = b.status === 'pending' ? 0 : 1;
    if (as !== bs) return bs - as;
    const at = Date.parse(a.updatedAt || a.createdAt || 0);
    const bt = Date.parse(b.updatedAt || b.createdAt || 0);
    return at - bt;
  });
  while (queue.items.length > EMOJI_QUEUE_MAX_ITEMS) {
    queue.items.shift();
  }
}

async function saveEmojiQueue(bucket, uid, queue) {
  await putJsonObject(bucket, emojiQueueKey(uid), queue);
}

function summarizeEmojiQueue(queue) {
  const total = queue.items.length;
  const pending = queue.items.filter((item) => item.status === 'pending').length;
  const delivered = queue.items.filter((item) => item.status === 'delivered').length;
  const archived = queue.items.filter((item) => item.status === 'archived').length;
  const pendingSlotsRemaining = Math.max(
    0,
    EMOJI_QUEUE_MAX_PENDING_ITEMS - pending
  );
  const latestItem = queue.items
    .slice()
    .sort((a, b) => Date.parse(b.updatedAt || b.createdAt || 0) - Date.parse(a.updatedAt || a.createdAt || 0))[0];
  return {
    version: queue.version,
    updatedAt: queue.updatedAt || null,
    total,
    pending,
    delivered,
    archived,
    pendingLimit: EMOJI_QUEUE_MAX_PENDING_ITEMS,
    pendingSlotsRemaining,
    pendingLimitReached: pending >= EMOJI_QUEUE_MAX_PENDING_ITEMS,
    canEnqueuePending: pending < EMOJI_QUEUE_MAX_PENDING_ITEMS,
    latestEmoji: latestItem?.emoji || null,
    latestEventAt: latestItem?.updatedAt || latestItem?.createdAt || null,
  };
}

async function getEmojiQueue(request, bucket, uid, url) {
  const queue = await loadEmojiQueue(bucket, uid);
  const status = (url.searchParams.get('status') || 'all').toLowerCase();
  const limitRaw = Number(url.searchParams.get('limit') || 50);
  const cursorRaw = Number(url.searchParams.get('cursor') || 0);
  const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(200, Math.floor(limitRaw))) : 50;
  const cursor = Number.isFinite(cursorRaw) ? Math.max(0, Math.floor(cursorRaw)) : 0;

  const filtered = queue.items.filter((item) => status === 'all' || item.status === status);
  filtered.sort((a, b) => {
    const pa = normalizePriority(a.priority);
    const pb = normalizePriority(b.priority);
    if (pa !== pb) return pb - pa;
    const at = Date.parse(a.createdAt || 0);
    const bt = Date.parse(b.createdAt || 0);
    return bt - at;
  });
  const slice = filtered.slice(cursor, cursor + limit);
  return jsonResponse({
    ok: true,
    userId: uid,
    statusFilter: status,
    limit,
    cursor,
    totalFiltered: filtered.length,
    totalInQueue: queue.items.length,
    items: slice,
    queue: summarizeEmojiQueue(queue),
  });
}

function recentPending(items, count) {
  return items
    .filter((item) => item.status === 'pending')
    .sort((a, b) => {
      const aTs = Date.parse(a.updatedAt || a.createdAt || 0);
      const bTs = Date.parse(b.updatedAt || b.createdAt || 0);
      return bTs - aTs;
    })
    .slice(0, count)
    .map((item) => ({
      id: item.id,
      emoji: item.emoji,
      reason: item.reason,
      note: item.note,
      priority: item.priority,
      createdAt: item.createdAt,
      source: item.source,
      status: item.status,
    }));
}

function summarizeResumeState(resume) {
  if (!resume || typeof resume !== 'object') {
    return {
      entriesCount: 0,
      lastEntryDate: null,
      lastStartKey: null,
      lastLang: null,
    };
  }
  const entries = Array.isArray(resume.entries) ? resume.entries : [];
  let latest = null;
  for (const entry of entries) {
    if (!entry || typeof entry !== 'object') continue;
    const date = cleanOptionalString(entry.date, 64);
    if (!date) continue;
    const ts = Date.parse(date);
    if (!Number.isFinite(ts)) continue;
    if (!latest || ts > latest.ts) {
      latest = {
        ts,
        date,
        startKey: cleanOptionalString(entry.startKey, 128),
        lang: cleanOptionalString(entry.lang, 32),
      };
    }
  }
  return {
    entriesCount: entries.length,
    lastEntryDate: latest?.date || null,
    lastStartKey: latest?.startKey || null,
    lastLang: latest?.lang || null,
  };
}

function latestResumeEntry(resume) {
  if (!resume || typeof resume !== 'object') return null;
  const entries = Array.isArray(resume.entries) ? resume.entries : [];
  let latest = null;
  for (const entry of entries) {
    if (!entry || typeof entry !== 'object') continue;
    const date = cleanOptionalString(entry.date, 64);
    if (!date) continue;
    const ts = Date.parse(date);
    if (!Number.isFinite(ts)) continue;
    if (!latest || ts > latest.ts) {
      latest = {
        ts,
        date,
        cursor: Number.isFinite(Number(entry.cursor)) ? Math.max(0, Math.floor(Number(entry.cursor))) : null,
        moduleRaw: cleanOptionalString(entry.startKey || entry.start_key || entry.module, 128),
        l1: cleanOptionalString(entry.l1 || entry.nativeLang || entry.native || entry.native_lang, 32),
        l2: cleanOptionalString(entry.l2 || entry.lang || entry.language, 32),
        winsYou: Number.isFinite(Number(entry.winsYou || entry.wins_you))
          ? Math.max(0, Math.floor(Number(entry.winsYou || entry.wins_you)))
          : null,
        winsRival: Number.isFinite(Number(entry.winsRival || entry.wins_rival))
          ? Math.max(0, Math.floor(Number(entry.winsRival || entry.wins_rival)))
          : null,
      };
    }
  }
  return latest;
}

function normalizeItemIds(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  const seen = new Set();
  for (const value of raw) {
    const id = cleanOptionalString(value, 128);
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
    if (out.length >= TRAINING_PROFILE_MAX_ITEMS) break;
  }
  return out;
}

async function loadRecentItemIdsFromLastSession(bucket, uid, lastSessionId) {
  const sid = cleanOptionalString(lastSessionId, 128);
  if (!sid) return [];
  const sessionState = await getJsonObject(bucket, `${uid}/session_state/${sid}.json`);
  const dayKey = cleanOptionalString(sessionState?.dayKey, 32);
  if (!dayKey) return [];
  const rawObj = await bucket.get(`${uid}/raw/${dayKey}/${sid}.ndjson`);
  if (!rawObj) return [];
  let text = '';
  try {
    text = await rawObj.text();
  } catch (_) {
    return [];
  }
  const out = [];
  const seen = new Set();
  const lines = text.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    let event;
    try {
      event = JSON.parse(trimmed);
    } catch (_) {
      continue;
    }
    const itemId = cleanOptionalString(event?.item_id || event?.uuid, 128);
    if (!itemId || seen.has(itemId)) continue;
    seen.add(itemId);
    out.push(itemId);
    if (out.length >= TRAINING_PROFILE_MAX_ITEMS) break;
  }
  return out;
}

async function enrichSupervisorLearner(bucket, learner) {
  if (!learner || typeof learner !== 'object') return learner;
  const uid = cleanOptionalString(learner.userId, 128);
  if (!uid) return learner;

  const [geoProfile, resumeState, trainingProfile] = await Promise.all([
    getJsonObject(bucket, `${uid}/profile/geo.json`),
    getJsonObject(bucket, `${uid}/resume_state.json`),
    getJsonObject(bucket, `${uid}/profile/training.json`),
  ]);

  const resume = latestResumeEntry(resumeState);
  const l1 = firstNonEmptyString(resume?.l1, trainingProfile?.l1);
  const l2 = firstNonEmptyString(resume?.l2, trainingProfile?.l2);

  const moduleRaw = firstNonEmptyString(
    resume?.moduleRaw,
    trainingProfile?.module_raw,
    trainingProfile?.module
  );
  const moduleLabel =
    moduleDisplayName(moduleRaw) ||
    cleanOptionalString(trainingProfile?.module_label, 128) ||
    cleanOptionalString(trainingProfile?.module, 128) ||
    null;

  const trainingWinsYou = Number.isFinite(Number(trainingProfile?.winsYou))
    ? Math.max(0, Math.floor(Number(trainingProfile?.winsYou)))
    : null;
  const trainingWinsRival = Number.isFinite(Number(trainingProfile?.winsRival))
    ? Math.max(0, Math.floor(Number(trainingProfile?.winsRival)))
    : null;
  const winsYou = Math.max(
    resume?.winsYou ?? -1,
    trainingWinsYou ?? -1
  );
  const winsRival = Math.max(
    resume?.winsRival ?? -1,
    trainingWinsRival ?? -1
  );

  let itemIds = normalizeItemIds(trainingProfile?.itemIds);
  if (itemIds.length === 0) {
    const fallbackSessionId =
      cleanOptionalString(trainingProfile?.lastSessionId, 128) ||
      cleanOptionalString(geoProfile?.lastSessionId, 128);
    if (fallbackSessionId) {
      itemIds = await loadRecentItemIdsFromLastSession(bucket, uid, fallbackSessionId);
    }
  }
  const items = itemIds.map((itemId, idx) => ({
    item_id: itemId,
    uuid: itemId,
    position: idx + 1,
  }));

  return {
    ...learner,
    l1: l1 || null,
    l2: l2 || null,
    country_code: cleanCountryCode(geoProfile?.country_code) || null,
    region_code: cleanOptionalString(geoProfile?.region_code, 32) || null,
    region: cleanOptionalString(geoProfile?.region, 128) || null,
    city: cleanOptionalString(geoProfile?.city, 128) || null,
    module: moduleLabel || moduleRaw || null,
    module_label: moduleLabel || null,
    module_raw: moduleRaw || null,
    wins_you: winsYou >= 0 ? winsYou : null,
    wins_rival: winsRival >= 0 ? winsRival : null,
    victories: winsYou >= 0 ? winsYou : null,
    defeats: winsRival >= 0 ? winsRival : null,
    wins: winsYou >= 0 ? winsYou : null,
    losses: winsRival >= 0 ? winsRival : null,
    item_ids: itemIds,
    item_list: itemIds,
    item_count: itemIds.length,
    items,
    resume_state: {
      cursor: resume?.cursor ?? null,
      date: resume?.date || null,
      start_key: resume?.moduleRaw || null,
      lang: resume?.l2 || null,
      native: resume?.l1 || null,
      wins_you: resume?.winsYou ?? null,
      wins_rival: resume?.winsRival ?? null,
    },
  };
}

async function sha256Hex(input) {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', data);
  const bytes = new Uint8Array(digest);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function maskEmail(email) {
  const raw = cleanOptionalString(email, 256);
  if (!raw || !raw.includes('@')) return null;
  const [local, domain] = raw.split('@');
  if (!local || !domain) return null;
  const visible = local.slice(0, 2);
  return `${visible}${'*'.repeat(Math.max(1, local.length - visible.length))}@${domain}`;
}

function parseTsMs(raw) {
  if (!raw) return null;
  if (typeof raw === 'number') return Math.floor(raw);
  if (typeof raw === 'string') {
    const parsed = Date.parse(raw);
    if (!Number.isNaN(parsed)) return parsed;
    const num = Number(raw);
    if (!Number.isNaN(num)) return Math.floor(num);
  }
  return null;
}

function dateKey(date) {
  const y = date.getUTCFullYear().toString().padStart(4, '0');
  const m = (date.getUTCMonth() + 1).toString().padStart(2, '0');
  const d = date.getUTCDate().toString().padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function dayKeyFromMs(tsMs) {
  return dateKey(new Date(tsMs));
}

function parseDateKey(key) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return null;
  const [y, m, d] = key.split('-').map((v) => parseInt(v, 10));
  if (!y || !m || !d) return null;
  return new Date(Date.UTC(y, m - 1, d));
}

function resolveSessionStartMs(events, state) {
  if (state.sessionStartMs) return state.sessionStartMs;
  let start = null;
  for (const event of events) {
    if (event.type === 'session_start') {
      start = event.tsMs;
      break;
    }
  }
  return start ?? events[0].tsMs;
}

function computeActiveSeconds(events, lastTsMs, idleCapSeconds) {
  let active = 0;
  if (lastTsMs && events.length > 0) {
    const gap = Math.max(0, (events[0].tsMs - lastTsMs) / 1000);
    active += Math.min(gap, idleCapSeconds);
  }
  for (let i = 0; i < events.length - 1; i++) {
    const gap = Math.max(0, (events[i + 1].tsMs - events[i].tsMs) / 1000);
    active += Math.min(gap, idleCapSeconds);
  }
  return Math.floor(active);
}

async function loadSessionState(bucket, uid, sessionId) {
  const key = `${uid}/session_state/${sessionId}.json`;
  const obj = await bucket.get(key);
  if (!obj) {
    return {
      sessionStartMs: null,
      dayKey: null,
      lastTsMs: null,
      bonusApplied: false,
      countedSession: false,
    };
  }
  try {
    const data = await obj.json();
    return {
      sessionStartMs: data.sessionStartMs || null,
      dayKey: data.dayKey || null,
      lastTsMs: data.lastTsMs || null,
      bonusApplied: !!data.bonusApplied,
      countedSession: !!data.countedSession,
    };
  } catch (_) {
    return {
      sessionStartMs: null,
      dayKey: null,
      lastTsMs: null,
      bonusApplied: false,
      countedSession: false,
    };
  }
}

async function saveSessionState(bucket, uid, sessionId, state) {
  const key = `${uid}/session_state/${sessionId}.json`;
  await bucket.put(key, JSON.stringify(state), {
    httpMetadata: { contentType: 'application/json' },
  });
}

async function appendRawSession(bucket, uid, dayKey, sessionId, lines) {
  if (!lines || lines.length === 0) return;
  const key = `${uid}/raw/${dayKey}/${sessionId}.ndjson`;
  const existing = await bucket.get(key);
  const payload = lines.join('\n') + '\n';
  if (!existing) {
    await bucket.put(key, payload, { httpMetadata: { contentType: 'application/x-ndjson' } });
    return;
  }
  const oldText = await existing.text();
  const merged = oldText + payload;
  await bucket.put(key, merged, { httpMetadata: { contentType: 'application/x-ndjson' } });
}

async function updateUserSummary(bucket, uid, dayKey, seconds, runs, sessions, lastEventTs) {
  const key = `${uid}/summary/${dayKey}.json`;
  let current = { seconds: 0, runs: 0, sessions: 0, lastEventTs: 0 };
  const existing = await bucket.get(key);
  if (existing) {
    try {
      const parsed = await existing.json();
      current.seconds = parsed.seconds || 0;
      current.runs = parsed.runs || 0;
      current.sessions = parsed.sessions || 0;
      current.lastEventTs = parsed.lastEventTs || 0;
    } catch (_) {
      // ignore parse errors
    }
  }
  current.seconds += seconds;
  current.runs += runs;
  current.sessions += sessions;
  current.lastEventTs = Math.max(current.lastEventTs || 0, lastEventTs || 0);
  await bucket.put(key, JSON.stringify(current), {
    httpMetadata: { contentType: 'application/json' },
  });
}

async function updateUserGeoProfile(bucket, uid, geo, sessionId) {
  const hasGeo =
    cleanCountryCode(geo?.country_code) ||
    cleanOptionalString(geo?.region_code, 32) ||
    cleanOptionalString(geo?.region, 128) ||
    cleanOptionalString(geo?.city, 128);
  if (!hasGeo) return;
  const key = `${uid}/profile/geo.json`;
  const previous = (await getJsonObject(bucket, key)) || {};
  const now = new Date().toISOString();
  const next = {
    userId: uid,
    country_code: cleanCountryCode(geo.country_code) || cleanCountryCode(previous.country_code) || null,
    region_code: cleanOptionalString(geo.region_code, 32) || cleanOptionalString(previous.region_code, 32) || null,
    region: cleanOptionalString(geo.region, 128) || cleanOptionalString(previous.region, 128) || null,
    city: cleanOptionalString(geo.city, 128) || cleanOptionalString(previous.city, 128) || null,
    continent: cleanOptionalString(geo.continent, 32) || cleanOptionalString(previous.continent, 32) || null,
    timezone: cleanOptionalString(geo.timezone, 64) || cleanOptionalString(previous.timezone, 64) || null,
    colo: cleanOptionalString(geo.colo, 32) || cleanOptionalString(previous.colo, 32) || null,
    source: cleanOptionalString(geo.source, 32) || cleanOptionalString(previous.source, 32) || null,
    lastSessionId: cleanOptionalString(sessionId, 128) || cleanOptionalString(previous.lastSessionId, 128) || null,
    updatedAt: now,
  };
  await putJsonObject(bucket, key, next);
}

async function gzipEncodeUtf8(text) {
  const stream = new Blob([text]).stream().pipeThrough(new CompressionStream('gzip'));
  const bytes = await new Response(stream).arrayBuffer();
  return bytes;
}

async function appendLegacyRun(bucket, uid, sessionId, lines, fallbackChunk) {
  const key = `${uid}/runs/${sessionId}.ndjson.gz`;
  let chunk = fallbackChunk;
  if (Array.isArray(lines) && lines.length > 0) {
    try {
      const body = `${lines.join('\n')}\n`;
      chunk = await gzipEncodeUtf8(body);
    } catch (_) {
      chunk = fallbackChunk;
    }
  }
  const existing = await bucket.get(key);
  if (!existing) {
    await bucket.put(key, chunk, { httpMetadata: { contentType: 'application/gzip' } });
    return;
  }
  const oldBytes = await existing.arrayBuffer();
  const total = oldBytes.byteLength + chunk.byteLength;
  if (total > LOG_MAX_BYTES) {
    const stamp = new Date().toISOString().replace(/[:.]/g, '').replace('T', '-').replace('Z', '');
    const rotatedKey = `${uid}/runs/${sessionId}-${stamp}.ndjson.gz`;
    await bucket.copy(key, rotatedKey);
    await bucket.put(key, chunk, { httpMetadata: { contentType: 'application/gzip' } });
    return;
  }
  const merged = new Uint8Array(total);
  merged.set(new Uint8Array(oldBytes), 0);
  merged.set(new Uint8Array(chunk), oldBytes.byteLength);
  await bucket.put(key, merged.buffer, { httpMetadata: { contentType: 'application/gzip' } });
}
