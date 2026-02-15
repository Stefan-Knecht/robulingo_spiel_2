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
const EMOJI_QUEUE_MAX_ITEMS = 500;

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
  const geo = extractGeoMetadata(request);

  const bodyText = await readRequestBody(request, chunk);
  const lines = bodyText
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const sessions = new Map();
  const legacyLines = [];
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

  // Keep legacy gzip log for audit/debug (optional).
  await appendLegacyRun(bucket, uid, sessionId, legacyLines, chunk);

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
  const now = new Date().toISOString();
  const key = consentKey(uid);
  const previous = await getJsonObject(env.USERDATA, key);
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
  await putJsonObject(env.USERDATA, key, next);
  if (!monitoringOn) {
    const pairing = await getJsonObject(env.USERDATA, pairingKey(uid));
    if (pairing && pairing.active) {
      pairing.active = false;
      pairing.updatedAt = now;
      await putJsonObject(env.USERDATA, pairingKey(uid), pairing);
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
  const consent = await getJsonObject(env.USERDATA, consentKey(uid));
  if (!consent || consent.monitoringOn !== true) {
    return jsonResponse(
      { ok: false, error: 'consent_required', message: 'consent monitoring_on=true required' },
      409
    );
  }
  const emailRaw = String(body.supervisor_email || '').trim();
  const codeRaw = String(body.supervisor_code_5 || body.supervisor_code || '').trim();
  if (!emailRaw) {
    return jsonResponse({ ok: false, error: 'missing_supervisor_email' }, 400);
  }
  if (codeRaw.length !== 5) {
    return jsonResponse({ ok: false, error: 'invalid_supervisor_code', expectedLength: 5 }, 400);
  }

  const now = new Date().toISOString();
  const previous = await getJsonObject(env.USERDATA, pairingKey(uid));
  const internalName = cleanOptionalString(body.internal_name, 128);
  const comment = cleanOptionalString(body.comment, 1024);
  const uiLanguage = cleanOptionalString(body.ui_language, 32);
  const next = {
    userId: uid,
    active: true,
    supervisorEmailNormalized: emailRaw.toLowerCase(),
    supervisorEmailMasked: maskEmail(emailRaw),
    supervisorCodeHash: await sha256Hex(codeRaw),
    supervisorCodeLast2: codeRaw.slice(-2),
    internalName,
    comment,
    uiLanguage,
    linkedAt: previous?.linkedAt || now,
    updatedAt: now,
  };
  await putJsonObject(env.USERDATA, pairingKey(uid), next);

  return jsonResponse({
    ok: true,
    pairing: {
      userId: next.userId,
      active: next.active,
      supervisorEmailMasked: next.supervisorEmailMasked,
      supervisorCodeLast2: next.supervisorCodeLast2,
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
    return await getEmojiQueue(request, env, uid, url);
  }
  if (request.method === 'DELETE') {
    const body = await readJsonBody(request);
    const uid = resolveUserId(request, body);
    if (!uid) {
      return new Response('missing x-user-id', { status: 400, headers: CORS_HEADERS });
    }
    const queue = await loadEmojiQueue(env.USERDATA, uid);
    queue.items = [];
    queue.updatedAt = new Date().toISOString();
    await saveEmojiQueue(env.USERDATA, uid, queue);
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
  const source = cleanOptionalString(body.source, 64) || 'app';
  const fallbackReason = cleanOptionalString(body.reason, 64);
  const fallbackNote = cleanOptionalString(body.note, 512);
  const fallbackMeta = normalizeMeta(body.meta);
  const now = new Date().toISOString();

  const rawItems = Array.isArray(body.items) ? body.items : [body];
  const accepted = [];
  for (const raw of rawItems) {
    const emoji = cleanOptionalString(raw?.emoji, 16);
    if (!emoji) continue;
    const reason = cleanOptionalString(raw?.reason, 64) || fallbackReason;
    const note = cleanOptionalString(raw?.note, 512) || fallbackNote;
    const meta = normalizeMeta(raw?.meta) || fallbackMeta;
    const priority = normalizePriority(raw?.priority);
    accepted.push({
      id: crypto.randomUUID(),
      emoji,
      status: 'pending',
      source: cleanOptionalString(raw?.source, 64) || source,
      reason,
      note,
      priority,
      meta,
      createdAt: cleanOptionalString(raw?.createdAt, 64) || now,
      updatedAt: now,
      consumedAt: null,
    });
  }
  if (accepted.length === 0) {
    return jsonResponse(
      { ok: false, error: 'no_valid_items', message: 'provide emoji or items[].emoji' },
      400
    );
  }

  const queue = await loadEmojiQueue(env.USERDATA, uid);
  queue.items.push(...accepted);
  trimEmojiQueue(queue);
  queue.updatedAt = now;
  await saveEmojiQueue(env.USERDATA, uid, queue);

  return jsonResponse({
    ok: true,
    userId: uid,
    accepted: accepted.length,
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
  const ids = Array.isArray(body.ids) ? body.ids.map((v) => String(v)) : [];
  if (ids.length === 0) {
    return jsonResponse({ ok: false, error: 'missing_ids' }, 400);
  }
  const now = new Date().toISOString();
  const queue = await loadEmojiQueue(env.USERDATA, uid);
  const idSet = new Set(ids);
  const mode = body.mode === 'remove' ? 'remove' : 'status';
  const nextStatus = mode === 'status' ? normalizeStatus(body.status) || 'delivered' : null;
  let changed = 0;
  if (mode === 'remove') {
    const before = queue.items.length;
    queue.items = queue.items.filter((item) => !idSet.has(item.id));
    changed = before - queue.items.length;
  } else {
    for (const item of queue.items) {
      if (!idSet.has(item.id)) continue;
      item.status = nextStatus;
      item.updatedAt = now;
      if (nextStatus !== 'pending') {
        item.consumedAt = item.consumedAt || now;
      }
      changed += 1;
    }
  }
  queue.updatedAt = now;
  await saveEmojiQueue(env.USERDATA, uid, queue);
  return jsonResponse({
    ok: true,
    userId: uid,
    changed,
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
  const [consent, pairing, queue, resume, registration] = await Promise.all([
    getJsonObject(env.USERDATA, consentKey(uid)),
    getJsonObject(env.USERDATA, pairingKey(uid)),
    loadEmojiQueue(env.USERDATA, uid),
    getJsonObject(env.USERDATA, `${uid}/resume_state.json`),
    loadSupervisorRegistration(env.USERDATA, uid),
  ]);
  const queueSummary = summarizeEmojiQueue(queue);
  const recent = recentPending(queue.items, 8);
  const resumeInfo = summarizeResumeState(resume);
  const registrationName = resolveSupervisorRegistrationName({
    pairing,
    consent,
    registration,
  });
  return jsonResponse({
    ok: true,
    userId: uid,
    generatedAt: new Date().toISOString(),
    supervisor: {
      paired: !!pairing?.active,
      active: !!pairing?.active,
      supervisorEmailMasked: pairing?.supervisorEmailMasked || null,
      linkedAt: pairing?.linkedAt || null,
      updatedAt: pairing?.updatedAt || null,
      registrationName: registrationName || null,
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
      queuePollingMs: 15000,
      queueAckEndpoint: '/api/emoji-queue-ack',
      queueReadEndpoint: '/api/emoji-queue?status=pending&limit=50',
      dataContractVersion: 2,
    },
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

function resolveSupervisorRegistrationName({ pairing, consent, registration }) {
  return firstNonEmptyString(
    registration?.supervisorName,
    registration?.registeredName,
    registration?.registrationName,
    registration?.displayName,
    registration?.name,
    pairing?.registrationName,
    pairing?.supervisorName,
    pairing?.displayName,
    pairing?.name,
    consent?.registrationName,
    consent?.supervisorName,
    consent?.displayName,
    consent?.name
  );
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
    latestEmoji: latestItem?.emoji || null,
    latestEventAt: latestItem?.updatedAt || latestItem?.createdAt || null,
  };
}

async function getEmojiQueue(request, env, uid, url) {
  const queue = await loadEmojiQueue(env.USERDATA, uid);
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
    .sort((a, b) => Date.parse(b.createdAt || 0) - Date.parse(a.createdAt || 0))
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
