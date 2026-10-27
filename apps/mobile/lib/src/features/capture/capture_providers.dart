import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../shared/api_providers.dart';
import 'data/capture_api_client.dart';
import 'data/capture_history_api.dart';
import 'data/capture_repository.dart';
import 'data/local/app_database.dart';
import 'data/platform/file_reader.dart';
import 'data/sync_service.dart';

/// Singleton local database. Disposed with the provider container.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Repository the UI uses for the optimistic offline write path.
final captureRepositoryProvider = Provider<CaptureRepository>((ref) {
  return CaptureRepository(ref.watch(appDatabaseProvider));
});

/// Observable list of local captures for the UI.
final capturesStreamProvider = StreamProvider<List<LocalCapture>>((ref) {
  return ref.watch(captureRepositoryProvider).watchCaptures();
});

/// HTTP client for the Capture API (shares the session token source, so an
/// expired access token is refreshed instead of failing the capture).
final captureApiClientProvider = Provider<CaptureApiClient>((ref) {
  return HttpCaptureApiClient(tokens: ref.watch(tokenSourceProvider));
});

/// Reads recorded audio bytes from disk (injected into [SyncService]).
final audioBytesReaderProvider = Provider<AudioBytesReader>((ref) {
  return (String localPath) => readLocalFileBytes(localPath);
});

/// The outbox drain service.
final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    db: ref.watch(appDatabaseProvider),
    api: ref.watch(captureApiClientProvider),
    audioReader: ref.watch(audioBytesReaderProvider),
  );
});

/// Drives the [SyncService] whenever connectivity is (re)gained, per design
/// §3.3. Watch this provider from the app root to keep the outbox draining.
final syncOnConnectivityProvider = Provider<void>((ref) {
  final sync = ref.watch(syncServiceProvider);
  final subscription =
      Connectivity().onConnectivityChanged.listen((results) {
    final online =
        results.any((r) => r != ConnectivityResult.none);
    if (online) {
      // Fire-and-forget; drainOnce guards against overlapping runs.
      unawaited(sync.drainOnce());
    }
  });
  ref.onDispose(subscription.cancel);
});

/// Server-side capture history (any device sees the same memory).
final captureHistoryApiProvider = Provider<CaptureHistoryApi>((ref) {
  return CaptureHistoryApi(ref.watch(mindosApiProvider));
});

final serverCapturesProvider =
    FutureProvider.autoDispose<List<ServerCapture>>((ref) {
  return ref.watch(captureHistoryApiProvider).recent();
});
