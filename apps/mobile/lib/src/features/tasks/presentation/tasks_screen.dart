import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/task_model.dart';
import '../tasks_providers.dart';

/// The Tareas tab: tasks ordered by priority, with quick complete, priority
/// editing and manual creation. Combines AI-extracted tasks and manual ones.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  Color _priorityColor(TaskPriority p) => switch (p) {
        TaskPriority.high => const Color(0xFFC62828),
        TaskPriority.medium => const Color(0xFFEF6C00),
        TaskPriority.low => const Color(0xFF2E7D32),
      };

  Future<void> _mutate(WidgetRef ref, Future<void> Function() action) async {
    await action();
    ref.invalidate(tasksListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tasksListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tareas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAdd(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva tarea'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(tasksListProvider);
          await ref.read(tasksListProvider.future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: const [
            Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('No se pudieron cargar las tareas.')),
            ),
          ]),
          data: (tasks) {
            if (tasks.isEmpty) return _empty(context);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) => _TaskTile(
                task: tasks[i],
                priorityColor: _priorityColor(tasks[i].priority),
                onToggle: (v) => _mutate(
                  ref,
                  () => ref
                      .read(tasksApiProvider)
                      .update(tasks[i].id, done: v ?? false),
                ),
                onPriority: () => _pickPriority(context, ref, tasks[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Icon(Icons.check_circle_outline,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          const Text('No tienes tareas', textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            'Aparecerán aquí cuando mindOS las detecte en tus capturas, o crea una con "Nueva tarea".',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _pickPriority(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    final choice = await showModalBottomSheet<TaskPriority>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Prioridad')),
            for (final p in TaskPriority.values)
              ListTile(
                title: Text(p.label),
                trailing: task.priority == p ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (choice != null && choice != task.priority) {
      await _mutate(
        ref,
        () => ref.read(tasksApiProvider).update(task.id, priority: choice),
      );
    }
  }

  Future<void> _showAdd(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    var priority = TaskPriority.medium;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Nueva tarea'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '¿Qué necesitas hacer?',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Prioridad:'),
                  const SizedBox(width: 12),
                  DropdownButton<TaskPriority>(
                    value: priority,
                    items: [
                      for (final p in TaskPriority.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: (v) =>
                        setState(() => priority = v ?? TaskPriority.medium),
                  ),
                ],
              ),
            ],
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
      ),
    );
    final title = controller.text.trim();
    if (created == true && title.isNotEmpty) {
      await _mutate(
        ref,
        () => ref.read(tasksApiProvider).create(title, priority: priority),
      );
    }
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.priorityColor,
    required this.onToggle,
    required this.onPriority,
  });

  final Task task;
  final Color priorityColor;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onPriority;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Checkbox(value: task.done, onChanged: onToggle),
        title: Text(
          (task.title ?? '').trim().isEmpty ? '(sin título)' : task.title!.trim(),
          style: TextStyle(
            decoration: task.done ? TextDecoration.lineThrough : null,
            color: task.done ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: task.dueAt != null
            ? Text('Para ${_formatDate(task.dueAt!)}')
            : (task.area != null ? Text(task.area!) : null),
        trailing: ActionChip(
          label: Text(task.priority.label),
          labelStyle: TextStyle(color: priorityColor, fontSize: 12),
          side: BorderSide(color: priorityColor.withValues(alpha: 0.4)),
          backgroundColor: priorityColor.withValues(alpha: 0.08),
          onPressed: onPriority,
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} $hh:$mm';
  }
}
