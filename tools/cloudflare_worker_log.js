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
      if (path.endsWith('/log')) {
        return await handleLog(request, env);
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
  'access-control-allow-headers': 'content-type,if-none-match,x-user-id,content-encoding',
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

function normalizeLang(raw) {
  if (!raw) return '';
  const trimmed = raw.trim().toLowerCase();
  if (!trimmed) return '';
  return trimmed.split(/[-_]/)[0];
}

// ---------- /log ----------
const LOG_MAX_BYTES = 5 * 1024 * 1024; // rotate around 5MB (compressed)

async function handleLog(request, env) {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }
  const uid = request.headers.get('x-user-id');
  if (!uid) {
    return new Response('missing x-user-id', { status: 400 });
  }
  const chunk = await request.arrayBuffer();
  const key = `${uid}/log.ndjson.gz`;
  const bucket = env.USERDATA;

  // Fetch existing log
  const existing = await bucket.get(key);
  if (!existing) {
    await bucket.put(key, chunk, { httpMetadata: { contentType: 'application/gzip' } });
    return new Response('ok', { status: 200 });
  }

  const oldBytes = await existing.arrayBuffer();
  const total = oldBytes.byteLength + chunk.byteLength;
  if (total > LOG_MAX_BYTES) {
    // Rotate current to a dated backup, then start fresh with the new chunk
    const stamp = new Date().toISOString().replace(/[:.]/g, '').replace('T', '-').replace('Z', '');
    const rotatedKey = `${uid}/log-${stamp}.ndjson.gz`;
    await bucket.copy(key, rotatedKey);
    await bucket.put(key, chunk, { httpMetadata: { contentType: 'application/gzip' } });
    return new Response('ok-rotated', { status: 200 });
  }

  // Append by re-uploading concatenated bytes (gzip supports multiple members)
  const merged = new Uint8Array(total);
  merged.set(new Uint8Array(oldBytes), 0);
  merged.set(new Uint8Array(chunk), oldBytes.byteLength);
  await bucket.put(key, merged.buffer, { httpMetadata: { contentType: 'application/gzip' } });
  return new Response('ok', { status: 200 });
}

// ---------- /audio-target-matches ----------
const AUDIO_MATCH_MAX_BYTES = 5 * 1024 * 1024; // rotate around 5MB (compressed)

async function handleAudioTargetMatches(request, env) {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }
  const uid = request.headers.get('x-user-id');
  if (!uid) {
    return new Response('missing x-user-id', { status: 400 });
  }
  const chunk = await request.arrayBuffer();
  const key = `${uid}/audio_target_matches.ndjson.gz`;
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
    const rotatedKey = `${uid}/audio_target_matches-${stamp}.ndjson.gz`;
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
