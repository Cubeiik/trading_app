import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors.dart';
import '../../data/alert_repository.dart';
import '../../domain/price_alert.dart';
import 'alerts_state.dart';

class AlertsCubit extends Cubit<AlertsState> {
  AlertsCubit(AlertRepository repository)
    : _repository = repository,
      super(_restore(repository));

  final AlertRepository _repository;

  static AlertsState _restore(AlertRepository repository) {
    final stored = repository.loadAll();

    final active = stored.where((alert) => alert.isActive).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final triggered = stored.where((alert) => !alert.isActive).toList()
      ..sort(
        (a, b) => (b.triggeredAt ?? b.createdAt).compareTo(
          a.triggeredAt ?? a.createdAt,
        ),
      );

    return AlertsState(active: active, triggered: triggered);
  }

  Future<void> create(PriceAlert alert) async {
    emit(state.copyWith(active: [alert, ...state.active]));

    try {
      await _repository.save(alert);
    } on AppException catch (error) {
      emit(state.copyWith(error: error.message));
    }
  }

  Future<void> delete(String id) async {
    emit(
      state.copyWith(
        active: state.active.where((alert) => alert.id != id).toList(),
        triggered: state.triggered.where((alert) => alert.id != id).toList(),
        pendingNotifications: state.pendingNotifications
            .where((alert) => alert.id != id)
            .toList(),
      ),
    );

    try {
      await _repository.delete(id);
    } on AppException catch (error) {
      emit(state.copyWith(error: error.message));
    }
  }

  Future<void> onTriggered(PriceAlert alert, double price) async {
    if (!state.active.any((candidate) => candidate.id == alert.id)) {
      return;
    }

    final fired = alert.markTriggered(price: price, at: DateTime.now());

    String? error;
    try {
      await _repository.save(fired);
    } on AppException catch (exception) {
      error = exception.message;
    }

    emit(
      state.copyWith(
        active: state.active
            .where((candidate) => candidate.id != alert.id)
            .toList(),
        triggered: [fired, ...state.triggered],
        pendingNotifications: [...state.pendingNotifications, fired],
        error: error,
      ),
    );
  }

  void acknowledge(String id) {
    emit(
      state.copyWith(
        pendingNotifications: state.pendingNotifications
            .where((alert) => alert.id != id)
            .toList(),
      ),
    );
  }
}
