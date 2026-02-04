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
  'access-control-allow-methods': 'GET,HEAD,POST,OPTIONS',
  'access-control-allow-headers':
    'content-type,if-none-match,x-user-id,x-session-id,content-encoding',
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

async function handleLog(request, env) {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }
  const uid = request.headers.get('x-user-id');
  const sessionId = request.headers.get('x-session-id');
  if (!uid) {
    return new Response('missing x-user-id', { status: 400 });
  }
  if (!sessionId) {
    return new Response('missing x-session-id', { status: 400 });
  }
  const chunk = await request.arrayBuffer();
  const bucket = env.USERDATA;

  const bodyText = await readRequestBody(request, chunk);
  const lines = bodyText
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const sessions = new Map();
  for (const line of lines) {
    let data;
    try {
      data = JSON.parse(line);
    } catch (_) {
      continue;
    }
    const tsMs = parseTsMs(data.ts);
    const sid = data.session;
    if (tsMs == null || !sid) continue;
    if (!sessions.has(sid)) {
      sessions.set(sid, { events: [], rawLines: [] });
    }
    const entry = sessions.get(sid);
    entry.events.push({ tsMs, type: data.type });
    entry.rawLines.push(line);
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

  // Keep legacy gzip log for audit/debug (optional).
  await appendLegacyRun(bucket, uid, sessionId, chunk);

  return new Response('ok', { status: 200, headers: CORS_HEADERS });
}

// ---------- /audio-target-matches ----------
const AUDIO_MATCH_MAX_BYTES = 5 * 1024 * 1024; // rotate around 5MB (compressed)

async function handleAudioTargetMatches(request, env) {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }
  const uid = request.headers.get('x-user-id');
  const sessionId = request.headers.get('x-session-id');
  if (!uid) {
    return new Response('missing x-user-id', { status: 400 });
  }
  if (!sessionId) {
    return new Response('missing x-session-id', { status: 400 });
  }
  const chunk = await request.arrayBuffer();
  const key = `${uid}/audio_target_matches/${sessionId}.ndjson.gz`;
  const bucket = env.USERDATA;

  const existing = await bucket.get(key);
  if (!existing) {
    await bucket.put(key, chunk, { httpMetadata: { contentType: 'application/gzip' } });
    return new Response('ok', { status: 200 });
  }

  const oldBytes = await existing.arrayBuffer();
  const total = oldBytes.byteLength + chunk.byteLength;
  if (total > AUDIO_MATCH_MAX_BYTES) {
    const stamp = new Date().toISOString().replace(/[:.]/g, '').replace('T', '-').replace('Z', '');
    const rotatedKey = `${uid}/audio_target_matches/${sessionId}-${stamp}.ndjson.gz`;
    await bucket.copy(key, rotatedKey);
    await bucket.put(key, chunk, { httpMetadata: { contentType: 'application/gzip' } });
    return new Response('ok-rotated', { status: 200 });
  }

  const merged = new Uint8Array(total);
  merged.set(new Uint8Array(oldBytes), 0);
  merged.set(new Uint8Array(chunk), oldBytes.byteLength);
  await bucket.put(key, merged.buffer, { httpMetadata: { contentType: 'application/gzip' } });
  return new Response('ok', { status: 200 });
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
  const days = [];
  const cursor = new Date(Date.UTC(fromDate.getUTCFullYear(), fromDate.getUTCMonth(), fromDate.getUTCDate()));
  const end = new Date(Date.UTC(toDate.getUTCFullYear(), toDate.getUTCMonth(), toDate.getUTCDate()));
  while (cursor <= end) {
    const key = dateKey(cursor);
    const obj = await env.USERDATA.get(`${uid}/summary/${key}.json`);
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
  const bucket = env.USERDATA;
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
  const bucket = env.USERDATA;
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

async function appendLegacyRun(bucket, uid, sessionId, chunk) {
  const key = `${uid}/runs/${sessionId}.ndjson.gz`;
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
