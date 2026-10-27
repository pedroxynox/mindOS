import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../graph/graph_providers.dart';
import '../../shared/format.dart';
import '../../shared/mindos_api.dart';
import '../data/task_model.dart';
import '../tasks_providers.dart';

/// Tareas: tasks ordered by priority, with quick complete, an editor (title,
/// priority, due date, delete) and manual creation. Combines AI-extracted tasks
/// and manual ones.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  static Color priorityColor(TaskPriority p) => switch (p) {
        TaskPriority.high => const Color(0xFFFF6B6B),
        TaskPriority.medium => const Color(0xFFF7C948),
        TaskPriority.low => const Color(0xFF57D9A3),
      };

  /// Run a mutation, refresh what depends on tasks, and surface failures.
  static Future<void> mutate(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      ref.invalidate(tasksListProvider);
      ref.invalidate(briefingProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tasksListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tareas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref, null),
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
                onToggle: (v) => mutate(
                  context,
                  ref,
                  () => ref
                      .read(tasksApiProvider)
                      .update(tasks[i].id, done: v ?? false),
                ),
                onTap: () => _showEditor(context, ref, tasks[i]),
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

  /// Create ([task] == null) or edit a task in a bottom sheet.
  Future<void> _showEditor(
    BuildContext context,
    WidgetRef ref,
    Task? task,
  ) async {
    final result = await showModalBottomSheet<_EditorResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TaskEditor(task: task),
    );
    if (result == null || !context.mounted) return;
    final api = ref.read(tasksApiProvider);
    if (result.delete && task != null) {
      await mutate(context, ref, () => api.delete(task.id));
      return;
    }
    if (task == null) {
      await mutate(
        context,
        ref,
        () => api.create(
          result.title,
          priority: result.priority,
          dueAt: result.dueAt,
        ),
      );
    } else {
      await mutate(
        context,
        ref,
        () => api.update(
          task.id,
          title: result.title != (task.title ?? '') ? result.title : null,
          priority: result.priority != task.priority ? result.priority : null,
          dueAt: result.dueAt,
          clearDueAt: result.dueAt == null && task.dueAt != null,
        ),
      );
    }
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onToggle,
    required this.onTap,
  });

  final Task task;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = TasksScreen.priorityColor(task.priority);
    final overdue = !task.done &&
        task.dueAt != null &&
        task.dueAt!.isBefore(DateTime.now());
    final subtitle = <String>[
      if (task.dueAt != null) 'Para ${formatDayTime(task.dueAt!)}',
      if (task.area != null) task.area!,
      if (task.fromAi) 'detectada por mindOS',
    ].join(' · ');

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Checkbox(value: task.done, onChanged: onToggle),
        title: Text(
          (task.title ?? '').trim().isEmpty ? '(sin título)' : task.title!.trim(),
          style: TextStyle(
            decoration: task.done ? TextDecoration.lineThrough : null,
            color: task.done ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(
                subtitle,
                style: TextStyle(
                  color: overdue
                      ? const Color(0xFFFF6B6B)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(task.priority.label,
              style: TextStyle(color: color, fontSize: 12)),
        ),
      ),
    );
  }
}

class _EditorResult {
  const _EditorResult({
    required this.title,
    required this.priority,
    this.dueAt,
    this.delete = false,
  });

  final String title;
  final TaskPriority priority;
  final DateTime? dueAt;
  final bool delete;
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({this.task});
  final Task? task;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.task?.title ?? '');
  late TaskPriority _priority = widget.task?.priority ?? TaskPriority.medium;
  late DateTime? _dueAt = widget.task?.dueAt?.toLocal();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt ?? now.add(const Duration(hours: 1))),
    );
    if (!mounted) return;
    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 9,
        time?.minute ?? 0,
      );
    });
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Escribe qué necesitas hacer');
      return;
    }
    Navigator.pop(
      context,
      _EditorResult(title: title, priority: _priority, dueAt: _dueAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.task != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(editing ? 'Editar tarea' : 'Nueva tarea',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: !editing,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '¿Qué necesitas hacer?',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          Text('Prioridad', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<TaskPriority>(
            segments: [
              for (final p in TaskPriority.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDue,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_dueAt == null
                      ? 'Añadir fecha'
                      : formatDayTime(_dueAt!)),
                ),
              ),
              if (_dueAt != null)
                IconButton(
                  tooltip: 'Quitar fecha',
                  onPressed: () => setState(() => _dueAt = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (editing)
                TextButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    _EditorResult(
                      title: _title.text,
                      priority: _priority,
                      delete: true,
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B6B)),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _submit,
                child: Text(editing ? 'Guardar' : 'Crear'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
