import 'dart:convert';

import 'package:http/http.dart' as http;

/// Tokens returned by the API after a successful auth call
/// (mirrors `AuthTokens` in the NestJS backend).
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresIn: (json['expiresIn'] as num).toInt(),
    );
  }
}

/// Raised when the API rejects the credentials or the request is invalid.
/// [message] is safe to show to the user (already user-facing in Spanish).
class AuthException implements Exception {
  const AuthException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AuthException($statusCode): $message';
}

/// Talks to the NestJS auth endpoints (`/v1/auth/*`). The base URL is provided
/// at build time via --dart-define=API_BASE_URL=... (defaults to localhost).
class AuthApiClient {
  AuthApiClient({http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/v1',
  );

  Future<AuthTokens> register(String email, String password) =>
      _credentials('register', email, password);

  Future<AuthTokens> login(String email, String password) =>
      _credentials('login', email, password);

  Future<AuthTokens> _credentials(
    String path,
    String email,
    String password,
  ) async {
    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/auth/$path'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(timeout);
    } catch (_) {
      throw const AuthException(
        'No se pudo conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.',
      );
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      return AuthTokens.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw AuthException(_messageFor(response), response.statusCode);
  }

  /// Best-effort session revocation. Never throws — logging out locally must
  /// always succeed even if the network call fails.
  Future<void> logout(String refreshToken) async {
    try {
      await _client
          .post(
            Uri.parse('$_baseUrl/auth/logout'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(timeout);
    } catch (_) {
      // Ignore: the local session is cleared regardless.
    }
  }

  /// Map an error response onto a friendly, user-facing Spanish message.
  String _messageFor(http.Response response) {
    switch (response.statusCode) {
      case 401:
        return 'Correo o contraseña incorrectos.';
      case 409:
        return 'Ese correo ya está registrado. Inicia sesión.';
      case 429:
        return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
      case 400:
        return 'Revisa el correo y que la contraseña tenga al menos 8 caracteres.';
      default:
        return 'Algo salió mal. Inténtalo de nuevo en unos segundos.';
    }
  }
}
