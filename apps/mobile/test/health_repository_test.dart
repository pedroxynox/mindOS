import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/health/health_repository.dart';

void main() {
  group('ApiHealth', () {
    test('parses a valid health payload', () {
      final health = ApiHealth.fromJson({
        'status': 'ok',
        'service': 'api',
        'timestamp': '2026-07-01T09:00:00Z',
      });

      expect(health.status, 'ok');
      expect(health.service, 'api');
      expect(health.timestamp, '2026-07-01T09:00:00Z');
    });
  });
}
