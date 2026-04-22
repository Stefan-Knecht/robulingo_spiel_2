# Deploy RobuLingo Web to Firebase Hosting

This repo deploys the Flutter web build to Firebase Hosting targets:

- `robulingo` (site: `robulingo-635c5`)
- `dailywords` (site: `dailywords-635c5`)

Both targets are in Firebase project `robulingo-635c5`.

## Canonical deploy path

The canonical deploy path is local deploy from this machine.

`tools/deploy_firebase_hosting.sh` now builds and deploys from the current local
git state by default:

- default source ref: `HEAD`
- default behavior: no `git fetch`
- both flavors are always deployed in sequence

The script builds Flutter web with:

- `APP_FLAVOR=robulingo` and deploys `hosting:robulingo`
- `APP_FLAVOR=dailywords` and deploys `hosting:dailywords`

## One-time setup

Install the Firebase CLI and log in:

```bash
npm i -g firebase-tools
firebase login
```

The Firebase project is configured in `.firebaserc` and Hosting is configured in
`firebase.json`.

## Deploy production from local HEAD

```bash
tools/deploy_firebase_hosting.sh prod
```

This deploys exactly what is checked out locally.

## Deploy preview from local HEAD

Preview deploys create a temporary URL so you can test without overwriting
production:

```bash
tools/deploy_firebase_hosting.sh preview my-branch
```

## Optional remote-ref deploy

If you explicitly want to deploy from a remote ref instead of local `HEAD`, opt
in:

```bash
FETCH_FROM_ORIGIN=1 SOURCE_REF=origin/main tools/deploy_firebase_hosting.sh prod
```

## Typical update workflow

```bash
git checkout main
# make or review local changes
tools/deploy_firebase_hosting.sh prod
```

## Legacy flavor arguments

Older commands such as:

```bash
tools/deploy_firebase_hosting.sh prod robulingo
tools/deploy_firebase_hosting.sh prod dailywords
```

still run, but the flavor argument is ignored. The script always deploys both
targets.

## One-time target binding

If the `dailywords` hosting target/site is not yet bound in Firebase, run:

```bash
firebase target:apply hosting dailywords <YOUR_DAILYWORDS_SITE_ID>
```

## GitHub workflow

This repo also contains `.github/workflows/deploy-hosting-main.yml`, but that is
not the canonical path for release. Use the local script unless GitHub-based
deploy is intentionally configured and maintained.
