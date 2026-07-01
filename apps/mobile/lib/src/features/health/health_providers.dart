import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'health_repository.dart';

/// Singleton repository provider.
final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepository();
});

/// Async health status of the API, consumed by the UI.
final apiHealthProvider = FutureProvider<ApiHealth>((ref) async {
  final repository = ref.watch(healthRepositoryProvider);
  return repository.fetchHealth();
});
