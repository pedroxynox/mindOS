import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/data/auth_session.dart';

/// Raised when an API call fails. [message] is user-facing (Spanish); [code]
/// is the machine-readable error code from the API body when present (e.g.
/// `ai_consent_required`), so callers can branch on it.
class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode, this.code]);
  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => 'ApiException($statusCode${code != null ? ' $code' : ''}): $message';
}

/// The ONE authenticated HTTP client of the app (D-016). Feature clients
/// (graph, tasks, growth, finance, …) are thin facades over it.
///
/// - Attaches the current Bearer token from [tokens].
/// - On a 401 it asks [tokens] to refresh the session ONCE and retries the
///   request; if the refresh is rejected the session ends (handled by the
///   token source) and the 401 surfaces as "Tu sesión expiró".
/// - Maps failures to user-friendly [ApiException]s.
///
/// Base URL comes from --dart-define=API_BASE_URL.
class MindosApi {
  MindosApi({
    required this.tokens,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final TokenSource tokens;
  final http.Client _client;
  final Duration timeout;

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/v1',
  );

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(
    String path, [
    Map<String, dynamic>? body,
    Duration? timeout,
  ]) =>
      _send('POST', path, body: body, timeout: timeout);

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path, [Map<String, dynamic>? body]) =>
      _send('DELETE', path, body: body);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    var res = await _once(method, uri, body, timeout);
    if (res.statusCode == 401 && await tokens.refresh()) {
      res = await _once(method, uri, body, timeout);
    }
    return _decode(res);
  }

  Future<http.Response> _once(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
    Duration? timeout,
  ) async {
    final token = tokens.accessToken;
    final headers = <String, String>{
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed =
          await _client.send(request).timeout(timeout ?? this.timeout);
      return await http.Response.fromStream(streamed);
    } catch (_) {
      throw const ApiException(
        'No se pudo conectar con el servidor. Revisa tu conexión.',
      );
    }
  }

  static dynamic _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    throw errorFor(res.statusCode, res.body);
  }

  /// Map an error response onto a friendly [ApiException]. Public so the
  /// streaming and binary-upload paths reuse the same messages.
  static ApiException errorFor(int status, String body) {
    final code = _codeFrom(body);
    switch (status) {
      case 401:
        return ApiException(
            'Tu sesión expiró. Inicia sesión de nuevo.', status, code);
      case 403:
        return ApiException(
            'No tienes permiso para hacer esto.', status, code);
      case 404:
        return ApiException('Esto ya no existe.', status, code);
      case 429:
        return ApiException(
            'Demasiadas solicitudes. Espera un momento.', status, code);
      case 503:
        return ApiException(
          'El asistente está despertando. Espera unos segundos e inténtalo de nuevo.',
          status,
          code,
        );
    }
    return ApiException(
      'No se pudo completar la acción. Inténtalo de nuevo.',
      status,
      code,
    );
  }

  static String? _codeFrom(String body) {
    if (body.isEmpty) return null;
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final code = json['code'];
        if (code is String) return code;
        final message = json['message'];
        if (message is Map<String, dynamic> && message['code'] is String) {
          return message['code'] as String;
        }
      }
    } catch (_) {}
    return null;
  }
}
