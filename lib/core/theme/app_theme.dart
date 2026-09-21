import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.lightBlue),
    scaffoldBackgroundColor: AppColors.primaryBackground,
    fontFamily: AppTypography.fontFamily,
  );
}
