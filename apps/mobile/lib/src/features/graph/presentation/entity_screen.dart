import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/format.dart';
import '../../shared/mindos_api.dart';
import '../data/graph_models.dart';
import '../graph_providers.dart';
import 'graph_corrections.dart';
import 'node_type_style.dart';

/// The card of one entity (`/node/:id`): a person, project, topic... with
/// every capture where it appears, the tasks linked to it and what it shows
/// up with. The user can rename it everywhere or forget it (FR-2.4).
class EntityScreen extends ConsumerWidget {
  const EntityScreen({super.key, required this.nodeId});

  final String nodeId;

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    EntityDetail detail,
  ) async {
    final title = await showRenameDialog(
      context,
      initial: detail.node.title ?? '',
      title: 'Renombrar',
      helper: detail.node.mentions > 1
          ? 'Cambia en las ${detail.node.mentions} menciones.'
          : null,
    );
    if (title == null || !context.mounted) return;
    await runCorrection(
      context,
      ref,
      () => ref
          .read(graphApiClientProvider)
          .renameNode(nodeId, title, wholeEntity: true),
      done: 'Renombrado.',
    );
  }

  Future<void> _forget(
    BuildContext context,
    WidgetRef ref,
    EntityDetail detail,
  ) async {
    final mentions = detail.node.mentions;
    final ok = await confirmForget(
      context,
      title: '¿Olvidar «${detail.node.label}»?',
      message: mentions > 1
          ? 'Lo quito de tus $mentions capturas y de sus conexiones. '
              'Tus capturas no se borran.'
          : 'Lo quito de tu captura y de sus conexiones. '
              'Tu captura no se borra.',
      action: 'Olvidar',
    );
    if (!ok || !context.mounted) return;
    final done = await runCorrection(
      context,
      ref,
      () => ref
          .read(graphApiClientProvider)
          .removeNode(nodeId, wholeEntity: true),
      done: 'Olvidado.',
    );
    if (done && context.mounted) {
      context.canPop() ? context.pop() : context.go('/');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entityProvider(nodeId));
    final detail = async.valueOrNull;
    final style = NodeTypeStyle.of(detail?.node.type ?? '');

    return Scaffold(
      appBar: AppBar(
        title: Text(detail == null ? 'Ficha' : style.singular),
        actions: [
          if (detail != null) ...[
            IconButton(
              tooltip: 'Renombrar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(context, ref, detail),
            ),
            IconButton(
              tooltip: 'Olvidar',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _forget(context, ref, detail),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(entityProvider(nodeId));
          try {
            await ref.read(entityProvider(nodeId).future);
          } catch (_) {}
        },
        child: async.when(
          loading: () => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(48),
                child: Text(
                  e is ApiException && e.statusCode == 404
                      ? 'Esto ya no existe.'
                      : 'No se pudo cargar. Desliza hacia abajo para reintentar.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          data: (d) => _EntityBody(detail: d),
        ),
      ),
    );
  }
}

class _EntityBody extends StatelessWidget {
  const _EntityBody({required this.detail});
  final EntityDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = detail.node;
    final style = NodeTypeStyle.of(node.type);
    final muted = theme.colorScheme.onSurfaceVariant;

    final seen = node.mentions > 1
        ? 'Lo mencionaste ${node.mentions} veces · desde ${formatShortDate(detail.firstSeenAt)}'
        : 'Lo mencionaste una vez · ${formatShortDate(detail.firstSeenAt)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: style.color.withValues(alpha: 0.15),
              child: Icon(style.icon, color: style.color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.label,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail.userEdited ? '$seen · corregido por ti' : seen,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (detail.tasks.isNotEmpty) ...[
          const _SectionTitle('Tareas'),
          for (final t in detail.tasks)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: Icon(
                  t.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: t.done ? const Color(0xFF2E7D32) : muted,
                ),
                title: Text(
                  (t.title ?? '').trim().isEmpty ? '(sin título)' : t.title!,
                  style: t.done
                      ? TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: muted,
                        )
                      : null,
                ),
                subtitle: t.dueAt == null ? null : Text(formatDayTime(t.dueAt!)),
                onTap: () => context.push('/tasks'),
              ),
            ),
        ],
        if (detail.related.isNotEmpty) ...[
          const _SectionTitle('Aparece con'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in detail.related)
                ActionChip(
                  avatar: Icon(
                    NodeTypeStyle.of(r.type).icon,
                    size: 16,
                    color: NodeTypeStyle.of(r.type).color,
                  ),
                  label: Text(
                    r.mentions > 1 ? '${r.label} · ${r.mentions}' : r.label,
                  ),
                  onPressed: () => context.push('/node/${r.id}'),
                ),
            ],
          ),
        ],
        const _SectionTitle('Dónde lo mencionaste'),
        if (detail.captures.isEmpty)
          Text(
            'No encuentro la captura de origen.',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        for (final c in detail.captures)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: Icon(
                c.isVoice ? Icons.mic_none : Icons.notes,
                color: muted,
              ),
              title: Text(
                c.snippet.isEmpty
                    ? (c.isVoice ? 'Nota de voz' : '(sin contenido)')
                    : c.snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(formatDayTime(c.createdAt)),
              onTap: () => context.push('/capture/${c.id}/insights'),
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
