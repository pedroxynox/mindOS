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

  Future<void> addExpense(
    double amount, {
    String? category,
    String currency = 'USD',
  }) async {
    await _api.post('/finance/expenses', {
      'amount': amount,
      'currency': currency,
      if (category != null && category.isNotEmpty) 'category': category,
    });
  }
}
