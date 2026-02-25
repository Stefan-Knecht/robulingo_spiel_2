# APK Release and Linking for `dailywords-project.org`

This file documents how to make sure the Android download link on `https://www.dailywords-project.org` always serves the latest APK from Cloudflare.

## How linking works

The website button should point to this Worker endpoint:

- `https://robulingo-api.knechtipad-aec.workers.dev/api/android-release/download?flavor=dailywords&source=landing`

That endpoint redirects to Cloudflare R2:

- `https://pub-64932e0bdd094618872a67d7b1ff3c50.r2.dev/releases/android/dailywords/dailywords-latest.apk`

Important: do not hardcode a timestamped APK URL in the website button.

## Local APK build output

APK is created here:

- `build/app/outputs/flutter-apk/app-release.apk`

Build command:

```bash
flutter build apk --release --dart-define=APP_FLAVOR=dailywords
```

## Release procedure

1. Build APK:

```bash
flutter build apk --release --dart-define=APP_FLAVOR=dailywords
```

2. Upload both versioned backup and latest key:

```bash
APK='build/app/outputs/flutter-apk/app-release.apk'
STAMP="$(date +%Y%m%d-%H%M)"

LATEST_KEY='dailywords-apk/releases/android/dailywords/dailywords-latest.apk'
VERSIONED_KEY="dailywords-apk/releases/android/dailywords/dailywords-${STAMP}.apk"

wrangler r2 object put "$VERSIONED_KEY" \
  --remote \
  --file "$APK" \
  --content-type 'application/vnd.android.package-archive' \
  --cache-control 'public, max-age=300' \
  --content-disposition 'attachment'

wrangler r2 object put "$LATEST_KEY" \
  --remote \
  --file "$APK" \
  --content-type 'application/vnd.android.package-archive' \
  --cache-control 'public, max-age=300' \
  --content-disposition 'attachment'
```

3. Verify local hash == endpoint hash:

```bash
LOCAL_SHA=$(shasum -a 256 build/app/outputs/flutter-apk/app-release.apk | awk '{print $1}')

TMP=$(mktemp /tmp/dailywords-apk.XXXXXX.apk)
curl -sSL 'https://robulingo-api.knechtipad-aec.workers.dev/api/android-release/download?flavor=dailywords&source=landing' -o "$TMP"
REMOTE_SHA=$(shasum -a 256 "$TMP" | awk '{print $1}')
rm -f "$TMP"

echo "LOCAL_SHA=$LOCAL_SHA"
echo "REMOTE_SHA=$REMOTE_SHA"
```

4. Verify endpoint still redirects correctly:

```bash
curl -I -L --max-redirs 3 \
  'https://robulingo-api.knechtipad-aec.workers.dev/api/android-release/download?flavor=dailywords&source=landing'
```

Expected:
- First response `302`
- Redirect location contains `dailywords-latest.apk`

## Optional check: website points to correct endpoint

```bash
curl -sL https://www.dailywords-project.org | rg 'android-release/download\?flavor=dailywords'
```

## Caveats

- Firebase Spark plan blocks direct `.apk` hosting on Firebase Hosting.
  - Error: `Executable files are forbidden on the Spark billing plan`
  - Therefore APK distribution should use Worker + Cloudflare R2 as above.

- Android launcher icon can appear stale due to OS cache.
  - If icon seems wrong after install, uninstall app and reinstall.

- APK updates can be cached for a few minutes (`Cache-Control: max-age=300`).
  - Always verify by SHA-256 hash when confirming rollout.

- If app behavior is item-specific (audio or similar), APK may be fine but runtime data/cache may be the issue.
  - Re-test on fresh install or after clearing app storage.

## Rollback

If a bad APK was uploaded, restore `dailywords-latest.apk` from a known-good versioned key:

```bash
GOOD='dailywords-apk/releases/android/dailywords/dailywords-YYYYMMDD-HHMM.apk'
TMP=$(mktemp /tmp/dailywords-good.XXXXXX.apk)

wrangler r2 object get "$GOOD" --remote --file "$TMP"
wrangler r2 object put 'dailywords-apk/releases/android/dailywords/dailywords-latest.apk' \
  --remote \
  --file "$TMP" \
  --content-type 'application/vnd.android.package-archive' \
  --cache-control 'public, max-age=300' \
  --content-disposition 'attachment'

rm -f "$TMP"
```

Then repeat hash verification.
