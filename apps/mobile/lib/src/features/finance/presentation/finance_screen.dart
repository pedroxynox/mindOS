import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../widgets/mini_charts.dart';
import '../../account/account_providers.dart';
import '../../account/locale_defaults.dart';
import '../../shared/format.dart';
import '../../shared/mindos_api.dart';
import '../data/finance_models.dart';
import '../expense_categories.dart';
import '../finance_providers.dart';

/// Finanzas (`/finance`, mejoras-v2 §E): the week at a glance, where the money
/// went by category, and every expense — the ones typed here and the ones
/// mindOS found in captures ("gasté 20 en el almuerzo").
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  static void refresh(WidgetRef ref) {
    ref.invalidate(financeSummaryProvider);
    ref.invalidate(expensesProvider);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final currency = ref.read(displayCurrencyProvider);
    final draft = await showModalBottomSheet<_ExpenseDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExpenseEditor(currency: currency),
    );
    if (draft == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(financeApiProvider).addExpense(
            draft.amount,
            category: draft.category,
            note: draft.note,
          );
      messenger.showSnackBar(const SnackBar(content: Text('Gasto guardado.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      refresh(ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(financeSummaryProvider);
    final expenses = ref.watch(expensesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Finanzas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Añadir gasto'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refresh(ref);
          try {
            await ref.read(financeSummaryProvider.future);
          } catch (_) {}
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            summary.when(
              loading: () => const _SummaryCard.loading(),
              error: (_, __) => const _Notice(
                'No se pudo cargar tu resumen. Desliza hacia abajo para reintentar.',
              ),
              data: (s) => _SummaryCard(summary: s),
            ),
            if (summary.valueOrNull?.byCategory.isNotEmpty ?? false) ...[
              const _SectionTitle('En qué se fue esta semana'),
              _CategoryBreakdown(summary: summary.value!),
            ],
            const _SectionTitle('Movimientos'),
            _ExpenseList(state: expenses),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required FinanceSummary this.summary});
  const _SummaryCard.loading() : summary = null;

  final FinanceSummary? summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final s = summary;
    final change = s?.changePct;
    final up = (change ?? 0) > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Últimos 7 días',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                s == null ? '—' : formatMoney(s.weekTotal, s.currency),
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (change != null)
              Text(
                '${up ? '+' : ''}$change% vs la semana anterior',
                style: TextStyle(
                  fontSize: 12,
                  color: up ? const Color(0xFFFF6B6B) : const Color(0xFF57D9A3),
                ),
              ),
            if (s != null && s.daily.isNotEmpty) ...[
              const SizedBox(height: 12),
              Sparkline(
                values: s.daily,
                color: theme.colorScheme.primary,
                height: 36,
              ),
            ],
            for (final other in s?.otherCurrencies ?? const <CurrencyTotal>[])
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Además, ${formatMoney(other.weekTotal, other.currency)} '
                  'en ${other.currency} (no se suma).',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.summary});
  final FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = summary.byCategory.isEmpty
        ? 1.0
        : summary.byCategory.first.total.clamp(0.01, double.infinity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            for (final c in summary.byCategory)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(ExpenseCategoryStyle.of(c.category).icon,
                        size: 18, color: ExpenseCategoryStyle.of(c.category).color),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 92,
                      child: Text(
                        ExpenseCategoryStyle.of(c.category).label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (c.total / top).clamp(0.0, 1.0),
                          minHeight: 6,
                          color: ExpenseCategoryStyle.of(c.category).color,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatMoney(c.total, summary.currency),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseList extends ConsumerWidget {
  const _ExpenseList({required this.state});
  final ExpensesState state;

  Future<void> _remove(BuildContext context, WidgetRef ref, Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar este gasto?'),
        content: Text(
          '${formatMoney(e.amount, e.currency)} · '
          '${e.note ?? ExpenseCategoryStyle.of(e.category).label}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(financeApiProvider).removeExpense(e.id);
      messenger.showSnackBar(const SnackBar(content: Text('Gasto borrado.')));
    } on ApiException catch (err) {
      messenger.showSnackBar(SnackBar(content: Text(err.message)));
    } finally {
      FinanceScreen.refresh(ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.items.isEmpty) {
      return _Notice(
        state.errorMessage ??
            'Aún no hay gastos. Añade uno o escribe en una captura algo como '
                '«gasté 20 en el almuerzo» y lo apunto solo.',
      );
    }
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        for (final e in state.items)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    ExpenseCategoryStyle.of(e.category).color.withValues(alpha: 0.15),
                child: Icon(ExpenseCategoryStyle.of(e.category).icon,
                    color: ExpenseCategoryStyle.of(e.category).color, size: 20),
              ),
              title: Text(
                (e.note ?? '').trim().isEmpty
                    ? ExpenseCategoryStyle.of(e.category).label
                    : e.note!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                e.fromAi
                    ? '${formatDayTime(e.spentAt)} · lo detecté en una captura'
                    : formatDayTime(e.spentAt),
                style: TextStyle(color: muted),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatMoney(e.amount, e.currency),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    tooltip: 'Borrar gasto',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline, color: muted, size: 20),
                    onPressed: () => _remove(context, ref, e),
                  ),
                ],
              ),
              onTap: e.captureId == null
                  ? null
                  : () => context.push('/capture/${e.captureId}/insights'),
            ),
          ),
        if (state.hasMore || state.isLoadingMore)
          Center(
            child: state.isLoadingMore
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  )
                : TextButton.icon(
                    onPressed: ref.read(expensesProvider.notifier).loadMore,
                    icon: const Icon(Icons.expand_more),
                    label: const Text('Cargar más'),
                  ),
          ),
      ],
    );
  }
}

/// What the editor returns.
class _ExpenseDraft {
  const _ExpenseDraft(this.amount, this.category, this.note);
  final double amount;
  final String category;
  final String? note;
}

/// Parses "12,50", "1.234,50", "1,500" or "12.5" into a positive amount
/// (null when it is not one). Same rules as the AI side: with both separators
/// the last one is the decimal; a lone separator followed by exactly three
/// digits groups thousands.
double? parseAmountInput(String raw) {
  var text = raw.trim().replaceAll(RegExp(r'[^\d.,]'), '');
  if (text.isEmpty) return null;
  final comma = text.lastIndexOf(','), dot = text.lastIndexOf('.');
  if (comma >= 0 && dot >= 0) {
    text = comma > dot
        ? text.replaceAll('.', '').replaceAll(',', '.')
        : text.replaceAll(',', '');
  } else if (comma >= 0 || dot >= 0) {
    final sep = comma >= 0 ? ',' : '.';
    final last = comma >= 0 ? comma : dot;
    final head = text.substring(0, last), tail = text.substring(last + 1);
    text = tail.length == 3 && head.isNotEmpty
        ? text.replaceAll(sep, '')
        : '${head.replaceAll(sep, '')}.$tail';
  }
  final value = double.tryParse(text);
  return value != null && value > 0 ? value : null;
}

class _ExpenseEditor extends StatefulWidget {
  const _ExpenseEditor({required this.currency});
  final String currency;

  @override
  State<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<_ExpenseEditor> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _category = 'food';
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final amount = parseAmountInput(_amount.text);
    if (amount == null) {
      setState(() => _error = 'Escribe un monto mayor que cero.');
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(
      _ExpenseDraft(amount, _category, _note.text.trim().isEmpty ? null : _note.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nuevo gasto',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Monto',
                prefixText: '${currencySymbol(widget.currency)} ',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            Text('Categoría', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in ExpenseCategoryStyle.all)
                  ChoiceChip(
                    avatar: Icon(c.icon, size: 16, color: c.color),
                    label: Text(c.label),
                    selected: _category == c.key,
                    onSelected: (_) => setState(() => _category = c.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Almuerzo con Ana',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('Guardar')),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
