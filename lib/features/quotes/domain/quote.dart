import 'package:equatable/equatable.dart';

enum QuoteSide { bid, ask }

class Quote extends Equatable {
  const Quote({
    required this.symbol,
    required this.bid,
    required this.ask,
    required this.timestamp,
  });

  final String symbol;
  final double bid;
  final double ask;
  final DateTime timestamp;

  double priceFor(QuoteSide side) => side == QuoteSide.bid ? bid : ask;

  @override
  List<Object?> get props => [symbol, bid, ask, timestamp];
}
