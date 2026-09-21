import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/market_data_socket.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../cubit/quotes_cubit.dart';
import '../cubit/quotes_state.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<QuotesCubit, QuotesState, ConnectionStatus>(
      selector: (state) => state.status,
      builder: (context, status) {
        if (status == ConnectionStatus.connected) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          color: AppColors.statusWarning,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.s,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_messageFor(status), style: AppTextStyles.caption),
              ),
              if (status != ConnectionStatus.connecting)
                TextButton(
                  onPressed: () => context.read<QuotesCubit>().reconnectNow(),
                  child: const Text('Retry now'),
                ),
            ],
          ),
        );
      },
    );
  }

  String _messageFor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connecting:
        return 'Connecting…';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting — showing last known prices';
      case ConnectionStatus.disconnected:
        return 'Disconnected — showing last known prices';
      case ConnectionStatus.connected:
        return '';
    }
  }
}
