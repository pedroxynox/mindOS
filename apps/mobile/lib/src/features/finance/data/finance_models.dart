// Client-side model for the weekly finance summary (mirrors /v1/finance/summary).

class FinanceSummary {
  const FinanceSummary({
    required this.currency,
    required this.weekTotal,
    required this.prevWeekTotal,
    required this.changePct,
    required this.daily,
  });

  final String currency;
  final double weekTotal;
  final double prevWeekTotal;
  final int? changePct;
  final List<double> daily;

  bool get isEmpty => weekTotal == 0 && prevWeekTotal == 0;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) => FinanceSummary(
        currency: (json['currency'] as String?) ?? 'USD',
        weekTotal: (json['week_total'] as num?)?.toDouble() ?? 0,
        prevWeekTotal: (json['prev_week_total'] as num?)?.toDouble() ?? 0,
        changePct: (json['change_pct'] as num?)?.toInt(),
        daily: (json['daily'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}
