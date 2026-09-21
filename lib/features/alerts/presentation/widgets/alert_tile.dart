import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/price_alert.dart';
import 'alert_text.dart';

class AlertTile extends StatelessWidget {
  const AlertTile({
    required this.alert,
    required this.onDelete,
    this.onTap,
    super.key,
  });

  final PriceAlert alert;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final origin = alertOrigin(alert);
    final outcome = alertOutcome(alert);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.s,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(alert.symbol, style: AppTextStyles.symbolLabel),
                      const SizedBox(width: AppSpacing.s),
                      Text(
                        alertCondition(alert),
                        style: AppTextStyles.priceCell,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    outcome ??
                        origin ??
                        'Created ${formatTimestamp(alert.createdAt)}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete alert',
            ),
          ],
        ),
      ),
    );
  }
}
