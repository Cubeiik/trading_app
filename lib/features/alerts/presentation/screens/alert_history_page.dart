import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/widgets/message_view.dart';
import '../cubit/alerts_cubit.dart';
import '../cubit/alerts_state.dart';
import '../widgets/alert_tile.dart';

class AlertHistoryPage extends StatelessWidget {
  const AlertHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: BlocBuilder<AlertsCubit, AlertsState>(
        buildWhen: (previous, current) => previous.triggered != current.triggered,
        builder: (context, state) {
          if (state.triggered.isEmpty) {
            return const MessageView(message: 'No alerts have been triggered yet.');
          }

          return ListView.builder(
            itemCount: state.triggered.length,
            itemBuilder: (context, index) {
              final alert = state.triggered[index];
              return AlertTile(
                key: ValueKey(alert.id),
                alert: alert,
                onTap: () => context.go(Routes.instrumentDetails(alert.symbol)),
                onDelete: () => context.read<AlertsCubit>().delete(alert.id),
              );
            },
          );
        },
      ),
    );
  }
}
