// Client-side model for the weekly finance summary (mirrors /v1/finance/summary).

class CategoryTotal {
  const CategoryTotal({required this.category, required this.total});
  final String category;
  final double total;

  factory CategoryTotal.fromJson(Map<String, dynamic> json) => CategoryTotal(
        category: (json['category'] as String?) ?? 'otros',
        total: (json['total'] as num?)?.toDouble() ?? 0,
      );
}

class CurrencyTotal {
  const CurrencyTotal({required this.currency, required this.weekTotal});
  final String currency;
  final double weekTotal;

  factory CurrencyTotal.fromJson(Map<String, dynamic> json) => CurrencyTotal(
        currency: json['currency'] as String,
        weekTotal: (json['week_total'] as num?)?.toDouble() ?? 0,
      );
}

class FinanceSummary {
  const FinanceSummary({
    required this.currency,
    required this.weekTotal,
    required this.prevWeekTotal,
    required this.changePct,
    required this.daily,
    this.byCategory = const [],
    this.otherCurrencies = const [],
  });

  /// The user's currency; every total is in it (other currencies apart).
  final String currency;
  final double weekTotal;
  final double prevWeekTotal;
  final int? changePct;
  final List<double> daily;
  final List<CategoryTotal> byCategory;
  final List<CurrencyTotal> otherCurrencies;

  bool get isEmpty =>
      weekTotal == 0 && prevWeekTotal == 0 && otherCurrencies.isEmpty;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) => FinanceSummary(
        currency: (json['currency'] as String?) ?? 'USD',
        weekTotal: (json['week_total'] as num?)?.toDouble() ?? 0,
        prevWeekTotal: (json['prev_week_total'] as num?)?.toDouble() ?? 0,
        changePct: (json['change_pct'] as num?)?.toInt(),
        daily: (json['daily'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        byCategory: (json['by_category'] as List<dynamic>? ?? [])
            .map((e) => CategoryTotal.fromJson(e as Map<String, dynamic>))
            .toList(),
        otherCurrencies: (json['other_currencies'] as List<dynamic>? ?? [])
            .map((e) => CurrencyTotal.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
