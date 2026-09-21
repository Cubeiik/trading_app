import 'package:flutter/material.dart';

import '../../../../app/widgets/custom_dialog.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../quotes/presentation/widgets/price_text.dart';
import '../../domain/price_alert.dart';
import 'alert_text.dart';

class AlertTile extends StatelessWidget {
  const AlertTile({required this.alert, required this.onDelete, this.onTap, super.key});

  final PriceAlert alert;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final origin = alertOrigin(alert);
    final outcome = alertOutcome(alert);
    final isLong = alert.direction == AlertDirection.above;
    final targetColor = isLong ? AppColors.priceUp : AppColors.priceDown;

    return Material(
      color: AppColors.secondaryBackground,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        side: const BorderSide(color: AppColors.stroke),
      ),
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.stroke.withValues(alpha: 0.5),
        highlightColor: AppColors.stroke.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.ms),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(alert.symbol, style: AppTextStyles.symbolLabel.copyWith(color: AppColors.primaryText)),
                        const SizedBox(width: AppSpacing.s),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: AppSpacing.xxs),
                            decoration: BoxDecoration(
                              color: AppColors.stroke,
                              borderRadius: BorderRadius.circular(AppSpacing.s),
                            ),
                            child: Text.rich(
                              TextSpan(
                                style: AppTextStyles.caption.copyWith(color: targetColor),
                                children: [
                                  TextSpan(text: sideLabel(alert.side)),
                                  const TextSpan(text: '  '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Icon(Icons.circle, size: 6, color: targetColor),
                                  ),
                                  const TextSpan(text: '  '),
                                  TextSpan(
                                    text: '${isLong ? 'Long' : 'Short'} ${formatPrice(alert.targetPrice)}',
                                    style: AppTextStyles.caption.copyWith(color: targetColor),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (outcome != null || origin != null)
                      Text(outcome ?? origin!, style: AppTextStyles.caption.copyWith(color: AppColors.secondaryText))
                    else
                      Text.rich(
                        TextSpan(
                          style: AppTextStyles.caption.copyWith(color: AppColors.secondaryText),
                          children: [
                            const TextSpan(text: 'Created at '),
                            TextSpan(text: formatPrice(alert.referencePrice ?? alert.targetPrice)),
                            const TextSpan(text: '  '),
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Icon(Icons.circle, size: 6, color: AppColors.secondaryText),
                            ),
                            const TextSpan(text: '  '),
                            TextSpan(text: formatTimestamp(alert.createdAt)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () async {
                  final confirmed = await CustomDialog.show(
                    context,
                    title: 'Delete alert',
                    description: 'Are you sure you want to delete this alert? This action cannot be undone.',
                  );
                  if (confirmed) {
                    onDelete();
                  }
                },
                icon: const Icon(Icons.delete_outline),
                color: AppColors.priceDown,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                tooltip: 'Delete alert',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
