# Deploying the Worker (logs → R2)

This repo contains the Worker entrypoint at `tools/cloudflare_worker_log.js`.

It expects two R2 bindings:

- `USERDATA` → bucket `userdata`
- `HINTS` → bucket `hints`

## Deploy via Wrangler

1. Install wrangler (once): `npm i -g wrangler`
2. Login (once): `wrangler login`
3. Deploy:

```bash
cd tools/worker
wrangler deploy
```

After deploy, the app will POST (per-session logs):

- `POST https://<workerHost><apiPrefix>/log` → `userdata/<userId>/runs/<sessionId>.ndjson.gz`
- `POST https://<workerHost><apiPrefix>/audio-target-matches` → `userdata/<userId>/audio_target_matches/<sessionId>.ndjson.gz`

These endpoints require headers:
- `x-user-id`
- `x-session-id`
