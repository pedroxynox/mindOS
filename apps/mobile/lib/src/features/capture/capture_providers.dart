import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/capture_api_client.dart';
import 'data/capture_repository.dart';
import 'data/local/app_database.dart';
import 'data/local/capture_tables.dart';
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

/// Access-token source for the API client.
///
/// Placeholder until the mobile auth feature lands (F4): reads a build-time
/// token so the wiring compiles and can be integration-tested. Replace with the
/// real auth store when available.
final accessTokenProvider = Provider<Future<String?> Function()>((ref) {
  return () async {
    const token = String.fromEnvironment('API_ACCESS_TOKEN', defaultValue: '');
    return token.isEmpty ? null : token;
  };
});

/// HTTP client for the Capture API.
final captureApiClientProvider = Provider<CaptureApiClient>((ref) {
  return HttpCaptureApiClient(tokenProvider: ref.watch(accessTokenProvider));
});

/// Reads recorded audio bytes from disk (injected into [SyncService]).
final audioBytesReaderProvider = Provider<AudioBytesReader>((ref) {
  return (String localPath) => File(localPath).readAsBytes();
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
