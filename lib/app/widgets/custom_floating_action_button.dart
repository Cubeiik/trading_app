import 'package:flutter/material.dart';
import 'package:trading_app/core/theme/app_colors.dart';
import 'package:trading_app/core/theme/app_spacing.dart';
import 'package:trading_app/core/theme/app_text_styles.dart';

class CustomFloatingActionButton extends StatelessWidget {
  CustomFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.icon,
    Object? heroTag,
  }) : heroTag = heroTag ?? UniqueKey();

  final VoidCallback onPressed;
  final String label;
  final IconData icon;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: heroTag,
      onPressed: onPressed,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.m)),
      backgroundColor: AppColors.lightBlue,
      icon: Icon(icon, color: AppColors.primaryTextInverted),
      label: Text(label, style: AppTextStyles.button.copyWith(color: AppColors.primaryTextInverted)),
    );
  }
}
