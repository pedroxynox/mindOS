# mindOS — Mobile (Flutter)

Mobile-first surface (ADR-010): Flutter + Riverpod + GoRouter + Drift (SQLite)
+ Material 3. Primary client for the Brazil/Latin America market.

## Requirements
- Flutter SDK 3.24+ (Dart 3.5+)

## First-time setup
Platform folders (`android/`, `ios/`) are generated locally — they are not
committed. Run this once inside `apps/mobile`:

```bash
flutter create . --project-name mindos --platforms=android,ios
flutter pub get
```

## Run
```bash
# Point the app at your API (defaults to http://localhost:3000/v1)
flutter run --dart-define=API_BASE_URL=http://localhost:3000/v1
```

The F0 screen calls `GET /v1/health` on the API and shows whether mindOS is
alive end-to-end (mobile -> API).

## Quality
- `flutter analyze` — static analysis
- `flutter test` — tests

## Installing Flutter (local/CI-like Linux)
No package manager ships Flutter; install the stable SDK directly and add it to
`PATH` (clone it **outside** the repo so it never pollutes the working tree):

```bash
git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
flutter --version          # first run downloads the embedded Dart SDK
flutter config --no-analytics
```

Then, inside `apps/mobile`:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates Drift's app_database.g.dart
flutter analyze --no-fatal-infos
flutter test
```

For `flutter test`, the Dart toolchain alone is enough (no Android/iOS SDK
needed); `NativeDatabase.memory()` uses the bundled `sqlite3`.

