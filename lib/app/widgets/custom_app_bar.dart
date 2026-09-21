import 'package:flutter/material.dart';
import 'package:trading_app/app/router/custom_router.dart';
import 'package:trading_app/core/theme/app_colors.dart';
import 'package:trading_app/core/theme/app_spacing.dart';
import 'package:trading_app/core/theme/app_text_styles.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({required this.title, this.actions, super.key});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;

    return AppBar(
      backgroundColor: AppColors.primaryBackground,
      automaticallyImplyLeading: false,
      leading: canPop
          ? IconButton(
              onPressed: () => CustomRouter.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.primaryText),
            )
          : null,
      title: Text(title, style: AppTextStyles.headline.copyWith(color: AppColors.primaryText)),
      centerTitle: false,
      titleSpacing: canPop ? AppSpacing.s : AppSpacing.l,
      actions: actions,
    );
  }
}
