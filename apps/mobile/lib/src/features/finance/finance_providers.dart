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
