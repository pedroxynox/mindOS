import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/api_providers.dart';
import 'data/finance_api.dart';
import 'data/finance_models.dart';

final financeApiProvider = Provider<FinanceApi>((ref) {
  return FinanceApi(ref.watch(mindosApiProvider));
});

final financeSummaryProvider = FutureProvider.autoDispose<FinanceSummary>((ref) {
  return ref.watch(financeApiProvider).summary();
});
