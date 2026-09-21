import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../features/alerts/domain/price_alert.dart';
import '../../features/alerts/presentation/widgets/alert_text.dart';
import '../../features/alerts/presentation/cubit/alerts_cubit.dart';
import '../../features/alerts/presentation/cubit/alerts_state.dart';
import '../router.dart';

const _visibleFor = Duration(seconds: 5);

class AlertNotificationHost extends StatefulWidget {
  const AlertNotificationHost({
    required this.router,
    required this.child,
    super.key,
  });

  // The host sits in MaterialApp's builder, above the Navigator that provides
  // InheritedGoRouter, so context.go() is not available here.
  final GoRouter router;
  final Widget child;

  @override
  State<AlertNotificationHost> createState() => _AlertNotificationHostState();
}

class _AlertNotificationHostState extends State<AlertNotificationHost> {
  Timer? _dismissTimer;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AlertsCubit, AlertsState>(
          listenWhen: (previous, current) =>
              _firstOf(previous)?.id != _firstOf(current)?.id,
          listener: (context, state) => _scheduleDismiss(_firstOf(state)),
        ),
        BlocListener<AlertsCubit, AlertsState>(
          listenWhen: (previous, current) =>
              previous.error != current.error && current.error != null,
          listener: (context, state) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(SnackBar(content: Text(state.error!)));
          },
        ),
      ],
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          BlocSelector<AlertsCubit, AlertsState, PriceAlert?>(
            selector: _firstOf,
            builder: (context, alert) => Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: alert == null
                  ? const SizedBox.shrink()
                  : _Notification(
                      alert: alert,
                      onDismiss: () =>
                          context.read<AlertsCubit>().acknowledge(alert.id),
                      onOpenHistory: () {
                        context.read<AlertsCubit>().acknowledge(alert.id);
                        widget.router.go(Routes.history);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static PriceAlert? _firstOf(AlertsState state) =>
      state.pendingNotifications.isEmpty
      ? null
      : state.pendingNotifications.first;

  void _scheduleDismiss(PriceAlert? alert) {
    _dismissTimer?.cancel();
    if (alert == null) {
      return;
    }

    _dismissTimer = Timer(
      _visibleFor,
      () => context.read<AlertsCubit>().acknowledge(alert.id),
    );
  }
}

class _Notification extends StatelessWidget {
  const _Notification({
    required this.alert,
    required this.onDismiss,
    required this.onOpenHistory,
  });

  final PriceAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s),
        child: Material(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          child: InkWell(
            onTap: onOpenHistory,
            borderRadius: BorderRadius.circular(AppSpacing.radiusM),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${alert.symbol} ${alertCondition(alert)}',
                          style: AppTextStyles.symbolLabel.copyWith(
                            color: colors.onInverseSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          alertOutcome(alert) ?? 'Alert triggered',
                          style: AppTextStyles.caption.copyWith(
                            color: colors.onInverseSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close, semanticLabel: 'Dismiss'),
                    color: colors.onInverseSurface,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
