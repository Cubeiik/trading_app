import 'package:equatable/equatable.dart';

class Instrument extends Equatable {
  const Instrument({required this.symbol, required this.contractType});

  final String symbol;
  final int contractType;

  @override
  List<Object?> get props => [symbol, contractType];
}
