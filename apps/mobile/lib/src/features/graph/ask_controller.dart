import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/graph_api_client.dart';
import 'data/query_models.dart';
import 'graph_providers.dart';

/// UI state for the "Ask mindOS" screen.
class AskState {
  const AskState({
    this.isLoading = false,
    this.question,
    this.answer,
    this.errorMessage,
  });

  final bool isLoading;
  final String? question;
  final QueryAnswer? answer;
  final String? errorMessage;

  bool get hasResult => answer != null || errorMessage != null;
}

/// Runs a single question against the API and exposes loading/answer/error.
class AskController extends StateNotifier<AskState> {
  AskController(this._client) : super(const AskState());

  final GraphApiClient _client;

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.isLoading) return;
    state = AskState(isLoading: true, question: q);
    try {
      final answer = await _client.ask(q);
      state = AskState(question: q, answer: answer);
    } on GraphApiException catch (e) {
      state = AskState(question: q, errorMessage: e.message);
    } catch (_) {
      state = AskState(
        question: q,
        errorMessage: 'No pude responder ahora mismo. Inténtalo de nuevo.',
      );
    }
  }

  void reset() => state = const AskState();
}

final askControllerProvider =
    StateNotifierProvider.autoDispose<AskController, AskState>((ref) {
  return AskController(ref.watch(graphApiClientProvider));
});
