import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../capture/capture_providers.dart';
import '../health/health_providers.dart';

/// Authenticated landing screen: a welcome, the live connection status, the
/// primary "capture" action and a quick glance at recent captures.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final health = ref.watch(apiHealthProvider);
    final captures = ref.watch(capturesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('mindOS'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/capture'),
        icon: const Icon(Icons.edit_note),
        label: const Text('Capturar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Tu mente, organizada',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Escribe lo que tengas en mente y mindOS lo entiende y ordena por ti.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          _StatusCard(
            child: health.when(
              loading: () => const _StatusRow(
                icon: Icons.sync,
                text: 'Conectando con mindOS...',
              ),
              error: (_, __) => _StatusRow(
                icon: Icons.cloud_off,
                text: 'Sin conexión con el servidor',
                color: theme.colorScheme.error,
              ),
              data: (_) => _StatusRow(
                icon: Icons.check_circle,
                text: 'mindOS está en línea',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Capturas recientes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          captures.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const Text('No se pudieron cargar las capturas.'),
            data: (items) {
              if (items.isEmpty) {
                return _EmptyState(theme: theme);
              }
              return Column(
                children: [
                  for (final c in items.take(5))
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.notes),
                        title: Text(
                          (c.content?.trim().isNotEmpty ?? false)
                              ? c.content!.trim()
                              : '(sin contenido)',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.lightbulb_outline,
              size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Aún no hay capturas',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Toca "Capturar" para escribir tu primera idea.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
