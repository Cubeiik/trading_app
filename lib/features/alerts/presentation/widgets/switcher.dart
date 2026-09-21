import 'package:flutter/material.dart';
import 'package:trading_app/core/theme/app_colors.dart';
import 'package:trading_app/core/theme/app_spacing.dart';
import 'package:trading_app/core/theme/app_text_styles.dart';

class Switcher extends StatefulWidget {
  const Switcher({super.key, required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<Switcher> with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: widget.labels.length, vsync: this, initialIndex: widget.index);
  }

  @override
  void didUpdateWidget(covariant Switcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index && widget.index != _controller.index && !_controller.indexIsChanging) {
      _controller.animateTo(widget.index);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTextStyles.button.copyWith(fontSize: 16, height: 1.0, letterSpacing: 0.0);

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.secondaryBackground,
          borderRadius: BorderRadius.circular(AppSpacing.m),
          border: Border.all(color: AppColors.stroke, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs + 2),
          child: TabBar(
            controller: _controller,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(color: AppColors.lightBlue, borderRadius: BorderRadius.circular(AppSpacing.ms)),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: AppColors.primaryTextInverted,
            unselectedLabelColor: AppColors.secondaryText,
            labelStyle: labelStyle,
            unselectedLabelStyle: labelStyle,
            splashBorderRadius: BorderRadius.circular(AppSpacing.ms),
            onTap: (index) {
              if (index != widget.index) {
                widget.onChanged(index);
              }
            },
            tabs: [for (final label in widget.labels) Tab(text: label)],
          ),
        ),
      ),
    );
  }
}
