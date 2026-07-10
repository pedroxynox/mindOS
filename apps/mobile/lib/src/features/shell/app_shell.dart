import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The signed-in shell with the minimal permanent navigation from the visual
/// bible: Hoy · Conversar · Capturar · Memoria. Three are branches (indexed
/// stack); "Capturar" is the universal capture action and opens over the shell.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  // Branch order: 0 Hoy, 1 Conversar, 2 Memoria.
  // Destination order: 0 Hoy, 1 Conversar, 2 Capturar (action), 3 Memoria.
  static const _captureDestination = 2;

  int _branchToDestination(int branch) => branch < 2 ? branch : branch + 1;
  int _destinationToBranch(int destination) =>
      destination < _captureDestination ? destination : destination - 1;

  void _onSelect(BuildContext context, int destination) {
    if (destination == _captureDestination) {
      context.push('/capture');
      return;
    }
    final branch = _destinationToBranch(destination);
    navigationShell.goBranch(
      branch,
      initialLocation: branch == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _branchToDestination(navigationShell.currentIndex),
        onDestinationSelected: (i) => _onSelect(context, i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.blur_on_outlined),
            selectedIcon: Icon(Icons.blur_on),
            label: 'Hoy',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Conversar',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle, color: theme.colorScheme.primary),
            label: 'Capturar',
          ),
          const NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore),
            label: 'Memoria',
          ),
        ],
      ),
    );
  }
}
