# mindOS — App (Flutter, web + mobile)

The primary surface (ADR-010): Flutter, Riverpod, GoRouter and Drift (SQLite on
mobile, WASM on web). One codebase serves the mobile app and the web app at
`https://mindos-web.onrender.com`. The dark "presence" theme is forced and the
font is Inter.

## Screens (routes)
| Route | Screen |
|-------|--------|
| `/login`, `/register` | Auth (session persisted with `shared_preferences`) |
| `/` | **Hoy**: focus card + focus score, finance, habit, goal ("Proyectos"), reminders, recommendation |
| `/capture` | Text capture, offline-first (Drift outbox → `SyncService`). Voice is disabled for now |
| `/capture/:id/insights` | **Lo que entendí**: extracted entities and connections (polls while processing) |
| `/ask` | **Conversar**: RAG answers with sources and the `PresenceOrb` |
| `/memory` | **Memoria**: graph counts and timeline of captures |
| `/graph/:type` | Nodes of one type (first page only) |
| `/tasks` | Tasks: done, priority, create |
| `/growth` | Goals, habits, reflection |

HTTP clients: `GraphApiClient` (graph, briefing, query) and `MindosApi` (tasks,
growth, finance), plus the auth and capture clients. Unifying them is pending
(D-016).

## Requirements
- Flutter SDK (stable; Render pins 3.44.6), Dart 3.5+

## First-time setup
Native platform folders (`android/`, `ios/`) are generated locally and are not
committed. `web/` **is** committed, because it includes `sqlite3.wasm` and
`drift_worker.js` for Drift on the web.

```bash
flutter create . --project-name mindos --platforms=android,ios
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates app_database.g.dart
```

## Run
```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000/v1   # web
flutter run --dart-define=API_BASE_URL=http://localhost:3000/v1             # device/emulator
flutter build web --release --dart-define=API_BASE_URL=https://mindos-api.onrender.com/v1
```

## Voice notes (ADR-021)
Recording uses the `record` plugin: Opus/WebM in browsers (AAC/MP4 on Safari)
and AAC/M4A on mobile. The audio sits in the offline outbox until it is synced
to `POST /v1/captures/voice`; the server transcribes it and the audio is
discarded. **Native builds** need the microphone permission in the generated
platform folders:
- Android: `<uses-permission android:name="android.permission.RECORD_AUDIO"/>` in `android/app/src/main/AndroidManifest.xml`.
- iOS: `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist`.

## Quality
- `flutter analyze --no-fatal-infos`: static analysis
- `flutter test`: tests. There are 15, all for capture; new screens have none
  yet (D-012).

## Installing Flutter (local/CI-like Linux)
Install the stable SDK **outside** the repo and add it to `PATH`:

```bash
git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
flutter --version          # first run downloads the embedded Dart SDK
flutter config --no-analytics
```

For `flutter test`, the Dart toolchain alone is enough (no Android/iOS SDK
needed): `NativeDatabase.memory()` uses the bundled `sqlite3`.
