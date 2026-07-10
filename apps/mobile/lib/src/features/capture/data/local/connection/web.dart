import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Web connection: Drift's WASM SQLite. The `sqlite3.wasm` and `drift_worker.js`
/// assets are served from the app's web root (see apps/mobile/web/). Data is
/// persisted in the browser (IndexedDB / OPFS when available) so the offline
/// outbox works the same way as on mobile.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'mindos',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}
