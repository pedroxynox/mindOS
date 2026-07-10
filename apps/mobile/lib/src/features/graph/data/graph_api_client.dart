import 'dart:convert';

import 'package:http/http.dart' as http;

import 'briefing_models.dart';
import 'graph_models.dart';
import 'query_models.dart';

/// Raised when a graph read fails. [message] is user-facing (Spanish).
class GraphApiException implements Exception {
  const GraphApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'GraphApiException($statusCode): $message';
}

/// Read-only client for the knowledge-graph endpoints (`/v1/graph/*`).
///
/// Every request is authenticated with the signed-in user's access token,
/// obtained lazily via [tokenProvider] so the client always uses the current
/// session. Base URL comes from --dart-define=API_BASE_URL (defaults to local).
class GraphApiClient {
  GraphApiClient({
    required this.tokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final Future<String?> Function() tokenProvider;
  final http.Client _client;
  final Duration timeout;

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/v1',
  );

  Future<GraphSummary> summary() async {
    final json = await _get('/graph/summary');
    return GraphSummary.fromJson(json as Map<String, dynamic>);
  }

  Future<GraphNodePage> listNodes(
    String type, {
    String? cursor,
    int limit = 50,
  }) async {
    final params = <String, String>{'type': type, 'limit': '$limit'};
    if (cursor != null) params['cursor'] = cursor;
    final json = await _get('/graph/nodes', params) as Map<String, dynamic>;
    final data = (json['data'] as List<dynamic>? ?? [])
        .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
        .toList();
    return GraphNodePage(data: data, nextCursor: json['next_cursor'] as String?);
  }

  Future<CaptureEntities> captureEntities(String captureId) async {
    final json = await _get('/graph/captures/$captureId/entities');
    return CaptureEntities.fromJson(json as Map<String, dynamic>);
  }

  /// The proactive Daily Briefing (tasks + upcoming events).
  Future<Briefing> briefing() async {
    final json = await _get('/briefing');
    return Briefing.fromJson(json as Map<String, dynamic>);
  }

  /// Ask a natural-language question; the answer is grounded on the user's own
  /// notes. Uses a longer timeout to absorb the AI service's cold start.
  Future<QueryAnswer> ask(String question) async {
    final json = await _post(
      '/query',
      {'question': question},
      timeout: const Duration(seconds: 100),
    );
    return QueryAnswer.fromJson(json as Map<String, dynamic>);
  }

  Future<dynamic> _post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final token = await tokenProvider();
    late http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'accept': 'application/json',
              'content-type': 'application/json',
              if (token != null && token.isNotEmpty)
                'authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout ?? this.timeout);
    } catch (_) {
      throw const GraphApiException(
        'No se pudo conectar con el servidor. Revisa tu conexión.',
      );
    }

    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body);
    }
    if (res.statusCode == 401) {
      throw const GraphApiException(
        'Tu sesión expiró. Inicia sesión de nuevo.',
        401,
      );
    }
    if (res.statusCode == 503) {
      throw const GraphApiException(
        'El asistente está despertando. Espera unos segundos e inténtalo de nuevo.',
        503,
      );
    }
    throw GraphApiException(
      'No pude responder ahora mismo. Inténtalo de nuevo.',
      res.statusCode,
    );
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final token = await tokenProvider();
    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: query,
    );
    late http.Response res;
    try {
      res = await _client.get(
        uri,
        headers: {
          'accept': 'application/json',
          if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
        },
      ).timeout(timeout);
    } catch (_) {
      throw const GraphApiException(
        'No se pudo conectar con el servidor. Revisa tu conexión.',
      );
    }

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    if (res.statusCode == 401) {
      throw const GraphApiException('Tu sesión expiró. Inicia sesión de nuevo.', 401);
    }
    throw GraphApiException(
      'No se pudo cargar la información. Inténtalo de nuevo.',
      res.statusCode,
    );
  }
}
