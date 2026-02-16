# Deploy Robulingo Web to Firebase Hosting

This repo deploys the Flutter web build to Firebase Hosting targets:

- `robulingo` (site: `robulingo-635c5`)
- `dailywords` (site: `dailywords`)

Both targets are in Firebase project `robulingo-635c5`.

## One-time setup

Install the Firebase CLI and log in:

```bash
npm i -g firebase-tools
firebase login
```

The Firebase project is configured in `.firebaserc` and Hosting is configured in
`firebase.json`.

## Deploy (production)

RobuLingo:

```bash
tools/deploy_firebase_hosting.sh prod robulingo
```

DailyWords:

```bash
tools/deploy_firebase_hosting.sh prod dailywords
```

The script builds Flutter web with flavor:

- `robulingo` -> `--dart-define=APP_FLAVOR=robulingo`
- `dailywords` -> `--dart-define=APP_FLAVOR=dailywords`

## Deploy (preview channel)

Preview deploys create a temporary URL so you can test without overwriting
production:

```bash
tools/deploy_firebase_hosting.sh preview my-branch robulingo
tools/deploy_firebase_hosting.sh preview my-branch dailywords
```

## Typical update workflow

```bash
git checkout main
git pull --rebase origin main
tools/deploy_firebase_hosting.sh prod robulingo
```

## One-time target binding

If the `dailywords` hosting target/site is not yet bound in Firebase, run:

```bash
firebase target:apply hosting dailywords <YOUR_DAILYWORDS_SITE_ID>
```

## Automatic deploy from GitHub (recommended)

This repo includes `.github/workflows/deploy-hosting-main.yml`.
It automatically deploys to Firebase Hosting `live` on every push to `main`.

### One-time GitHub setup

1. Create a Firebase service account key JSON with Hosting deploy permissions.
2. In GitHub, open `Settings > Secrets and variables > Actions`.
3. Add a repository secret named `FIREBASE_SERVICE_ACCOUNT_ROBULINGO_635C5`.
4. Paste the full JSON key contents as the secret value.
5. Push to `main` (or run the workflow manually from GitHub Actions).

### Verify what is live

After each deploy, check:

- `https://robulingo-635c5.web.app/version.json`