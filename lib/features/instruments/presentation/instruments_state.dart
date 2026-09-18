import 'package:equatable/equatable.dart';

import '../domain/instrument.dart';

enum InstrumentsStatus { initial, loading, success, failure }

class InstrumentsState extends Equatable {
  const InstrumentsState({
    this.status = InstrumentsStatus.initial,
    this.instruments = const [],
    this.error,
  });

  final InstrumentsStatus status;
  final List<Instrument> instruments;
  final String? error;

  bool get isEmpty =>
      status == InstrumentsStatus.success && instruments.isEmpty;

  @override
  List<Object?> get props => [status, instruments, error];
}
