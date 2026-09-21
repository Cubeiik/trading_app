import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trading_app/app/widgets/custom_floating_action_button.dart';
import 'package:trading_app/app/router/custom_router.dart';
import '../../../../app/widgets/custom_app_bar.dart';
import '../../../../app/widgets/message_view.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../quotes/presentation/widgets/connection_banner.dart';
import '../cubit/alerts_cubit.dart';
import '../cubit/alerts_state.dart';
import '../widgets/alert_tile.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Alerts'),
      floatingActionButton: CustomFloatingActionButton(
        heroTag: 'alerts-new-alert',
        onPressed: () => CustomRouter.push(context, RouteScreens.createAlert),
        label: 'New alert',
        icon: Icons.add,
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: BlocBuilder<AlertsCubit, AlertsState>(
              buildWhen: (previous, current) => previous.active != current.active,
              builder: (context, state) {
                if (state.active.isEmpty) {
                  return const MessageView(
                    message: 'No active alerts.\nCreate one from an instrument or with the button below.',
                  );
                }

                return ListView.builder(
                  itemCount: state.active.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final alert = state.active[index];
                    final isFirst = index == 0;
                    final isLast = index == state.active.length - 1;
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
          ),
        ],
      ),
    );
  }
}
