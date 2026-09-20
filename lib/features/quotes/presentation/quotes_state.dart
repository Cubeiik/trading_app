import 'package:equatable/equatable.dart';

import '../../../core/network/market_data_socket.dart';
import '../domain/quote.dart';

class QuotesState extends Equatable {
  const QuotesState({
    this.quotes = const {},
    this.status = ConnectionStatus.disconnected,
  });

  final Map<String, Quote> quotes;
  final ConnectionStatus status;

  bool get isLive => status == ConnectionStatus.connected;

  QuotesState copyWith({Map<String, Quote>? quotes, ConnectionStatus? status}) {
    return QuotesState(
      quotes: quotes ?? this.quotes,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [quotes, status];
}
