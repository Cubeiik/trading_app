import 'package:flutter/material.dart';
import 'package:trading_app/core/theme/app_colors.dart';
import 'package:trading_app/core/theme/app_spacing.dart';
import 'package:trading_app/core/theme/app_text_styles.dart';

OutlineInputBorder customInputBorder({Color color = AppColors.stroke}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.m),
    borderSide: BorderSide(color: color, width: 2),
  );
}

InputDecoration customInputDecoration({String? hintText, String? suffixText}) {
  final border = customInputBorder();
  return InputDecoration(
    filled: true,
    fillColor: AppColors.secondaryBackground,
    hintText: hintText,
    hintStyle: AppTextStyles.caption,
    suffixText: suffixText,
    suffixStyle: AppTextStyles.caption,
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
    border: border,
    enabledBorder: border,
    focusedBorder: customInputBorder(),
    disabledBorder: border,
    errorBorder: customInputBorder(color: AppColors.priceDown),
    focusedErrorBorder: customInputBorder(color: AppColors.priceDown),
  );
}

class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    this.controller,
    this.hintText,
    this.suffixText,
    this.keyboardType,
    this.onChanged,
    this.autofocus = false,
    this.style,
  });

  final TextEditingController? controller;
  final String? hintText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        style: style ?? AppTextStyles.symbolLabel,
        keyboardType: keyboardType,
        cursorColor: AppColors.lightBlue,
        onChanged: onChanged,
        decoration: customInputDecoration(hintText: hintText, suffixText: suffixText),
      ),
    );
  }
}
