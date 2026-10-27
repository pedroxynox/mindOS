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

  /// Log an expense. The currency defaults (server-side) to the user's own.
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
}
