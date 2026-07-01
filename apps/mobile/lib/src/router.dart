import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/health/health_screen.dart';

/// Application router (GoRouter).
///
/// F0 has a single route (the health screen that proves the end-to-end
/// connection to the API). Real routes arrive from F1.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HealthScreen(),
      ),
    ],
  );
});
