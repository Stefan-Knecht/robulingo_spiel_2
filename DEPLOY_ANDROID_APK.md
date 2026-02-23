# Android APK Release + Cloudflare R2 (DailyWords)

This project includes scripts for building a signed `dailywords` APK and uploading it to Cloudflare R2.

## 1) One-time setup: Android signing key

Fast setup via helper script:

```bash
tools/android/setup_android_keystore.sh \
  --store-pass "<STORE_PASSWORD>" \
  --key-pass "<KEY_PASSWORD>"
```

Manual setup (alternative):

```bash
keytool -genkeypair -v \
  -keystore android/upload-keystore.jks \
  -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

Create `android/key.properties` from the sample:

```bash
cp android/key.properties.sample android/key.properties
```

Set real values in `android/key.properties`:

```properties
storeFile=upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Important:
- Keep `android/key.properties` and your keystore private.
- Back up the keystore + passwords safely. You need the same key for future updates.

## 2) One-time setup: Cloudflare bucket

Login first (opens browser; you enter Cloudflare credentials there):

```bash
tools/android/cloudflare_wrangler_login.sh
```

Create a dedicated public APK bucket (recommended):

```bash
wrangler r2 bucket create dailywords-apk
```

Then enable public access for that bucket (R2 public URL or custom domain) in Cloudflare dashboard.

## 3) Build signed DailyWords APK

```bash
tools/android/build_dailywords_release_apk.sh
```

Artifacts are created in:

`build/releases/android/dailywords/`

including:
- versioned APK
- `.sha256` checksum
- metadata JSON
- `dailywords-latest.apk`

## 4) Upload to R2

```bash
tools/android/upload_dailywords_apk_r2.sh \
  --bucket dailywords-apk \
  --public-base-url https://<your-public-base-url>
```

Uploaded objects:
- `releases/android/dailywords/<apk>`
- `releases/android/dailywords/<apk>.sha256`
- `releases/android/dailywords/<apk>.json`
- `releases/android/dailywords/latest.json`
  - includes `version_name` and `version_code` for in-app update checks

## 5) One-command release (build + upload)

```bash
tools/android/release_dailywords_to_r2.sh \
  --bucket dailywords-apk \
  --public-base-url https://<your-public-base-url>
```

## Optional flags

- Set custom version:
  - `--build-name 1.0.3`
  - `--build-number 103`
- Set upload prefix:
  - `--prefix releases/android/dailywords`
- Set explicit Wrangler config:
  - `--wrangler-config tools/worker/wrangler.toml`

## Landing page + in-app updater links

Use the Worker endpoint (not the raw R2 APK URL) so downloads are tracked and redirects stay on the latest APK:

- `https://<workerHost><apiPrefix>/android-release/download?flavor=dailywords&source=landing`

For app-side update checks:

- `https://<workerHost><apiPrefix>/android-release/latest?flavor=dailywords`

For download counters:

- `https://<workerHost><apiPrefix>/android-release/download-stats?flavor=dailywords&from=YYYY-MM-DD&to=YYYY-MM-DD`
