import 'package:flutter/material.dart';
import 'package:trading_app/core/theme/app_colors.dart';
import 'package:trading_app/core/theme/app_spacing.dart';
import 'package:trading_app/core/theme/app_text_styles.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height,
    this.isDisabled = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final VoidCallback onPressed;
  final Widget child;
  final double? height;
  final bool isDisabled;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height ?? 48,
      child: FilledButton(
        onPressed: isDisabled ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.lightBlue,
          foregroundColor: foregroundColor ?? AppColors.primaryTextInverted,
          disabledBackgroundColor: AppColors.stroke,
          disabledForegroundColor: AppColors.secondaryText,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
          textStyle: AppTextStyles.button.copyWith(fontSize: 16, height: 1.0, letterSpacing: 0.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.m)),
        ),
        child: child,
      ),
    );
  }
}
