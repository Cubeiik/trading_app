import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';

// TODO: delete once all five screens are implemented (phase 9).
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({required this.title, this.detail, super.key});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppTextStyles.screenTitle),
              if (detail != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(detail!, style: AppTextStyles.caption, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
