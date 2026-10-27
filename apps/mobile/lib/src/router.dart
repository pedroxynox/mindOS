import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/account/presentation/account_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_providers.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/register_screen.dart';
import 'features/capture/presentation/capture_screen.dart';
import 'features/finance/presentation/finance_screen.dart';
import 'features/graph/presentation/ask_screen.dart';
import 'features/graph/presentation/capture_insights_screen.dart';
import 'features/graph/presentation/entity_screen.dart';
import 'features/graph/presentation/nodes_list_screen.dart';
import 'features/growth/presentation/growth_screen.dart';
import 'features/home/home_screen.dart';
import 'features/memory/memory_hub_screen.dart';
import 'features/tasks/presentation/tasks_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Application router (GoRouter) with an authentication guard.
///
/// - `/login` and `/register` are the only routes reachable while signed out.
/// - Signed in, Hoy (`/`) is the base; every other section (Conversar,
///   Memoria, Capturar, Tareas, Crecimiento, …) is pushed over it with a back
///   arrow, matching the chat / + / search bottom bar of the design.
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

      // Home is the base; the other sections open over it (with a back arrow),
      // matching the design's chat / + / search bottom bar on Hoy.
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/ask', builder: (_, __) => const AskScreen()),
      GoRoute(path: '/memory', builder: (_, __) => const MemoryHubScreen()),
      GoRoute(path: '/capture', builder: (_, __) => const CaptureScreen()),
      GoRoute(
        path: '/capture/:id/insights',
        builder: (_, state) =>
            CaptureInsightsScreen(captureId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/node/:id',
        builder: (_, state) =>
            EntityScreen(nodeId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/graph/:type',
        builder: (_, state) =>
            NodesListScreen(type: state.pathParameters['type']!),
      ),
      GoRoute(path: '/tasks', builder: (_, __) => const TasksScreen()),
      GoRoute(path: '/growth', builder: (_, __) => const GrowthScreen()),
      GoRoute(path: '/finance', builder: (_, __) => const FinanceScreen()),
      GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
    ],
  );
});
