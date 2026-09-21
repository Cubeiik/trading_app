import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trading_app/app/router/custom_router.dart';

import '../../../../app/widgets/custom_app_bar.dart';
import '../../../../app/widgets/message_view.dart';
import '../../../../core/theme/app_spacing.dart';
import '../cubit/alerts_cubit.dart';
import '../cubit/alerts_state.dart';
import '../widgets/alert_tile.dart';

class AlertHistoryPage extends StatelessWidget {
  const AlertHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'History'),
      body: BlocBuilder<AlertsCubit, AlertsState>(
        buildWhen: (previous, current) => previous.triggered != current.triggered,
        builder: (context, state) {
          if (state.triggered.isEmpty) {
            return const MessageView(message: 'No alerts have been triggered yet.');
          }

          return ListView.builder(
            itemCount: state.triggered.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final alert = state.triggered[index];
              final isFirst = index == 0;
              final isLast = index == state.triggered.length - 1;
              return Padding(
                padding: EdgeInsets.only(
                  left: AppSpacing.l,
                  right: AppSpacing.l,
                  bottom: isLast ? AppSpacing.m : AppSpacing.s,
                  top: isFirst ? AppSpacing.m : 0,
                ),
                child: AlertTile(
                  key: ValueKey(alert.id),
                  alert: alert,
                  onTap: () => CustomRouter.go(context, RouteScreens.instrumentDetails, symbol: alert.symbol),
                  onDelete: () => context.read<AlertsCubit>().delete(alert.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
