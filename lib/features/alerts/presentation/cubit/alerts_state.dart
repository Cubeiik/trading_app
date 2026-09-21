import 'package:equatable/equatable.dart';

import '../../domain/price_alert.dart';

class AlertsState extends Equatable {
  const AlertsState({
    this.active = const [],
    this.triggered = const [],
    this.pendingNotifications = const [],
    this.error,
  });

  final List<PriceAlert> active;
  final List<PriceAlert> triggered;
  final List<PriceAlert> pendingNotifications;
  final String? error;

  AlertsState copyWith({
    List<PriceAlert>? active,
    List<PriceAlert>? triggered,
    List<PriceAlert>? pendingNotifications,
    String? error,
  }) {
    return AlertsState(
      active: active ?? this.active,
      triggered: triggered ?? this.triggered,
      pendingNotifications: pendingNotifications ?? this.pendingNotifications,
      error: error,
    );
  }

  @override
  List<Object?> get props => [active, triggered, pendingNotifications, error];
}
