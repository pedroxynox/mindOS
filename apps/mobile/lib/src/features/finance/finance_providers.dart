import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../shared/api_providers.dart';
import 'data/finance_api.dart';
import 'data/finance_models.dart';

final financeApiProvider = Provider<FinanceApi>((ref) {
  return FinanceApi(ref.watch(mindosApiProvider));
});

final financeSummaryProvider =
    FutureProvider.autoDispose<FinanceSummary>((ref) async {
  await settingsReady(ref); // local days + the user's currency
  return ref.watch(financeApiProvider).summary();
});

/// The expense list with "Cargar más".
class ExpensesState {
  const ExpensesState({
    this.items = const [],
    this.nextCursor,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
  });

  final List<Expense> items;
  final String? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;

  bool get hasMore => nextCursor != null;
}

class ExpensesController extends StateNotifier<ExpensesState> {
  ExpensesController(this._api) : super(const ExpensesState(isLoading: true)) {
    refresh();
  }

  final FinanceApi _api;

  Future<void> refresh() async {
    try {
      final page = await _api.listExpenses();
      if (!mounted) return;
      state = ExpensesState(items: page.data, nextCursor: page.nextCursor);
    } catch (_) {
      if (!mounted) return;
      state = const ExpensesState(
        errorMessage: 'No se pudieron cargar tus gastos.',
      );
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.isLoadingMore) return;
    state = ExpensesState(
      items: state.items,
      nextCursor: cursor,
      isLoadingMore: true,
    );
    try {
      final page = await _api.listExpenses(cursor: cursor);
      if (!mounted) return;
      state = ExpensesState(
        items: [...state.items, ...page.data],
        nextCursor: page.nextCursor,
      );
    } catch (_) {
      if (!mounted) return;
      state = ExpensesState(
        items: state.items,
        nextCursor: cursor,
        errorMessage: 'No se pudieron cargar más gastos.',
      );
    }
  }
}

final expensesProvider =
    StateNotifierProvider.autoDispose<ExpensesController, ExpensesState>((ref) {
  return ExpensesController(ref.watch(financeApiProvider));
});
