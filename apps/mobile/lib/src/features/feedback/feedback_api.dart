import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/api_providers.dart';
import '../shared/mindos_api.dart';

/// What a 👍/👎 is about (FR-3.5): a capture ("Lo que entendí"), an answer
/// (`query`, keyed by the question), the day's briefing (keyed by the local
/// day) or a node.
class FeedbackTarget {
  const FeedbackTarget(this.type, this.id);

  const FeedbackTarget.capture(String captureId) : this('capture', captureId);
  const FeedbackTarget.query(String question) : this('query', question);
  const FeedbackTarget.briefing(String dayKey) : this('briefing', dayKey);

  final String type;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is FeedbackTarget && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

/// `/v1/feedback` over the shared authenticated client.
class FeedbackApi {
  FeedbackApi(this._api);

  final MindosApi _api;

  /// Record (or replace) the vote on [target].
  Future<void> vote(FeedbackTarget target, {required bool useful}) async {
    await _api.post('/feedback', {
      'target_type': target.type,
      'target_id': target.id,
      'useful': useful,
    });
  }

  /// The current vote on [target]: true 👍, false 👎, null not voted.
  Future<bool?> current(FeedbackTarget target) async {
    final json = await _api.get('/feedback', query: {
      'target_type': target.type,
      'target_id': target.id,
    }) as Map<String, dynamic>?;
    final useful = json?['useful'];
    return useful is bool ? useful : null;
  }
}

final feedbackApiProvider = Provider<FeedbackApi>((ref) {
  return FeedbackApi(ref.watch(mindosApiProvider));
});

/// The user's vote on a target. A failed read shows as "not voted" — the
/// thumbs still work, they just start neutral.
final feedbackVoteProvider =
    FutureProvider.autoDispose.family<bool?, FeedbackTarget>((ref, target) async {
  try {
    return await ref.watch(feedbackApiProvider).current(target);
  } catch (_) {
    return null;
  }
});
