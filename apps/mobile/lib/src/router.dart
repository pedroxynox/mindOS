import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/auth_providers.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/register_screen.dart';
import 'features/capture/presentation/capture_screen.dart';
import 'features/graph/presentation/ask_screen.dart';
import 'features/graph/presentation/capture_insights_screen.dart';
import 'features/graph/presentation/nodes_list_screen.dart';
import 'features/home/home_screen.dart';

/// Application router (GoRouter) with an authentication guard.
///
/// - `/login` and `/register` are the only routes reachable while signed out.
/// - Everything else requires a session; unauthenticated users are redirected
///   to `/login`. Signed-in users visiting an auth route are sent to `/`.
/// The router refreshes whenever the auth state changes.
final routerProvider = Provider<GoRouter>((ref) {
  // Bridges Riverpod auth-state changes to GoRouter's refresh mechanism.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider).status;
      final loggedIn = status == AuthStatus.authenticated;
      final loc = state.matchedLocation;
      final onAuthRoute = loc == '/login' || loc == '/register';

      if (!loggedIn) {
        return onAuthRoute ? null : '/login';
      }
      if (onAuthRoute) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/capture', builder: (_, __) => const CaptureScreen()),
      GoRoute(path: '/ask', builder: (_, __) => const AskScreen()),
      GoRoute(
        path: '/capture/:id/insights',
        builder: (_, state) =>
            CaptureInsightsScreen(captureId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/graph/:type',
        builder: (_, state) =>
            NodesListScreen(type: state.pathParameters['type']!),
      ),
    ],
  );
});
