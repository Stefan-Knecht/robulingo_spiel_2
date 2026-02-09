# Deploy Robulingo Web to Firebase Hosting

This repo deploys the Flutter web build to Firebase Hosting:

- `https://robulingo-635c5.web.app/` (project: `robulingo-635c5`)

## One-time setup

Install the Firebase CLI and log in:

```bash
npm i -g firebase-tools
firebase login
```

The Firebase project is configured in `.firebaserc` and Hosting is configured in
`firebase.json`.

## Deploy (production)

```bash
tools/deploy_firebase_hosting.sh
```

This builds Flutter web (`flutter build web --release`) and deploys `build/web`
to Firebase Hosting.

## Deploy (preview channel)

Preview deploys create a temporary URL so you can test without overwriting
production:

```bash
tools/deploy_firebase_hosting.sh preview my-branch
```

## Typical update workflow

```bash
git checkout main
git pull --rebase origin main
tools/deploy_firebase_hosting.sh
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