import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trading_app/core/theme/app_colors.dart';
import 'package:trading_app/core/theme/app_text_styles.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  void _onDestinationSelected(int index) {
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.primaryBackground,
        indicatorColor: AppColors.lightBlue,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected) ? AppColors.lightBlue : AppColors.secondaryText;
          return AppTextStyles.caption.copyWith(color: color);
        }),
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined, color: AppColors.secondaryText),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Instruments',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined, color: AppColors.secondaryText),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined, color: AppColors.secondaryText),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
