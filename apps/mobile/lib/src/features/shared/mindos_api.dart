import 'dart:convert';

import 'package:http/http.dart' as http;

/// Raised when an API call fails. [message] is user-facing (Spanish).
class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Small authenticated HTTP client for the mindOS API, shared by the feature
/// clients (tasks, growth, ...). Attaches the current session's Bearer token
/// (via [tokenProvider]) and maps failures to user-friendly [ApiException]s.
/// Base URL comes from --dart-define=API_BASE_URL.
class MindosApi {
  MindosApi({
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

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body: body);

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) =>
      _send('PATCH', path, body: body);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final token = await tokenProvider();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };

    late http.Response res;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      res = await http.Response.fromStream(streamed);
    } catch (_) {
      throw const ApiException(
        'No se pudo conectar con el servidor. Revisa tu conexión.',
      );
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    if (res.statusCode == 401) {
      throw const ApiException('Tu sesión expiró. Inicia sesión de nuevo.', 401);
    }
    throw ApiException(
      'No se pudo completar la acción. Inténtalo de nuevo.',
      res.statusCode,
    );
  }
}
