import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_text_styles.dart';

final _majorFormat = NumberFormat('#,##0.00');

String formatPrice(double price) => _majorFormat.format(price);

class PriceText extends StatelessWidget {
  const PriceText({required this.price, this.style, super.key});

  final double? price;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final value = price;
    return Text(
      value == null ? '—' : formatPrice(value),
      style: style ?? AppTextStyles.priceCell,
    );
  }
}
