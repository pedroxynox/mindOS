import 'package:flutter/widgets.dart';
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
import 'features/growth/presentation/growth_screen.dart';
import 'features/home/home_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/tasks/presentation/tasks_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Application router (GoRouter) with an authentication guard and a bottom-nav
/// shell for the signed-in sections.
///
/// - `/login` and `/register` are the only routes reachable while signed out.
/// - The signed-in area is a [StatefulShellRoute] with four branches (Hoy,
///   Tareas, Crecimiento, Preguntar); focused screens (capture, insights, node
///   lists) push over the shell on the root navigator.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
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

      // Signed-in sections with a bottom navigation bar.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/tasks', builder: (_, __) => const TasksScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/growth', builder: (_, __) => const GrowthScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/ask', builder: (_, __) => const AskScreen()),
            ],
          ),
        ],
      ),

      // Focused screens pushed over the shell (root navigator).
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/capture',
        builder: (_, __) => const CaptureScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/capture/:id/insights',
        builder: (_, state) =>
            CaptureInsightsScreen(captureId: state.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/graph/:type',
        builder: (_, state) =>
            NodesListScreen(type: state.pathParameters['type']!),
      ),
    ],
  );
});
