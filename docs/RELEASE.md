# Release guide

Follow these in order. Items marked **[you]** need your own accounts and can't be done from the code.

## 1. Firebase (sign-in + crash reports) — about 20 minutes
1. **[you]** Create a project at [console.firebase.google.com](https://console.firebase.google.com).
2. **Authentication → Sign-in method:** enable **Google**, **Email/Password** and **Apple**.
3. From `flutter/`, generate the real config (replaces the placeholder `lib/firebase_options.dart`):
   ```bash
   dart pub global activate flutterfire_cli
   flutter create --platforms=android,ios --org com.yourname.myexpance --project-name my_expance .   # first time only
   flutterfire configure --platforms=android,ios
   ```
4. **Android Google sign-in:** add your SHA-1 fingerprints in Firebase → Project settings → Android app:
   - debug: `cd android && ./gradlew signingReport`
   - release/upload key: from section 3 below
   - Play App Signing key: Play Console → Setup → App signing (after the first upload)
   Then re-download `google-services.json`. If sign-in still fails, pass the Web client ID:
   `--dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com`.
5. **iOS Google sign-in:** add the `REVERSED_CLIENT_ID` from `GoogleService-Info.plist` as a URL scheme in `ios/Runner/Info.plist` (see the google_sign_in_ios README).
6. **iOS Sign in with Apple:** in Xcode → Runner → Signing & Capabilities → **+ Sign in with Apple**. In Firebase → Apple provider, add your Services ID / key as prompted.
7. **Crashlytics:** Firebase → Crashlytics → enable. It starts reporting after the first release-build crash.

## 2. Backend on Render — about 15 minutes
1. **[you]** Push this repo to GitHub.
2. Render → **New → Blueprint** → pick the repo. `render.yaml` creates the API and the Postgres database in Singapore.
3. Fill the secrets it asks for: `GROQ_API_KEY`, `FIREBASE_PROJECT_ID`, `SUPPORT_EMAIL`, `DEVELOPER_NAME` (optional `SENTRY_DSN`).
4. Wait for the deploy, then check:
   - `https://<your-service>.onrender.com/health` → `{"status":"ok"}`
   - `/privacy` and `/account-deletion` open in a browser (you need these URLs for both stores).
5. Migrations run automatically on every deploy (`alembic upgrade head` in the Docker command).
6. Optional: a custom domain (Render → Settings → Custom domains), e.g. `api.myexpance.app`.

Cost guide: the blueprint starts on Render's **free** plans for the trial: the API sleeps after 15 minutes idle (first request then takes ~1 minute) and the free database is deleted after 30 days. Before a real launch, change `plan: free` to `starter` (web) and `basic-256mb` (database) in `render.yaml`. The assistant uses Groq's free tier by default; usage is also capped per user by `CHAT_DAILY_LIMIT` (default 60 messages/day). For a store launch, consider a paid model (`LLM_PROVIDER=anthropic`) so free-tier limits don't hit real users.

## 3. Android release (Google Play)
1. Create an upload key (keep it and its passwords somewhere safe; losing it is painful):
   ```bash
   keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `flutter/android/key.properties` (already git-ignored):
   ```
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=/Users/you/upload-keystore.jks
   ```
3. In `android/app/build.gradle(.kts)`, load `key.properties` and use it for `signingConfigs.release` (Flutter's guide: docs.flutter.dev/deployment/android#configure-signing-in-gradle). Set `applicationId` to your final ID, e.g. `com.yourname.myexpance` — it can never change after publishing.
4. Make sure `android/app/src/main/AndroidManifest.xml` has `<uses-permission android:name="android.permission.INTERNET"/>`, and the app label is "My Expance".
5. Icons and splash:
   ```bash
   dart run flutter_launcher_icons
   dart run flutter_native_splash:create
   ```
6. Build:
   ```bash
   flutter build appbundle --release --obfuscate --split-debug-info=build/symbols \
     --dart-define=API_BASE_URL=https://<your-service>.onrender.com \
     --dart-define=SUPPORT_EMAIL=you@yourdomain.com
   ```
   Upload `build/app/outputs/bundle/release/app-release.aab`. Keep `build/symbols` (for readable crash reports).
7. **[you]** Play Console ($25 one-time): create the app, fill the listing from `STORE_LISTING.md`, Data safety, content rating, target audience, and the account deletion URL.
8. New personal developer accounts must run a **closed test with at least 12 testers for 14 days** before production access. Start this early; it is the longest step.

## 4. iOS release (App Store)
1. **[you]** Apple Developer Program ($99/year). Create the App ID with **Sign in with Apple** enabled.
2. In Xcode: set the bundle identifier, team, version 1.0.0 and build 1; app display name "My Expance".
3. Build:
   ```bash
   flutter build ipa --release --obfuscate --split-debug-info=build/symbols \
     --dart-define=API_BASE_URL=https://<your-service>.onrender.com \
     --dart-define=SUPPORT_EMAIL=you@yourdomain.com
   ```
   Upload with Xcode Organizer or Transporter, test with TestFlight.
4. **[you]** App Store Connect: listing from `STORE_LISTING.md`, App Privacy answers, privacy policy URL, a **demo account** for the reviewer (email + password), and review notes.

## 5. Before you press "Submit"
- [ ] Release build talks to the Render URL (not 10.0.2.2), sign-in works on a real device
- [ ] Add, edit, delete an expense; assistant logs one; budget jar shows after setting a budget
- [ ] Light and dark mode, large system font, reduce-motion on
- [ ] Delete account works end to end and you land on the sign-in screen
- [ ] `/privacy` and `/account-deletion` URLs live and correct (name, email filled in)
- [ ] Crashlytics receives a test crash from a release build
- [ ] Version/build numbers bumped in `pubspec.yaml` for every upload (`1.0.0+1`, `1.0.1+2`, …)
