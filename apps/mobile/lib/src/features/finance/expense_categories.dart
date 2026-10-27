import 'package:flutter/material.dart';

/// The canonical expense categories (same keys as the API and the AI's
/// expense detector), shown in Spanish with an icon and a colour.
class ExpenseCategoryStyle {
  const ExpenseCategoryStyle(this.key, this.label, this.icon, this.color);

  final String key;
  final String label;
  final IconData icon;
  final Color color;

  static const all = <ExpenseCategoryStyle>[
    ExpenseCategoryStyle(
        'food', 'Comida', Icons.restaurant_outlined, Color(0xFFFFB74D)),
    ExpenseCategoryStyle('transport', 'Transporte',
        Icons.directions_car_outlined, Color(0xFF64B5F6)),
    ExpenseCategoryStyle('home', 'Casa', Icons.home_outlined, Color(0xFFA1887F)),
    ExpenseCategoryStyle(
        'health', 'Salud', Icons.favorite_outline, Color(0xFFE57373)),
    ExpenseCategoryStyle(
        'leisure', 'Ocio', Icons.local_activity_outlined, Color(0xFFBA68C8)),
    ExpenseCategoryStyle('shopping', 'Compras', Icons.shopping_bag_outlined,
        Color(0xFF4DB6AC)),
    ExpenseCategoryStyle(
        'bills', 'Cuentas', Icons.receipt_long_outlined, Color(0xFF90A4AE)),
    ExpenseCategoryStyle(
        'education', 'Educación', Icons.school_outlined, Color(0xFF7986CB)),
    ExpenseCategoryStyle(
        'other', 'Otros', Icons.more_horiz, Color(0xFF9E9BC0)),
  ];

  /// Style of a key; anything unknown is "Otros".
  static ExpenseCategoryStyle of(String? key) =>
      all.firstWhere((c) => c.key == key, orElse: () => all.last);
}
