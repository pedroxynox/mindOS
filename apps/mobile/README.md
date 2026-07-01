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
