import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/briefing_models.dart';
import '../graph_providers.dart';

/// The hero card at the top of the home screen: mindOS "speaks first" with a
/// time-based greeting, a one-line headline of what matters now, and a glance at
/// upcoming events and pending tasks.
class BriefingCard extends ConsumerWidget {
  const BriefingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(briefingProvider);

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greeting(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            async.when(
              loading: () => _line(
                theme,
                'Preparando tu resumen...',
              ),
              error: (_, __) => _line(
                theme,
                'No pude cargar tu resumen. Desliza para reintentar.',
              ),
              data: (b) => _BriefingBody(briefing: b),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
      );

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }
}

class _BriefingBody extends StatelessWidget {
  const _BriefingBody({required this.briefing});
  final Briefing briefing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onPrimaryContainer;

    if (briefing.isEmpty) {
      return Text(
        'Todo despejado por ahora. Captura algo y empezaré a organizarlo por ti.',
        style: theme.textTheme.bodyMedium?.copyWith(color: onContainer),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _headline(briefing),
          style: theme.textTheme.bodyLarge?.copyWith(color: onContainer),
        ),
        if (briefing.upcomingEvents.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final e in briefing.upcomingEvents.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.event_outlined, size: 18, color: onContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (e.title ?? '').trim().isEmpty
                          ? 'Evento'
                          : e.title!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: onContainer),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(e.occurredAt),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: onContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (briefing.taskTotal > 0) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push('/graph/task'),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                briefing.taskTotal == 1
                    ? 'Ver mi tarea'
                    : 'Ver mis ${briefing.taskTotal} tareas',
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// One-line summary, e.g. "Hoy tienes 3 tareas y 2 eventos próximos."
  static String _headline(Briefing b) {
    final parts = <String>[];
    if (b.taskTotal > 0) {
      parts.add(b.taskTotal == 1 ? '1 tarea' : '${b.taskTotal} tareas');
    }
    final ev = b.upcomingEvents.length;
    if (ev > 0) {
      parts.add(ev == 1 ? '1 evento próximo' : '$ev eventos próximos');
    }
    if (parts.isEmpty) return 'Todo despejado por ahora.';
    if (parts.length == 1) return 'Tienes ${parts[0]}.';
    return 'Tienes ${parts[0]} y ${parts[1]}.';
  }

  /// Lightweight Spanish date label (no external i18n dependency).
  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = day.difference(today).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';
    if (diff == 0) return 'hoy $time';
    if (diff == 1) return 'mañana $time';
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${local.day} ${months[local.month - 1]} $time';
  }
}
