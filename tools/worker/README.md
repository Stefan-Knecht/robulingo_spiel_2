# Deploying the Worker (logs → R2)

This repo contains the Worker entrypoint at `tools/cloudflare_worker_log.js`.

It expects these R2 bindings:

- `USERDATA` → bucket `userdata`
- `DAILYWORDSUSERDATA` → bucket `dailywordsuserdata`
- `DAILYWORDSAPK` → bucket `dailywords-apk`
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
- optional: `x-app-flavor` (`dailywords` routes user-data writes/reads to `DAILYWORDSUSERDATA`)
- optional query fallback for link-based clients: `app_flavor=dailywords` (also supports `flavor=dailywords` / `app=dailywords`)

Summary endpoint:
- `GET https://<workerHost><apiPrefix>/summary?from=YYYY-MM-DD&to=YYYY-MM-DD`
  - header: `x-user-id`
  - optional: `x-app-flavor: dailywords` or query `app_flavor=dailywords`

Android release endpoints (DailyWords):
- `GET https://<workerHost><apiPrefix>/android-release/latest?flavor=dailywords`
  - returns latest release metadata (`version_name`, `version_code`, `download_url`, ...)
- `GET https://<workerHost><apiPrefix>/android-release/download?flavor=dailywords&source=landing`
  - logs one download event in R2 and redirects (`302`) to the current APK URL
- `GET https://<workerHost><apiPrefix>/android-release/download-stats?flavor=dailywords&from=YYYY-MM-DD&to=YYYY-MM-DD`
  - returns counted download events per day + total for the date range

Supervisor/Consent endpoints (R2-backed MVP):
- Bucket behavior: these endpoints always use `DAILYWORDSUSERDATA` (fallback `USERDATA` only if the DailyWords binding is missing), independent of `x-app-flavor`.
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
  - side effect: updates canonical supervisor→learner index in R2

Supervisor learner listing (canonical, index-backed):
- `GET https://<workerHost><apiPrefix>/supervisor-users`
  - credentials:
    - header: `x-supervisor-email` + `x-supervisor-code`
    - or query: `supervisor_email` + `supervisor_code`
  - flavor parameters are ignored for this endpoint (always DailyWords bucket)
  - returns:
    - `supervisor` metadata (`emailMasked`, `codeLast2`, `learnerCount`, `updatedAt`)
    - `learners[]` entries:
      - base linkage fields: `userId`, `active`, `linkedAt`, `updatedAt`, `internalName`, `comment`, `uiLanguage`
      - language/module fields: `l1`, `l2`, `module`, `module_label`, `module_raw`
      - geo fields: `country_code`, `region_code`, `region`, `city`
      - outcome counters: `wins_you`, `wins_rival` (+ aliases `victories`, `defeats`, `wins`, `losses`)
      - item list fields: `item_ids`, `item_list`, `item_count`, `items[]` (`item_id`, `uuid`, `position`)
      - latest resume snapshot: `resume_state` (`cursor`, `date`, `start_key`, `lang`, `native`, `wins_you`, `wins_rival`)
  - behavior:
    - if index is empty (legacy data), endpoint auto-rebuilds index from existing `*/supervisor/pairing.json` records in the selected bucket
    - enrichment source is learner data in `profile/training.json`, `profile/geo.json`, and `resume_state.json`

Learner profile endpoint (bridge helper for dashboards):
- `GET https://<workerHost><apiPrefix>/learner-profile`
  - header: `x-user-id` (or `uid` query fallback)
  - optional flavor routing: `x-app-flavor` / `app_flavor` (uses normal user-data bucket routing)
  - returns enriched learner metadata:
    - `l1`, `l2`, `country_code`, `region_code`, `region`, `city`
    - `module`, `module_label`, `module_raw`
    - `wins_you`, `wins_rival` (+ aliases)
    - `item_ids`, `items[]`, `resume_state`

Emoji queue endpoints (for dashboard integration):
- Bucket behavior: all queue reads/writes always use the DailyWords bucket.
- Pending queue cap: max **2** pending emoji items per learner.
- `POST https://<workerHost><apiPrefix>/emoji-queue`
  - header: `x-user-id`
  - body (single item):
    - `emoji: string`
    - `reason`, `note`, `priority`, `source`, `meta` (all optional)
  - body (batch):
    - `items: [{ emoji, reason?, note?, priority?, source?, meta? }, ...]`
  - if pending queue is full:
    - returns `409` with `error: pending_queue_limit_reached`
  - if batch exceeds free slots:
    - accepts up to available slots and returns `rejectedDueToPendingLimit`
- `GET https://<workerHost><apiPrefix>/emoji-queue?status=pending|delivered|archived|all&limit=50&cursor=0`
  - header: `x-user-id` (or `uid` query fallback)
  - `queue` summary includes UI guard fields:
    - `pendingLimit` (=2)
    - `pendingSlotsRemaining`
    - `pendingLimitReached`
    - `canEnqueuePending`
- `POST https://<workerHost><apiPrefix>/emoji-queue-ack`
  - header: `x-user-id`
  - body:
    - `ids: string[]`
    - `status: delivered|archived` (optional, default `delivered`)
    - `mode: status|remove` (optional, default `status`)
  - `mode=status` respects the same max pending cap (`2`) for transitions to `pending`
- `DELETE https://<workerHost><apiPrefix>/emoji-queue`
  - header: `x-user-id`
  - clears queue

Dashboard build endpoint:
- `GET https://<workerHost><apiPrefix>/dashboard-info`
  - header: `x-user-id` (or `uid` query fallback)
  - flavor parameters are ignored for this endpoint (always DailyWords bucket)
  - returns:
    - `supervisor` block:
      - canonical: `displayName`
      - legacy aliases: `registrationName`, `display_name`
      - email fields: `supervisorEmail` (full), `email` (alias), `supervisorEmailMasked`
      - plus `paired/active/internal name/comment/ui language`
    - `consent` block
    - `emojiQueue` summary + `itemsPreview`
      - includes `pendingLimit`, `pendingSlotsRemaining`, `pendingLimitReached`, `canEnqueuePending`
    - `resumeState` summary
    - `dashboardHints` (poll interval + endpoint hints incl. APK update/count endpoints, `dataContractVersion: 3`, current `queuePollingMs=15000`)
