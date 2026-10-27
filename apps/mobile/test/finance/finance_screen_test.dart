import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/account/account_providers.dart';
import 'package:mindos/src/features/finance/data/finance_api.dart';
import 'package:mindos/src/features/finance/data/finance_models.dart';
import 'package:mindos/src/features/finance/finance_providers.dart';
import 'package:mindos/src/features/finance/presentation/finance_screen.dart';
import 'package:mindos/src/theme.dart';

import '../helpers.dart';

class _FakeFinance extends FinanceApi {
  _FakeFinance() : super(offlineApi());

  final added = <(double, String?, String?)>[];
  final removed = <String>[];
  late List<Expense> expenses = [
    Expense(
      id: 'e1',
      amount: 30,
      currency: 'BRL',
      category: 'food',
      spentAt: DateTime.now().subtract(const Duration(hours: 2)),
      note: 'almuerzo',
      origin: 'ai',
      captureId: 'c1',
    ),
    Expense(
      id: 'e2',
      amount: 12,
      currency: 'BRL',
      category: 'transport',
      spentAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  FinanceSummary get summaryValue => FinanceSummary.fromJson({
        'currency': 'BRL',
        'week_total': expenses.fold<double>(0, (t, e) => t + e.amount),
        'prev_week_total': 0,
        'change_pct': null,
        'daily': [0, 0, 0, 0, 0, 12, 30],
        'by_category': [
          for (final e in expenses) {'category': e.category, 'total': e.amount},
        ],
      });

  @override
  Future<FinanceSummary> summary() async => summaryValue;

  @override
  Future<ExpensePage> listExpenses({String? cursor, int limit = 50}) async =>
      ExpensePage(data: expenses);

  @override
  Future<void> addExpense(double amount,
      {String? category, String? currency, String? note}) async {
    added.add((amount, category, note));
  }

  @override
  Future<void> removeExpense(String id) async {
    removed.add(id);
    expenses = expenses.where((e) => e.id != id).toList();
  }
}

// Finanzas (mejoras-v2 §E): the week, the categories, manual and
// AI-detected expenses; add one with a category; delete one.
void main() {
  Future<_FakeFinance> pump(WidgetTester tester) async {
    final api = _FakeFinance();
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        financeApiProvider.overrideWithValue(api),
        financeSummaryProvider.overrideWith((ref) => api.summary()),
        displayCurrencyProvider.overrideWithValue('BRL'),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: const FinanceScreen()),
    ));
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('shows the week, the categories and both kinds of expense',
      (tester) async {
    await pump(tester);

    expect(find.text('R\$ 42,00'), findsOneWidget);
    expect(find.text('Comida'), findsOneWidget);
    expect(find.text('Transporte'), findsWidgets);
    expect(find.text('almuerzo'), findsOneWidget);
    expect(find.textContaining('lo detecté en una captura'), findsOneWidget);
    expect(find.text('R\$ 30,00'), findsWidgets);
  });

  testWidgets('adds an expense with a category and a note', (tester) async {
    final api = await pump(tester);

    await tester.tap(find.text('Añadir gasto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '12,50');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Transporte'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Nota (opcional)'), 'Uber');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(api.added, [(12.5, 'transport', 'Uber')]);
    expect(find.text('Gasto guardado.'), findsOneWidget);
  });

  testWidgets('refuses an empty amount', (tester) async {
    final api = await pump(tester);

    await tester.tap(find.text('Añadir gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe un monto mayor que cero.'), findsOneWidget);
    expect(api.added, isEmpty);
  });

  testWidgets('deletes an expense after confirming', (tester) async {
    final api = await pump(tester);

    await tester.tap(find.byTooltip('Borrar gasto').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
    await tester.pumpAndSettle();

    expect(api.removed, ['e1']);
    expect(find.text('almuerzo'), findsNothing);
    expect(find.text('R\$ 12,00'), findsWidgets);
  });

  test('parses amounts the way people type them', () {
    expect(parseAmountInput('12,50'), 12.5);
    expect(parseAmountInput('1.234,50'), 1234.5);
    expect(parseAmountInput('1,234.50'), 1234.5);
    expect(parseAmountInput('1.500'), 1500);
    expect(parseAmountInput('R\$ 20'), 20);
    expect(parseAmountInput('12.5'), 12.5);
    expect(parseAmountInput('0'), isNull);
    expect(parseAmountInput('abc'), isNull);
  });
}
