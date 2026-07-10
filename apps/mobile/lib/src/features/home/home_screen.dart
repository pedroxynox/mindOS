import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../finance/finance_providers.dart';
import '../growth/data/growth_models.dart';
import '../growth/growth_providers.dart';
import '../tasks/data/task_model.dart';
import '../tasks/tasks_providers.dart';
import '../../theme.dart';
import '../../widgets/cosmic_background.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/mini_charts.dart';
import 'focus_score.dart';

/// "Hoy" — the dashboard. Contextual greeting, a focus card (score + the three
/// priorities that matter), a quick summary grid (finance, habits, projects,
/// reminders) and mindOS's top recommendation.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(tokenStoreProvider).displayName;
    final tasks = ref.watch(tasksListProvider).valueOrNull ?? const <Task>[];
    final pending = tasks.where((t) => !t.done).toList();
    final reminders = _dueTomorrow(tasks);

    return Scaffold(
      extendBody: true,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/capture'),
        elevation: 0,
        child: const Icon(Icons.add, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: const _HomeBottomBar(),
      body: CosmicBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(tasksListProvider);
              ref.invalidate(financeSummaryProvider);
              ref.invalidate(habitsProvider);
              ref.invalidate(goalsProvider);
              try {
                await ref.read(tasksListProvider.future);
              } catch (_) {}
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _Header(onAvatar: () => _logout(context, ref)),
                const SizedBox(height: 18),
                Text(
                  name != null ? 'Buenos días, $name' : _greeting(),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
                ),
                const SizedBox(height: 6),
                Text(
                  'Así va todo para hoy. Tienes ${pending.length} '
                  '${pending.length == 1 ? "prioridad" : "prioridades"} y '
                  '$reminders ${reminders == 1 ? "recordatorio" : "recordatorios"} importantes.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 20),
                const FadeInUp(child: _FocusCard()),
                const SizedBox(height: 26),
                Text('Resumen rápido',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                const FadeInUp(delay: Duration(milliseconds: 80), child: _SummaryGrid()),
                const SizedBox(height: 18),
                const FadeInUp(
                    delay: Duration(milliseconds: 160), child: _RecommendationCard()),
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

  static int _dueTomorrow(List<Task> tasks) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    return tasks.where((t) {
      if (t.done || t.dueAt == null) return false;
      final d = t.dueAt!.toLocal();
      return d.year == tomorrow.year &&
          d.month == tomorrow.month &&
          d.day == tomorrow.day;
    }).length;
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
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
    if (ok ?? false) await ref.read(authControllerProvider.notifier).logout();
  }
}

/// The floating bottom bar from the design: chat (Conversar) on the left, the
/// universal Capturar action as the raised centre button, search (Memoria) on
/// the right. Blends into the cosmic background.
class _HomeBottomBar extends StatelessWidget {
  const _HomeBottomBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BottomAppBar(
      color: Colors.transparent,
      elevation: 0,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Conversar',
            iconSize: 26,
            icon: Icon(Icons.chat_bubble_outline,
                color: theme.colorScheme.onSurfaceVariant),
            onPressed: () => context.push('/ask'),
          ),
          const SizedBox(width: 48),
          IconButton(
            tooltip: 'Memoria',
            iconSize: 26,
            icon: Icon(Icons.search,
                color: theme.colorScheme.onSurfaceVariant),
            onPressed: () => context.push('/memory'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onAvatar});
  final VoidCallback onAvatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: 'mind',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            TextSpan(
              text: 'OS',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ]),
        ),
        GestureDetector(
          onTap: onAvatar,
          child: CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.25),
            child: Icon(Icons.person, color: theme.colorScheme.primary),
          ),
        ),
      ],
    );
  }
}

// --- Focus card --------------------------------------------------------------

class _FocusCard extends ConsumerWidget {
  const _FocusCard();

  static const _dotColors = [
    Color(0xFF8B7BFF),
    Color(0xFF5AA9FF),
    Color(0xFF57D9A3),
    Color(0xFFF7C948),
    Color(0xFFFF6B6B),
  ];

  Color _areaColor(String? s) {
    if (s == null || s.isEmpty) return _dotColors[0];
    return _dotColors[s.hashCode.abs() % _dotColors.length];
  }

  String _timeOf(Task t) {
    if (t.dueAt == null) return '';
    final l = t.dueAt!.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksListProvider).valueOrNull ?? const <Task>[];
    final pending = tasks.where((t) => !t.done).take(3).toList();
    final score = computeFocusScore(tasks);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B2E86), Color(0xFF241C57), Color(0xFF1A1636)],
        ),
        border: Border.all(color: AppTheme.violet.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.violetDeep.withValues(alpha: 0.35),
            blurRadius: 30,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bolt, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Tu enfoque de hoy',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              Column(
                children: [
                  RingProgress(
                    value: score / 100,
                    size: 46,
                    stroke: 4,
                    color: AppTheme.electric,
                    trackColor: Colors.white.withValues(alpha: 0.15),
                    child: Text('$score',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                  ),
                  const SizedBox(height: 4),
                  Text('Puntuación de enfoque',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 9)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Sin prioridades pendientes. Disfruta el día.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
            )
          else
            for (var i = 0; i < pending.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == pending.length - 1 ? 0 : 14),
                child: _PriorityRow(
                  index: i + 1,
                  task: pending[i],
                  dotColor: _areaColor(pending[i].area),
                  time: _timeOf(pending[i]),
                  onTap: () => context.push('/tasks'),
                ),
              ),
        ],
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    required this.index,
    required this.task,
    required this.dotColor,
    required this.time,
    required this.onTap,
  });

  final int index;
  final Task task;
  final Color dotColor;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text('$index',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (task.title ?? '').trim().isEmpty
                      ? '(sin título)'
                      : task.title!.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(width: 7, height: 7,
                        decoration: BoxDecoration(
                            color: dotColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(
                      task.area ?? 'General',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(time,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
        ],
      ),
    );
  }
}

// --- Summary grid ------------------------------------------------------------

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(
          height: 150,
          child: Row(children: [
            Expanded(child: _FinanceCard()),
            SizedBox(width: 14),
            Expanded(child: _HabitCard()),
          ]),
        ),
        SizedBox(height: 14),
        SizedBox(
          height: 150,
          child: Row(children: [
            Expanded(child: _ProjectCard()),
            SizedBox(width: 14),
            Expanded(child: _ReminderCard()),
          ]),
        ),
      ],
    );
  }
}

class _DashCard extends StatelessWidget {
  const _DashCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

class _FinanceCard extends ConsumerWidget {
  const _FinanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(financeSummaryProvider);
    return _DashCard(
      onTap: () => _addExpense(context, ref),
      child: async.when(
        loading: () => const _CardLabel('Finanzas'),
        error: (_, __) => const _CardLabel('Finanzas'),
        data: (s) {
          if (s.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardLabel('Finanzas'),
                const Spacer(),
                Text('Añade tu primer gasto',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('Toca para registrar',
                      style: TextStyle(
                          color: theme.colorScheme.primary, fontSize: 12)),
                ]),
              ],
            );
          }
          final up = (s.changePct ?? 0) > 0;
          final changeColor = up
              ? const Color(0xFFFF6B6B)
              : const Color(0xFF57D9A3);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardLabel('Finanzas'),
              const SizedBox(height: 2),
              Text('Gasto semanal',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text('\$${s.weekTotal.toStringAsFixed(s.weekTotal % 1 == 0 ? 0 : 1)}',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (s.changePct != null)
                Text('${up ? "+" : ""}${s.changePct}% vs semana pasada',
                    style: TextStyle(color: changeColor, fontSize: 11)),
              const Spacer(),
              Sparkline(values: s.daily, color: theme.colorScheme.primary, height: 30),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addExpense(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final catController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar gasto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  prefixText: '\$ ', hintText: 'Monto'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: catController,
              decoration:
                  const InputDecoration(hintText: 'Categoría (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    final amount = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    if (ok == true && amount != null && amount > 0) {
      await ref.read(financeApiProvider).addExpense(
            amount,
            category: catController.text.trim(),
          );
      ref.invalidate(financeSummaryProvider);
    }
  }
}

class _HabitCard extends ConsumerWidget {
  const _HabitCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(habitsProvider);
    return _DashCard(
      onTap: () => context.push('/growth'),
      child: async.when(
        loading: () => const _CardLabel('Hábitos'),
        error: (_, __) => const _CardLabel('Hábitos'),
        data: (habits) {
          if (habits.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardLabel('Hábitos'),
                const Spacer(),
                Text('Crea tu primer hábito',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            );
          }
          final h = habits.first;
          const target = 7;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardLabel('Hábitos'),
              const SizedBox(height: 2),
              Text(
                (h.title ?? 'Hábito').trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${h.streak} ${h.streak == 1 ? "día" : "días"}',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(h.streak > 0 ? '¡Vas por buen camino!' : 'Empieza hoy',
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11)),
                    ],
                  ),
                  RingProgress(
                    value: (h.streak.clamp(0, target)) / target,
                    size: 40,
                    stroke: 4,
                    color: const Color(0xFF57D9A3),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectCard extends ConsumerWidget {
  const _ProjectCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(goalsProvider);
    return _DashCard(
      onTap: () => context.push('/growth'),
      child: async.when(
        loading: () => const _CardLabel('Proyectos'),
        error: (_, __) => const _CardLabel('Proyectos'),
        data: (goals) {
          if (goals.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardLabel('Proyectos'),
                const Spacer(),
                Text('Crea una meta',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            );
          }
          final Goal g = goals.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardLabel('Proyectos'),
              const SizedBox(height: 2),
              Text(
                (g.title ?? 'Meta').trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text('${g.progress}%',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text('Avance total',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (g.progress / 100).clamp(0, 1),
                  minHeight: 6,
                  backgroundColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReminderCard extends ConsumerWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksListProvider).valueOrNull ?? const <Task>[];
    final count = HomeScreen._dueTomorrow(tasks);
    return _DashCard(
      onTap: () => context.push('/tasks'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Recordatorios'),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              count > 0
                  ? 'Tienes $count ${count == 1 ? "pendiente" : "pendientes"} para mañana'
                  : 'Sin recordatorios para mañana',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.3),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.notifications_none,
                  color: theme.colorScheme.primary, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700));
  }
}

// --- Recommendation ----------------------------------------------------------

class _RecommendationCard extends ConsumerWidget {
  const _RecommendationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksListProvider).valueOrNull ?? const <Task>[];
    final top = tasks.where((t) => !t.done).isNotEmpty
        ? tasks.firstWhere((t) => !t.done)
        : null;
    final body = top != null
        ? 'La mejor acción hoy es ${(top.title ?? '').trim().toLowerCase()}. Enfócate en eso primero.'
        : 'Captura una idea o crea una tarea y te diré por dónde empezar.';

    return _DashCard(
      onTap: () => context.push('/tasks'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [
                AppTheme.violetDeep.withValues(alpha: 0.5),
                AppTheme.violet.withValues(alpha: 0.25),
              ]),
              boxShadow: [
                BoxShadow(
                    color: AppTheme.violet.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: -4),
              ],
            ),
            child: Icon(Icons.psychology_alt,
                color: theme.colorScheme.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Recomendación de '),
                  TextSpan(
                      text: 'mindOS',
                      style: TextStyle(color: theme.colorScheme.primary)),
                ]),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant, height: 1.35)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
