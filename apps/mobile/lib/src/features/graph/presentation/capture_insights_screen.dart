import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/graph_models.dart';
import '../graph_providers.dart';
import 'node_type_style.dart';

/// Shows what the brain understood from a single capture: the extracted
/// entities grouped by type and the connections between them. While the
/// pipeline is still working, it shows a "thinking" state and polls until the
/// capture is processed.
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
        const SizedBox(height: 12),
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

class _TypeSection extends StatelessWidget {
  const _TypeSection({required this.type, required this.nodes});
  final String type;
  final List<GraphNode> nodes;

  @override
  Widget build(BuildContext context) {
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
                  Chip(
                    avatar: Icon(style.icon, size: 16, color: style.color),
                    label: Text((n.title ?? '').trim().isEmpty
                        ? '(sin título)'
                        : n.title!.trim()),
                    backgroundColor: style.color.withValues(alpha: 0.10),
                    side: BorderSide(color: style.color.withValues(alpha: 0.30)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.edge, required this.titleById});
  final GraphEdge edge;
  final Map<String, String> titleById;

  @override
  Widget build(BuildContext context) {
    final source = titleById[edge.source] ?? '—';
    final target = titleById[edge.target] ?? '—';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.link),
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
