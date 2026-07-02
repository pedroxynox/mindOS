import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/capture/presentation/capture_screen.dart';
import 'features/health/health_screen.dart';

/// Application router (GoRouter).
///
/// `/` is the F0 health screen (proves the end-to-end connection to the API);
/// `/capture` is the F1 offline-first capture screen.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HealthScreen(),
      ),
      GoRoute(
        path: '/capture',
        builder: (context, state) => const CaptureScreen(),
      ),
    ],
  );
});
