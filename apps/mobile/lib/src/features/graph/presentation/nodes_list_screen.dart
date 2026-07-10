import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../graph_providers.dart';
import 'node_type_style.dart';

/// Lists all derived nodes of one type (e.g. all tasks, all people). Reached by
/// tapping a summary chip on the home screen.
class NodesListScreen extends ConsumerWidget {
  const NodesListScreen({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = NodeTypeStyle.of(type);
    final async = ref.watch(nodesByTypeProvider(type));

    return Scaffold(
      appBar: AppBar(title: Text(style.plural)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(nodesByTypeProvider(type));
          await ref.read(nodesByTypeProvider(type).future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: Text('No se pudo cargar. Desliza para reintentar.')),
              ),
            ],
          ),
          data: (nodes) {
            if (nodes.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      children: [
                        Icon(style.icon, size: 48, color: style.color),
                        const SizedBox(height: 12),
                        Text('Aún no hay ${style.plural.toLowerCase()}',
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: nodes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final n = nodes[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: style.color.withValues(alpha: 0.15),
                      child: Icon(style.icon, color: style.color, size: 20),
                    ),
                    title: Text(
                      (n.title ?? '').trim().isEmpty
                          ? '(sin título)'
                          : n.title!.trim(),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
