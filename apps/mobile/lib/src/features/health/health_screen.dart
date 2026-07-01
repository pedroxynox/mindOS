import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'health_providers.dart';

/// F0 screen: proves the end-to-end connection mobile -> API.
/// Shows the API health status, or an error if it is unreachable.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(apiHealthProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('mindOS')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: health.when(
            loading: () => const CircularProgressIndicator(),
            error: (error, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'No se pudo contactar la API',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(apiHealthProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
            data: (status) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text('mindOS está vivo', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Servicio: ${status.service}'),
                Text('Estado: ${status.status}'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
