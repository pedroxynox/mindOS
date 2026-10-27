import '../../shared/mindos_api.dart';
import 'briefing_models.dart';
import 'graph_models.dart';
import 'query_models.dart';

/// Facade for the knowledge-graph, briefing and query endpoints over the single
/// authenticated [MindosApi] client (D-016: one client, one error/refresh
/// policy).
class GraphApiClient {
  GraphApiClient(this._api);

  final MindosApi _api;

  Future<GraphSummary> summary() async {
    final json = await _api.get('/graph/summary');
    return GraphSummary.fromJson(json as Map<String, dynamic>);
  }

  Future<GraphNodePage> listNodes(
    String type, {
    String? cursor,
    int limit = 50,
  }) async {
    final params = <String, String>{'type': type, 'limit': '$limit'};
    if (cursor != null) params['cursor'] = cursor;
    final json =
        await _api.get('/graph/nodes', query: params) as Map<String, dynamic>;
    final data = (json['data'] as List<dynamic>? ?? [])
        .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
        .toList();
    return GraphNodePage(data: data, nextCursor: json['next_cursor'] as String?);
  }

  Future<CaptureEntities> captureEntities(String captureId) async {
    final json = await _api.get('/graph/captures/$captureId/entities');
    return CaptureEntities.fromJson(json as Map<String, dynamic>);
  }

  /// The proactive Daily Briefing.
  Future<Briefing> briefing() async {
    final json = await _api.get('/briefing');
    return Briefing.fromJson(json as Map<String, dynamic>);
  }

  /// Ask a natural-language question; the answer is grounded on the user's own
  /// notes. Uses a longer timeout to absorb the AI service's cold start.
  Future<QueryAnswer> ask(String question) async {
    final json = await _api.post(
      '/query',
      {'question': question},
      const Duration(seconds: 100),
    );
    return QueryAnswer.fromJson(json as Map<String, dynamic>);
  }
}
