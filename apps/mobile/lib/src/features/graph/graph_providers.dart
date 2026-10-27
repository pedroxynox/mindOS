import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../shared/api_providers.dart';
import 'data/briefing_models.dart';
import 'data/graph_api_client.dart';
import 'data/graph_models.dart';

/// Graph / briefing / query facade over the single authenticated client.
final graphApiClientProvider = Provider<GraphApiClient>((ref) {
  return GraphApiClient(ref.watch(mindosApiProvider));
});

/// Per-type counts of derived knowledge (Memoria overview). Auto-refreshes when
/// invalidated (e.g. after creating a capture).
final graphSummaryProvider = FutureProvider.autoDispose<GraphSummary>((ref) {
  return ref.watch(graphApiClientProvider).summary();
});

/// The Daily Briefing shown on Hoy. Auto-refreshes when invalidated.
final briefingProvider = FutureProvider.autoDispose<Briefing>((ref) async {
  await settingsReady(ref); // "today" in the user's timezone
  return ref.watch(graphApiClientProvider).briefing();
});

/// What the brain extracted from one capture. Consumed by the insights screen,
/// which re-reads it while the capture is still being processed.
final captureEntitiesProvider = FutureProvider.autoDispose
    .family<CaptureEntities, String>((ref, captureId) async {
  return ref.watch(graphApiClientProvider).captureEntities(captureId);
});

/// One entity (person, project, topic...) with its captures and links.
final entityProvider =
    FutureProvider.autoDispose.family<EntityDetail, String>((ref, id) async {
  return ref.watch(graphApiClientProvider).entity(id);
});

/// Paginated list of derived nodes of one type ("Cargar más").
class NodesListState {
  const NodesListState({
    this.items = const [],
    this.nextCursor,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
  });

  final List<GraphNode> items;
  final String? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;

  bool get hasMore => nextCursor != null;

  NodesListState copyWith({
    List<GraphNode>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
  }) {
    return NodesListState(
      items: items ?? this.items,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: errorMessage,
    );
  }
}

class NodesListController extends StateNotifier<NodesListState> {
  NodesListController(this._client, this.type, {this.pageSize = 50})
      : super(const NodesListState(isLoading: true)) {
    refresh();
  }

  final GraphApiClient _client;
  final String type;
  final int pageSize;

  Future<void> refresh() async {
    state = const NodesListState(isLoading: true);
    try {
      final page = await _client.listNodes(type, limit: pageSize);
      state = NodesListState(items: page.data, nextCursor: page.nextCursor);
    } catch (_) {
      state = const NodesListState(
        errorMessage: 'No se pudo cargar. Desliza para reintentar.',
      );
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page =
          await _client.listNodes(type, cursor: cursor, limit: pageSize);
      state = NodesListState(
        items: [...state.items, ...page.data],
        nextCursor: page.nextCursor,
      );
    } catch (_) {
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: 'No se pudieron cargar más elementos.',
      );
    }
  }
}

final nodesListProvider = StateNotifierProvider.autoDispose
    .family<NodesListController, NodesListState, String>((ref, type) {
  return NodesListController(ref.watch(graphApiClientProvider), type);
});
