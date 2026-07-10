import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../capture/capture_providers.dart';
import '../graph/graph_providers.dart';
import '../graph/presentation/node_type_style.dart';
import '../../widgets/cosmic_background.dart';

/// "Memoria" — the navigable universe of what mindOS knows about you: the
/// knowledge it extracted (people, projects, topics, events), your tasks and
/// growth, and a timeline of recent captures. A hub, not a folder tree.
class MemoryHubScreen extends ConsumerWidget {
  const MemoryHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(graphSummaryProvider);
    final captures = ref.watch(capturesStreamProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Memoria'),
      ),
      body: CosmicBackground(
        haloAlignment: const Alignment(0.8, -0.7),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(graphSummaryProvider);
              try {
                await ref.read(graphSummaryProvider.future);
              } catch (_) {}
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text('Tu conocimiento',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                summary.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) =>
                      const Text('No se pudo cargar tu conocimiento.'),
                  data: (data) {
                    final counts = data.counts;
                    if (counts.isEmpty) {
                      return Text(
                        'Aún no hay conocimiento. Captura algo y empezaré a conectar personas, proyectos e ideas.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      );
                    }
                    const order = [
                      'task', 'person', 'project', 'event', 'topic', 'decision',
                    ];
                    final types = counts.keys.toList()
                      ..sort((a, b) {
                        final ia = order.indexOf(a), ib = order.indexOf(b);
                        return (ia == -1 ? 99 : ia)
                            .compareTo(ib == -1 ? 99 : ib);
                      });
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final t in types)
                          _CountChip(type: t, count: counts[t] ?? 0),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text('Explorar',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _HubTile(
                  icon: Icons.check_circle_outline,
                  title: 'Tareas',
                  subtitle: 'Ordenadas por prioridad',
                  onTap: () => context.push('/tasks'),
                ),
                const SizedBox(height: 10),
                _HubTile(
                  icon: Icons.trending_up,
                  title: 'Crecimiento',
                  subtitle: 'Metas, hábitos y reflexión',
                  onTap: () => context.push('/growth'),
                ),
                const SizedBox(height: 28),
                Text('Capturas recientes',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                captures.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) =>
                      const Text('No se pudieron cargar las capturas.'),
                  data: (items) {
                    if (items.isEmpty) {
                      return Text(
                        'Tus capturas aparecerán aquí como una línea de tiempo.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      );
                    }
                    return Column(
                      children: [
                        for (final c in items.take(8))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                leading: Icon(Icons.bubble_chart_outlined,
                                    color: theme.colorScheme.primary),
                                title: Text(
                                  (c.content?.trim().isNotEmpty ?? false)
                                      ? c.content!.trim()
                                      : '(sin contenido)',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(c.serverId != null
                                    ? 'Ver lo que entendí'
                                    : 'Sincronizando...'),
                                trailing: const Icon(Icons.chevron_right),
                                enabled: c.serverId != null,
                                onTap: c.serverId == null
                                    ? null
                                    : () => context
                                        .push('/capture/${c.serverId}/insights'),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
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
      onPressed: () => context.push('/graph/$type'),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
