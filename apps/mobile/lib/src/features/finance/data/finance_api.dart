import '../../shared/mindos_api.dart';
import 'finance_models.dart';

/// Client for `/v1/finance/*`.
class FinanceApi {
  FinanceApi(this._api);
  final MindosApi _api;

  Future<FinanceSummary> summary() async {
    final json = await _api.get('/finance/summary');
    return FinanceSummary.fromJson(json as Map<String, dynamic>);
  }

  /// Log an expense. The currency defaults (server-side) to the user's own;
  /// [category] is a canonical key (food, transport, ...).
  Future<void> addExpense(
    double amount, {
    String? category,
    String? currency,
    String? note,
  }) async {
    await _api.post('/finance/expenses', {
      'amount': amount,
      if (currency != null) 'currency': currency,
      if (category != null && category.isNotEmpty) 'category': category,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  /// Every expense (manual and AI-detected), most recently logged first.
  Future<ExpensePage> listExpenses({String? cursor, int limit = 50}) async {
    final json = await _api.get('/finance/expenses', query: {
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    }) as Map<String, dynamic>;
    return ExpensePage(
      data: (json['data'] as List<dynamic>? ?? [])
          .map((e) => Expense.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
    );
  }

  Future<void> removeExpense(String id) async {
    await _api.delete('/finance/expenses/$id');
  }
}
