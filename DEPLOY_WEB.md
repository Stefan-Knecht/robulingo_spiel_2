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
