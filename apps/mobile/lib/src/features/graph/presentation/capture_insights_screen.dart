import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../feedback/feedback_api.dart';
import '../../feedback/feedback_thumbs.dart';
import '../data/graph_models.dart';
import '../graph_providers.dart';
import 'graph_corrections.dart';
import 'node_type_style.dart';

/// Shows what the brain understood from a single capture: the extracted
/// entities grouped by type and the connections between them. While the
/// pipeline is still working, it shows a "thinking" state and polls until the
/// capture is processed.
///
/// The user can rate it (👍/👎) and fix it (FR-2.4): tap an item to open its
/// card, correct its name or remove it; confirm or reject each connection.
class CaptureInsightsScreen extends ConsumerStatefulWidget {
  const CaptureInsightsScreen({super.key, required this.captureId});

  final String captureId;

  @override
  ConsumerState<CaptureInsightsScreen> createState() =>
      _CaptureInsightsScreenState();
}

class _CaptureInsightsScreenState
    extends ConsumerState<CaptureInsightsScreen> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _schedulePollIfPending(CaptureEntities? entities) {
    final pending = entities?.isPending ?? true;
    if (pending && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) {
        ref.invalidate(captureEntitiesProvider(widget.captureId));
      });
    } else if (!pending) {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(captureEntitiesProvider(widget.captureId));
    _schedulePollIfPending(async.valueOrNull);

    return Scaffold(
      appBar: AppBar(title: const Text('Lo que entendí')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(captureEntitiesProvider(widget.captureId));
          await ref.read(captureEntitiesProvider(widget.captureId).future);
        },
        child: async.when(
          loading: () => const _CenteredList(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, __) => const _CenteredList(
            child: _Message(
              icon: Icons.cloud_off,
              title: 'No se pudo cargar',
              subtitle: 'Desliza hacia abajo para reintentar.',
            ),
          ),
          data: (entities) => _InsightsBody(entities: entities),
        ),
      ),
    );
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({required this.entities});
  final CaptureEntities entities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    if (entities.isPending) {
      return const _CenteredList(
        child: _Message(
          icon: Icons.psychology_alt,
          title: 'El cerebro está pensando...',
          subtitle:
              'Estoy entendiendo tu captura. Esto toma unos segundos; se actualiza solo.',
          showSpinner: true,
        ),
      );
    }

    if (entities.isFailed) {
      return const _CenteredList(
        child: _Message(
          icon: Icons.error_outline,
          title: 'No pude procesar esta captura',
          subtitle: 'Puedes intentar crear la captura de nuevo.',
        ),
      );
    }

    if (entities.nodes.isEmpty) {
      return const _CenteredList(
        child: _Message(
          icon: Icons.info_outline,
          title: 'Sin elementos destacados',
          subtitle:
              'Esta captura se guardó, pero no encontré tareas, personas ni proyectos que resaltar.',
        ),
      );
    }

    // Group nodes by type for a tidy, sectioned view.
    final byType = <String, List<GraphNode>>{};
    for (final n in entities.nodes) {
      byType.putIfAbsent(n.type, () => []).add(n);
    }
    final titleById = {
      for (final n in entities.nodes) n.id: (n.title ?? '').trim(),
    };
    // Show types in a stable, useful order.
    const order = ['task', 'person', 'project', 'event', 'topic', 'decision', 'note'];
    final types = byType.keys.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a), ib = order.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Esto entendí de tu captura',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Toca un elemento para corregirlo o quitarlo.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FeedbackThumbs(
            target: FeedbackTarget.capture(entities.captureId),
            prompt: '¿Lo entendí bien?',
            thanks: 'Gracias. Si algo falló, corrígelo abajo.',
          ),
        ),
        const SizedBox(height: 4),
        for (final type in types) ...[
          _TypeSection(type: type, nodes: byType[type]!),
          const SizedBox(height: 8),
        ],
        if (entities.edges.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Conexiones', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final e in entities.edges)
            _ConnectionTile(edge: e, titleById: titleById),
        ],
      ],
    );
  }
}

class _TypeSection extends ConsumerWidget {
  const _TypeSection({required this.type, required this.nodes});
  final String type;
  final List<GraphNode> nodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = NodeTypeStyle.of(type);
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(style.icon, color: style.color, size: 20),
                const SizedBox(width: 8),
                Text(
                  nodes.length == 1 ? style.singular : style.plural,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in nodes)
                  ActionChip(
                    tooltip: 'Ver o corregir',
                    avatar: Icon(style.icon, size: 16, color: style.color),
                    label: Text(n.label),
                    backgroundColor: style.color.withValues(alpha: 0.10),
                    side: BorderSide(color: style.color.withValues(alpha: 0.30)),
                    onPressed: () => _openNodeActions(context, ref, n),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _NodeAction { open, rename, remove }

/// The card of one extracted item: open its entity, fix its name (this capture
/// only) or remove it ("no era eso").
Future<void> _openNodeActions(
  BuildContext context,
  WidgetRef ref,
  GraphNode node,
) async {
  final style = NodeTypeStyle.of(node.type);
  final theme = Theme.of(context);
  final action = await showModalBottomSheet<_NodeAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(style.icon, color: style.color),
            title: Text(node.label, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(style.singular),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Ver ficha'),
            subtitle: const Text('Todo lo que sé sobre esto'),
            onTap: () => Navigator.of(ctx).pop(_NodeAction.open),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Corregir nombre'),
            onTap: () => Navigator.of(ctx).pop(_NodeAction.rename),
          ),
          ListTile(
            leading: Icon(Icons.remove_circle_outline,
                color: theme.colorScheme.error),
            title: Text('Quitar',
                style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text('No era eso: dejaré de usarlo'),
            onTap: () => Navigator.of(ctx).pop(_NodeAction.remove),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  final client = ref.read(graphApiClientProvider);
  switch (action) {
    case _NodeAction.open:
      context.push('/node/${node.id}');
    case _NodeAction.rename:
      final title = await showRenameDialog(
        context,
        initial: node.title ?? '',
        helper: 'Solo cambia en esta captura. Si ya existe con ese nombre, '
            'se unen.',
      );
      if (title == null || !context.mounted) return;
      await runCorrection(
        context,
        ref,
        () => client.renameNode(node.id, title),
        done: 'Corregido.',
      );
    case _NodeAction.remove:
      final ok = await confirmForget(
        context,
        title: '¿Quitar «${node.label}»?',
        message: 'Lo quito de esta captura y de sus conexiones. '
            'Tu captura no se borra.',
      );
      if (!ok || !context.mounted) return;
      await runCorrection(
        context,
        ref,
        () => client.removeNode(node.id),
        done: 'Quitado.',
      );
  }
}

class _ConnectionTile extends ConsumerWidget {
  const _ConnectionTile({required this.edge, required this.titleById});
  final GraphEdge edge;
  final Map<String, String> titleById;

  Future<void> _review(BuildContext context, WidgetRef ref, bool ok) {
    return runCorrection(
      context,
      ref,
      () => ref
          .read(graphApiClientProvider)
          .reviewEdge(edge.id!, confirmed: ok),
      done: ok ? 'Conexión confirmada.' : 'Conexión quitada.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final source = titleById[edge.source] ?? '—';
    final target = titleById[edge.target] ?? '—';
    Widget? trailing;
    if (edge.userConfirmed) {
      trailing = Tooltip(
        message: 'Confirmada por ti',
        child: Icon(Icons.verified, color: theme.colorScheme.primary),
      );
    } else if (edge.id != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Es correcto',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.check),
            onPressed: () => _review(context, ref, true),
          ),
          IconButton(
            tooltip: 'No es correcto',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: () => _review(context, ref, false),
          ),
        ],
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.link),
        trailing: trailing,
        title: Text.rich(
          TextSpan(children: [
            TextSpan(
              text: source.isEmpty ? '—' : source,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: '  ${NodeTypeStyle.edgeLabel(edge.type)}  '),
            TextSpan(
              text: target.isEmpty ? '—' : target,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.showSpinner = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
      child: Column(
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (showSpinner) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

/// Wraps content in a scrollable so RefreshIndicator works even when short.
class _CenteredList extends StatelessWidget {
  const _CenteredList({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [child],
    );
  }
}
