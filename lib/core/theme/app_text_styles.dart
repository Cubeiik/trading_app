import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

abstract final class AppTextStyles {
  static const button = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.bodySize,
    fontWeight: AppTypography.semiBold,
    color: AppColors.primaryText,
  );

  static const symbolLabel = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.labelSize,
    fontWeight: AppTypography.bold,
    color: AppColors.primaryText,
  );

  static const priceCell = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.bodySize,
    fontWeight: AppTypography.medium,
    fontFeatures: [FontFeature.tabularFigures()],
    color: AppColors.primaryText,
  );

  static const priceHeadline = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.displaySize,
    fontWeight: AppTypography.semiBold,
    fontFeatures: [FontFeature.tabularFigures()],
    color: AppColors.primaryText,
  );

  static const headline = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.headlineSize,
    fontWeight: AppTypography.semiBold,
    color: AppColors.primaryText,
  );

  static const screenTitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.titleSize,
    fontWeight: AppTypography.semiBold,
    color: AppColors.primaryText,
  );

  static const caption = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.captionSize,
    fontWeight: AppTypography.regular,
    color: AppColors.secondaryText,
  );
}
