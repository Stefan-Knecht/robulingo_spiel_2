// Cloudflare Worker for RobuLingo logs + user curriculum delta.
// Bindings: R2 bucket named USERDATA -> bucket "userdata"

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');
    try {
      if (path.endsWith('/log')) {
        return await handleLog(request, env);
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
