import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/format.dart';
import '../graph_providers.dart';
import 'node_type_style.dart';

/// Lists all derived nodes of one type (e.g. all people, all topics), page by
/// page with "Cargar más". Reached from the Memoria count chips. People,
/// projects... come grouped by name ("3 menciones"); tapping one opens its
/// card (`/node/:id`).
class NodesListScreen extends ConsumerWidget {
  const NodesListScreen({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = NodeTypeStyle.of(type);
    final state = ref.watch(nodesListProvider(type));
    final controller = ref.read(nodesListProvider(type).notifier);

    Widget body;
    if (state.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.items.isEmpty) {
      body = ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              children: [
                Icon(style.icon, size: 48, color: style.color),
                const SizedBox(height: 12),
                Text(
                  state.errorMessage ??
                      'Aún no hay ${style.plural.toLowerCase()}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      final showMore = state.hasMore || state.isLoadingMore;
      body = ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: state.items.length + (showMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          if (i == state.items.length) {
            return Center(
              child: state.isLoadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    )
                  : TextButton.icon(
                      onPressed: controller.loadMore,
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Cargar más'),
                    ),
            );
          }
          final n = state.items[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: style.color.withValues(alpha: 0.15),
                child: Icon(style.icon, color: style.color, size: 20),
              ),
              title: Text(n.label),
              subtitle: n.mentions > 1
                  ? Text(plural(n.mentions, 'mención', 'menciones'))
                  : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/node/${n.id}'),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(style.plural)),
      body: RefreshIndicator(onRefresh: controller.refresh, child: body),
    );
  }
}
