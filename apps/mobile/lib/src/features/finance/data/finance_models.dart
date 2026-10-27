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

/// One expense — typed by the user or found by mindOS in a capture.
class Expense {
  const Expense({
    required this.id,
    required this.amount,
    required this.currency,
    required this.category,
    required this.spentAt,
    this.note,
    this.origin = 'manual_text',
    this.captureId,
  });

  final String id;
  final double amount;
  final String currency;

  /// Canonical key (food, transport, ...).
  final String category;
  final DateTime spentAt;
  final String? note;
  final String origin;

  /// The capture the AI found it in (null when typed by hand).
  final String? captureId;

  bool get fromAi => origin == 'ai';

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: (json['currency'] as String?) ?? 'USD',
        category: (json['category'] as String?) ?? 'other',
        spentAt: DateTime.parse(
            (json['spent_at'] ?? json['created_at']) as String),
        note: json['note'] as String?,
        origin: (json['origin'] as String?) ?? 'manual_text',
        captureId: json['capture_id'] as String?,
      );
}

/// A page of the expense list.
class ExpensePage {
  const ExpensePage({required this.data, this.nextCursor});
  final List<Expense> data;
  final String? nextCursor;
}
