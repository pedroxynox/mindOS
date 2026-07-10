import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/briefing_models.dart';
import 'data/graph_api_client.dart';
import 'data/graph_models.dart';

/// Authenticated client for the knowledge-graph endpoints.
final graphApiClientProvider = Provider<GraphApiClient>((ref) {
  final store = ref.watch(tokenStoreProvider);
  return GraphApiClient(tokenProvider: () async => store.accessToken);
});

/// Per-type counts of derived knowledge (home overview). Auto-refreshes when
/// invalidated (e.g. after creating a capture).
final graphSummaryProvider = FutureProvider.autoDispose<GraphSummary>((ref) {
  return ref.watch(graphApiClientProvider).summary();
});

/// The list of derived nodes of a given type (task/person/project/...).
final nodesByTypeProvider =
    FutureProvider.autoDispose.family<List<GraphNode>, String>((ref, type) async {
  final page = await ref.watch(graphApiClientProvider).listNodes(type);
  return page.data;
});

/// The Daily Briefing (tasks + upcoming events). Auto-refreshes when invalidated.
final briefingProvider = FutureProvider.autoDispose<Briefing>((ref) {
  return ref.watch(graphApiClientProvider).briefing();
});

/// What the brain extracted from one capture. Consumed by the insights screen,
/// which re-reads it while the capture is still being processed.
final captureEntitiesProvider = FutureProvider.autoDispose
    .family<CaptureEntities, String>((ref, captureId) async {
  return ref.watch(graphApiClientProvider).captureEntities(captureId);
});
