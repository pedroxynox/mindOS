import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/growth_models.dart';
import '../growth_providers.dart';

/// The Crecimiento tab: goals (with progress), habits (streaks) and quick
/// reflections — the personal-development side of mindOS.
class GrowthScreen extends StatelessWidget {
  const GrowthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Crecimiento'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Metas'),
              Tab(text: 'Hábitos'),
              Tab(text: 'Reflexión'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_GoalsView(), _HabitsView(), _ReflectionView()],
        ),
      ),
    );
  }
}

// --- Goals -------------------------------------------------------------------

class _GoalsView extends ConsumerWidget {
  const _GoalsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goalsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-goal',
        onPressed: () => _addGoal(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva meta'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('No se pudieron cargar.')),
        data: (goals) {
          if (goals.isEmpty) {
            return const _Empty(
              icon: Icons.flag_outlined,
              text: 'Define tu primera meta y sigue tu progreso.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: goals.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _GoalCard(
              goal: goals[i],
              onChange: (p) async {
                await ref.read(growthApiProvider).updateGoalProgress(goals[i].id, p);
                ref.invalidate(goalsProvider);
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _addGoal(BuildContext context, WidgetRef ref) async {
    final title = await _promptText(context, 'Nueva meta', '¿Qué quieres lograr?');
    if (title != null && title.isNotEmpty) {
      await ref.read(growthApiProvider).createGoal(title);
      ref.invalidate(goalsProvider);
    }
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onChange});
  final Goal goal;
  final Future<void> Function(int progress) onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (goal.title ?? '').trim().isEmpty
                        ? '(sin título)'
                        : goal.title!.trim(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Text('${goal.progress}%',
                    style: TextStyle(color: theme.colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (goal.progress / 100).clamp(0, 1),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: goal.progress <= 0
                      ? null
                      : () => onChange((goal.progress - 10).clamp(0, 100)),
                  child: const Text('-10%'),
                ),
                TextButton(
                  onPressed: goal.progress >= 100
                      ? null
                      : () => onChange((goal.progress + 10).clamp(0, 100)),
                  child: const Text('+10%'),
                ),
                if (goal.progress < 100)
                  FilledButton.tonal(
                    onPressed: () => onChange(100),
                    child: const Text('Lograda'),
                  )
                else
                  const Chip(label: Text('¡Lograda! 🎉')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- Habits ------------------------------------------------------------------

class _HabitsView extends ConsumerWidget {
  const _HabitsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(habitsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-habit',
        onPressed: () => _addHabit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo hábito'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('No se pudieron cargar.')),
        data: (habits) {
          if (habits.isEmpty) {
            return const _Empty(
              icon: Icons.repeat,
              text: 'Crea un hábito y construye tu racha día a día.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: habits.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) => _HabitTile(
              habit: habits[i],
              onCheck: () async {
                await ref.read(growthApiProvider).checkHabit(habits[i].id);
                ref.invalidate(habitsProvider);
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _addHabit(BuildContext context, WidgetRef ref) async {
    final title =
        await _promptText(context, 'Nuevo hábito', 'p. ej. Meditar 10 min');
    if (title != null && title.isNotEmpty) {
      await ref.read(growthApiProvider).createHabit(title);
      ref.invalidate(habitsProvider);
    }
  }
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({required this.habit, required this.onCheck});
  final Habit habit;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        title: Text(
          (habit.title ?? '').trim().isEmpty ? '(sin título)' : habit.title!.trim(),
        ),
        subtitle: Text(habit.streak > 0
            ? '🔥 Racha de ${habit.streak} ${habit.streak == 1 ? "día" : "días"}'
            : 'Sin racha todavía'),
        trailing: IconButton(
          iconSize: 32,
          tooltip: habit.doneToday ? 'Hecho hoy' : 'Marcar hoy',
          icon: Icon(
            habit.doneToday
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: habit.doneToday
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          onPressed: onCheck,
        ),
      ),
    );
  }
}

// --- Reflections -------------------------------------------------------------

class _ReflectionView extends ConsumerStatefulWidget {
  const _ReflectionView();

  @override
  ConsumerState<_ReflectionView> createState() => _ReflectionViewState();
}

class _ReflectionViewState extends ConsumerState<_ReflectionView> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(growthApiProvider).createReflection(text);
      _controller.clear();
      ref.invalidate(reflectionsProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(reflectionsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: '¿Cómo te sientes hoy? ¿Qué aprendiste?',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar reflexión'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) =>
                const Center(child: Text('No se pudieron cargar.')),
            data: (items) {
              if (items.isEmpty) {
                return const _Empty(
                  icon: Icons.self_improvement,
                  text: 'Tus reflexiones aparecerán aquí.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.notes),
                    title: Text((items[i].body ?? '').trim()),
                    subtitle: Text(_formatDate(items[i].createdAt)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

// --- Shared ------------------------------------------------------------------

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }
}

/// Simple single-field prompt dialog. Returns the trimmed text or null.
Future<String?> _promptText(
  BuildContext context,
  String title,
  String hint,
) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Crear'),
        ),
      ],
    ),
  );
  return ok == true ? controller.text.trim() : null;
}
