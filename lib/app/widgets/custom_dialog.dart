import 'package:flutter/material.dart';
import 'package:trading_app/core/theme/app_colors.dart';
import 'package:trading_app/core/theme/app_spacing.dart';
import 'package:trading_app/core/theme/app_text_styles.dart';

import 'custom_button.dart';

class CustomDialog extends StatelessWidget {
  const CustomDialog({
    required this.title,
    required this.description,
    this.cancelLabel = 'Cancel',
    this.confirmLabel = 'Delete',
    super.key,
  });

  final String title;
  final String description;
  final String cancelLabel;
  final String confirmLabel;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String description,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Delete',
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierColor: AppColors.primaryBackground.withValues(alpha: 0.72),
          builder: (context) => CustomDialog(
            title: title,
            description: description,
            cancelLabel: cancelLabel,
            confirmLabel: confirmLabel,
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.secondaryBackground,
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          border: Border.all(color: AppColors.stroke, width: 2),
        ),
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.screenTitle),
            const SizedBox(height: AppSpacing.s),
            Text(description, style: AppTextStyles.caption),
            const SizedBox(height: AppSpacing.l),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    backgroundColor: AppColors.stroke,
                    foregroundColor: AppColors.primaryText,
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: CustomButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    backgroundColor: AppColors.priceDown,
                    foregroundColor: AppColors.primaryText,
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
