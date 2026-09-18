import 'package:flutter/material.dart';

import 'app_typography.dart';

abstract final class AppTextStyles {
  static const symbolLabel = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.bodySize,
    fontWeight: AppTypography.semiBold,
  );

  static const priceCell = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.bodySize,
    fontWeight: AppTypography.medium,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const screenTitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.titleSize,
    fontWeight: AppTypography.semiBold,
  );

  static const caption = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.captionSize,
    fontWeight: AppTypography.regular,
  );
}
