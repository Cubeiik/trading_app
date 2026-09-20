import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/market_data_socket.dart';
import '../data/quote_repository.dart';
import '../domain/quote.dart';
import 'quotes_state.dart';

class QuotesCubit extends Cubit<QuotesState> {
  QuotesCubit(this._repository)
    : super(QuotesState(status: _repository.currentStatus)) {
    _quotesSubscription = _repository.quotes.listen(_onQuote);
    _statusSubscription = _repository.status.listen(_onStatus);
  }

  final QuoteRepository _repository;

  late final StreamSubscription<Quote> _quotesSubscription;
  late final StreamSubscription<ConnectionStatus> _statusSubscription;

  void subscribe(String symbol) => _repository.subscribe(symbol);

  void reconnectNow() => _repository.reconnectNow();

  void _onQuote(Quote quote) {
    emit(state.copyWith(quotes: {...state.quotes, quote.symbol: quote}));
  }

  void _onStatus(ConnectionStatus status) =>
      emit(state.copyWith(status: status));

  @override
  Future<void> close() async {
    await _quotesSubscription.cancel();
    await _statusSubscription.cancel();
    return super.close();
  }
}
