import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../../widgets/presence_orb.dart';
import '../graph/data/briefing_models.dart';
import '../graph/graph_providers.dart';
import '../shared/format.dart';

/// The lines mindOS "says first" on Hoy, composed from the Daily Briefing.
/// Pure (no widgets) so it is unit-testable. The first line is the headline.
List<String> composeBriefingLines(Briefing b, {DateTime? now}) {
  if (b.isEmpty) {
    return const ['Todo despejado. Captura una idea y la organizo por ti.'];
  }
  final lines = <String>[];

  if (b.taskTotal > 0) {
    final details = <String>[];
    if (b.overdueCount > 0) {
      details.add(plural(b.overdueCount, 'vencida', 'vencidas'));
    }
    if (b.dueTodayCount > 0) details.add('${b.dueTodayCount} para hoy');
    final head = 'Tienes ${plural(b.taskTotal, 'pendiente', 'pendientes')}';
    lines.add(details.isEmpty ? '$head.' : '$head (${details.join(', ')}).');
  } else {
    lines.add('No tienes tareas pendientes.');
  }

  if (b.people.isNotEmpty) {
    final p = b.people.first;
    lines.add(p.pendingCount > 1
        ? '${p.name} espera ${p.pendingCount} cosas de ti.'
        : '${p.name} espera algo de ti.');
  }

  if (b.upcomingEvents.isNotEmpty) {
    final e = b.upcomingEvents.first;
    final title = (e.title ?? '').trim().isEmpty ? 'Evento' : e.title!.trim();
    lines.add('Próximo: $title, ${formatDayTime(e.occurredAt, now: now)}.');
  }
  return lines;
}

/// "mindOS te habla primero": the proactive briefing card at the top of Hoy.
class BriefingHero extends ConsumerWidget {
  const BriefingHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(briefingProvider);

    final lines = async.when(
      loading: () => const ['Preparando tu resumen…'],
      error: (_, __) =>
          const ['No pude preparar tu resumen. Desliza hacia abajo para reintentar.'],
      data: composeBriefingLines,
    );
    final isLoading = async.isLoading;

    return Semantics(
      container: true,
      label: 'Resumen de mindOS',
      child: InkWell(
        onTap: () => context.push('/tasks'),
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: AppTheme.glass.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.violet.withValues(alpha: 0.22)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PresenceOrb(
                size: 40,
                state: isLoading ? OrbState.thinking : OrbState.speaking,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Column(
                    key: ValueKey(lines.join('|')),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lines.first,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      for (final line in lines.skip(1)) ...[
                        const SizedBox(height: 4),
                        Text(
                          line,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
