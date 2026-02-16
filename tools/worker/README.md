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

- `POST https://<workerHost><apiPrefix>/log` → 
  - raw NDJSON: `userdata/<userId>/raw/<YYYY-MM-DD>/<sessionId>.ndjson`
  - per-day summary: `userdata/<userId>/summary/<YYYY-MM-DD>.json`
  - legacy gzip: `userdata/<userId>/runs/<sessionId>.ndjson.gz`
- `POST https://<workerHost><apiPrefix>/audio-target-matches` → `userdata/<userId>/audio_target_matches/<sessionId>.ndjson.gz`

These endpoints require headers:
- `x-user-id`
- `x-session-id`

Summary endpoint:
- `GET https://<workerHost><apiPrefix>/summary?from=YYYY-MM-DD&to=YYYY-MM-DD`
  - header: `x-user-id`

Supervisor/Consent endpoints (R2-backed MVP):
- `POST https://<workerHost><apiPrefix>/consent`
  - header: `x-user-id`
  - body:
    - `monitoring_on: true|false`
    - `text_version: string` (optional, default `trial_v1`)
    - `internal_name: string` (optional)
    - `comment: string` (optional)
    - `ui_language: string` (optional)
- `POST https://<workerHost><apiPrefix>/pair`
  - header: `x-user-id`
  - body:
    - `supervisor_email: string`
    - `supervisor_code` or `supervisor_code_5`: 5 chars
  - requires active consent (`monitoring_on=true`)

Emoji queue endpoints (for dashboard integration):
- `POST https://<workerHost><apiPrefix>/emoji-queue`
  - header: `x-user-id`
  - body (single item):
    - `emoji: string`
    - `reason`, `note`, `priority`, `source`, `meta` (all optional)
  - body (batch):
    - `items: [{ emoji, reason?, note?, priority?, source?, meta? }, ...]`
- `GET https://<workerHost><apiPrefix>/emoji-queue?status=pending|delivered|archived|all&limit=50&cursor=0`
  - header: `x-user-id` (or `uid` query fallback)
- `POST https://<workerHost><apiPrefix>/emoji-queue-ack`
  - header: `x-user-id`
  - body:
    - `ids: string[]`
    - `status: delivered|archived` (optional, default `delivered`)
    - `mode: status|remove` (optional, default `status`)
- `DELETE https://<workerHost><apiPrefix>/emoji-queue`
  - header: `x-user-id`
  - clears queue

Dashboard build endpoint:
- `GET https://<workerHost><apiPrefix>/dashboard-info`
  - header: `x-user-id` (or `uid` query fallback)
  - returns:
    - `supervisor` block (paired/active/email masked/registrationName/internal name/comment/ui language)
    - `consent` block
    - `emojiQueue` summary + `itemsPreview`
    - `resumeState` summary
    - `dashboardHints` (poll interval + endpoint hints, `dataContractVersion: 2`)
