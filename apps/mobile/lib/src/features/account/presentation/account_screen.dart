import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../finance/finance_providers.dart';
import '../../graph/graph_providers.dart';
import '../../growth/growth_providers.dart';
import '../../shared/mindos_api.dart';
import '../account_providers.dart';
import '../locale_defaults.dart';

/// Cuenta: who you are, the currency your money is shown in and the timezone
/// mindOS uses for "today", plus signing out. (Privacy — export / delete /
/// AI consent — lives here too.)
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta')),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ListView(children: [
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('No se pudo cargar tu cuenta.', textAlign: TextAlign.center),
          ),
          _LogoutTile(),
        ]),
        data: (m) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                  child: Icon(Icons.person, color: theme.colorScheme.primary),
                ),
                title: Text(m.email),
                subtitle: const Text('Tu cuenta de mindOS'),
              ),
            ),
            const SizedBox(height: 16),
            Text('Preferencias', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Moneda'),
                    subtitle: Text(
                      '${supportedCurrencies[m.effectiveCurrency] ?? m.effectiveCurrency} (${m.effectiveCurrency})',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickCurrency(context, ref, m.effectiveCurrency),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('Zona horaria'),
                    subtitle: Text(
                        '${m.timezone} · se toma de tu dispositivo para calcular tu "hoy"'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _LogoutTile(),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Elige tu moneda')),
            for (final e in supportedCurrencies.entries)
              ListTile(
                title: Text(e.value),
                subtitle: Text('${e.key} · ${formatMoney(1234.5, e.key)}'),
                trailing: e.key == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    try {
      await ref.read(meApiProvider).update(currency: picked);
      ref.invalidate(meProvider);
      ref.invalidate(financeSummaryProvider);
      ref.invalidate(briefingProvider);
      ref.invalidate(habitsProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _LogoutTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Cerrar sesión'),
        onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cerrar sesión'),
              content: const Text('¿Seguro que quieres cerrar sesión?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Cerrar sesión')),
              ],
            ),
          );
          if (ok ?? false) {
            await ref.read(authControllerProvider.notifier).logout();
          }
        },
      ),
    );
  }
}
