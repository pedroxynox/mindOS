import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../graph/data/briefing_models.dart';
import '../graph/graph_providers.dart';
import '../tasks/data/task_model.dart';
import '../tasks/tasks_providers.dart';
import '../../widgets/cosmic_background.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/presence_orb.dart';

/// "Hoy" — the presence screen. mindOS greets contextually and surfaces only
/// what matters now (never more than three priorities), around the living
/// sphere. Tapping the sphere opens the conversation.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final briefing = ref.watch(briefingProvider);
    final tasks = ref.watch(tasksListProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('mindOS'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: Icon(Icons.logout,
                color: theme.colorScheme.onSurfaceVariant, size: 20),
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),
      body: CosmicBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(briefingProvider);
              ref.invalidate(tasksListProvider);
              try {
                await ref.read(briefingProvider.future);
              } catch (_) {}
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                const SizedBox(height: 8),
                Text(
                  _greeting(),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                _ContextLine(briefing: briefing),
                const SizedBox(height: 12),
                // The living presence — tap to converse.
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/ask'),
                    child: const PresenceOrb(size: 172),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'Toca para conversar',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Ahora',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                FadeInUp(child: _Priorities(tasks: tasks, briefing: briefing)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
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
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

/// The one-line contextual message under the greeting (from the briefing).
class _ContextLine extends StatelessWidget {
  const _ContextLine({required this.briefing});
  final AsyncValue<Briefing> briefing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35);
    return briefing.when(
      loading: () => Text('Poniéndome al día...', style: style),
      error: (_, __) =>
          Text('Estoy aquí cuando me necesites.', style: style),
      data: (b) {
        final parts = <String>[];
        if (b.taskTotal > 0) {
          parts.add(b.taskTotal == 1 ? '1 tarea' : '${b.taskTotal} tareas');
        }
        if (b.upcomingEvents.isNotEmpty) {
          parts.add(b.upcomingEvents.length == 1
              ? '1 evento próximo'
              : '${b.upcomingEvents.length} eventos próximos');
        }
        final msg = parts.isEmpty
            ? 'Todo despejado. Estoy aquí cuando me necesites.'
            : 'Tienes ${parts.join(' y ')}.';
        return Text(msg, style: style);
      },
    );
  }
}

/// Up to three priorities: pending tasks first, then upcoming events.
class _Priorities extends ConsumerWidget {
  const _Priorities({required this.tasks, required this.briefing});
  final AsyncValue<List<Task>> tasks;
  final AsyncValue<Briefing> briefing;

  Color _dot(TaskPriority p) => switch (p) {
        TaskPriority.high => const Color(0xFFFF6B6B),
        TaskPriority.medium => const Color(0xFFF7C948),
        TaskPriority.low => const Color(0xFF57D9A3),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return tasks.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _hint(theme, 'No pude cargar tus prioridades.'),
      data: (all) {
        final pending = all.where((t) => !t.done).take(3).toList();
        if (pending.isNotEmpty) {
          return Column(
            children: [
              for (final t in pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      onTap: () => context.go('/tasks'),
                      leading: Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: _dot(t.priority),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _dot(t.priority).withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      title: Text(
                        (t.title ?? '').trim().isEmpty
                            ? '(sin título)'
                            : t.title!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('Prioridad ${t.priority.label.toLowerCase()}'),
                      trailing: Icon(Icons.chevron_right,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          );
        }

        // Fallback: upcoming events, else a calm prompt.
        final events = briefing.valueOrNull?.upcomingEvents ?? const [];
        if (events.isNotEmpty) {
          return Column(
            children: [
              for (final e in events.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: Icon(Icons.event_outlined,
                          color: theme.colorScheme.primary),
                      title: Text(
                        (e.title ?? '').trim().isEmpty
                            ? 'Evento'
                            : e.title!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
          );
        }
        return _hint(
          theme,
          'Nada urgente por ahora. Captura una idea y yo me encargo del resto.',
        );
      },
    );
  }

  Widget _hint(ThemeData theme, String text) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      );
}
