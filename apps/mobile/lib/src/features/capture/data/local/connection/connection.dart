import 'package:drift/drift.dart';

// Platform-conditional database opener. The concrete implementation is selected
// at compile time: native (mobile/desktop) uses a file-backed SQLite database;
// web uses Drift's WASM build (sqlite3.wasm + drift_worker.js served from web/).
export 'unsupported.dart'
    if (dart.library.io) 'native.dart'
    if (dart.library.js_interop) 'web.dart';

/// Marker so callers import a single, platform-agnostic entry point.
typedef DriftExecutor = QueryExecutor;
