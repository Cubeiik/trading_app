import 'package:flutter/material.dart';
import 'package:trading_app/app/widgets/custom_text_field.dart';
import 'package:trading_app/core/theme/app_colors.dart';
import 'package:trading_app/core/theme/app_text_styles.dart';

class CustomDropdown<T> extends StatelessWidget {
  const CustomDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.hint,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        dropdownColor: AppColors.secondaryBackground,
        style: AppTextStyles.symbolLabel,
        iconEnabledColor: AppColors.secondaryText,
        iconDisabledColor: AppColors.tertiaryText,
        hint: hint == null ? null : Text(hint!, style: AppTextStyles.caption),
        decoration: customInputDecoration(),
      ),
    );
  }
}
