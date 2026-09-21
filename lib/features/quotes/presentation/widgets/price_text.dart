import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_text_styles.dart';

final _formats = <int, NumberFormat>{};

// Two decimals hide every move a sub-dollar instrument makes.
int _decimalsFor(double price) {
  final magnitude = price.abs();
  if (magnitude >= 100) return 2;
  if (magnitude >= 10) return 3;
  if (magnitude >= 1) return 4;
  if (magnitude >= 0.1) return 5;
  return 6;
}

String formatPrice(double price) {
  final decimals = _decimalsFor(price);
  final format = _formats.putIfAbsent(decimals, () => NumberFormat('#,##0.${'0' * decimals}'));
  return format.format(price);
}

class PriceText extends StatelessWidget {
  const PriceText({required this.price, this.style, super.key});

  final double? price;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final value = price;
    return Text(value == null ? '—' : formatPrice(value), style: style ?? AppTextStyles.priceCell);
  }
}
