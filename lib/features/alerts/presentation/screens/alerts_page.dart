import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/widgets/message_view.dart';
import '../../../quotes/presentation/widgets/connection_banner.dart';
import '../cubit/alerts_cubit.dart';
import '../cubit/alerts_state.dart';
import '../widgets/alert_tile.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.createAlert),
        icon: const Icon(Icons.add),
        label: const Text('New alert'),
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: BlocBuilder<AlertsCubit, AlertsState>(
              buildWhen: (previous, current) =>
                  previous.active != current.active,
              builder: (context, state) {
                if (state.active.isEmpty) {
                  return const MessageView(
                    message:
                        'No active alerts.\nCreate one from an instrument or with the button below.',
                  );
                }

                return ListView.builder(
                  itemCount: state.active.length,
                  itemBuilder: (context, index) {
                    final alert = state.active[index];
                    return AlertTile(
                      key: ValueKey(alert.id),
                      alert: alert,
                      onTap: () =>
                          context.go(Routes.instrumentDetails(alert.symbol)),
                      onDelete: () =>
                          context.read<AlertsCubit>().delete(alert.id),
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
