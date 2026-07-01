import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of a health check against the mindOS API.
class ApiHealth {
  const ApiHealth({
    required this.status,
    required this.service,
    required this.timestamp,
  });

  final String status;
  final String service;
  final String timestamp;

  factory ApiHealth.fromJson(Map<String, dynamic> json) {
    return ApiHealth(
      status: json['status'] as String,
      service: json['service'] as String,
      timestamp: json['timestamp'] as String,
    );
  }
}

/// Talks to the NestJS API. Base URL is configurable at build time via
/// --dart-define=API_BASE_URL=... (defaults to localhost for development).
class HealthRepository {
  HealthRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/v1',
  );

  Future<ApiHealth> fetchHealth() async {
    final response = await _client.get(Uri.parse('$_baseUrl/health'));
    if (response.statusCode != 200) {
      throw Exception('API health check failed (${response.statusCode})');
    }
    return ApiHealth.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
