import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../capture/capture_providers.dart';
import '../graph/data/graph_models.dart';
import '../graph/graph_providers.dart';
import '../graph/presentation/node_type_style.dart';
import '../health/health_providers.dart';

/// Authenticated landing screen: a welcome, the live connection status, an
/// overview of the knowledge the brain has extracted (tappable per type), the
/// primary "capture" action and recent captures (tap to see what was
/// understood).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final health = ref.watch(apiHealthProvider);
    final captures = ref.watch(capturesStreamProvider);
    final summary = ref.watch(graphSummaryProvider);

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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(graphSummaryProvider);
          try {
            await ref.read(graphSummaryProvider.future);
          } catch (_) {
            // Errors are surfaced inline by the summary section; swallow here so
            // the refresh indicator dismisses cleanly.
          }
        },
        child: ListView(
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
            Text('Tu conocimiento', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _SummarySection(summary: summary),
            const SizedBox(height: 24),
            Text('Capturas recientes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            captures.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) =>
                  const Text('No se pudieron cargar las capturas.'),
              data: (items) {
                if (items.isEmpty) {
                  return _EmptyState(theme: theme);
                }
                return Column(
                  children: [
                    for (final c in items.take(6))
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
                          subtitle: Text(
                            c.serverId != null
                                ? 'Ver lo que entendí'
                                : 'Sincronizando...',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          // Only synced captures have a server id to inspect.
                          enabled: c.serverId != null,
                          onTap: c.serverId == null
                              ? null
                              : () =>
                                  context.push('/capture/${c.serverId}/insights'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
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

/// Chips with per-type counts of extracted knowledge; tap to see the full list.
class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary});
  final AsyncValue<GraphSummary> summary;

  @override
  Widget build(BuildContext context) {
    return summary.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const Text('No se pudo cargar tu conocimiento.'),
      data: (data) {
        final counts = data.counts;
        if (counts.isEmpty) {
          return Text(
            'Aún no hay conocimiento extraído. Crea una captura y mindOS empezará a conectar personas, tareas y proyectos.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          );
        }
        const order = [
          'task',
          'person',
          'project',
          'event',
          'topic',
          'decision',
          'note'
        ];
        final types = counts.keys.toList()
          ..sort((a, b) {
            final ia = order.indexOf(a), ib = order.indexOf(b);
            return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
          });
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final type in types)
              _CountChip(type: type, count: counts[type] ?? 0),
          ],
        );
      },
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.type, required this.count});
  final String type;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style = NodeTypeStyle.of(type);
    final label = count == 1 ? style.singular : style.plural;
    return ActionChip(
      avatar: Icon(style.icon, size: 18, color: style.color),
      label: Text('$count $label'),
      backgroundColor: style.color.withValues(alpha: 0.10),
      side: BorderSide(color: style.color.withValues(alpha: 0.30)),
      onPressed: () => context.push('/graph/$type'),
    );
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
          Text('Aún no hay capturas', style: theme.textTheme.titleSmall),
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
