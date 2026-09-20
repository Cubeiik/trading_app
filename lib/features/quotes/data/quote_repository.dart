import '../../../core/network/market_data_socket.dart';
import '../domain/quote.dart';

class QuoteRepository {
  QuoteRepository(this._socket);

  final MarketDataSocket _socket;

  Stream<Quote> get quotes => _socket.quotes;

  Stream<ConnectionStatus> get status => _socket.status;

  ConnectionStatus get currentStatus => _socket.currentStatus;

  void subscribeAll(Iterable<String> symbols) => _socket.subscribe(symbols);

  void subscribe(String symbol) => _socket.subscribe([symbol]);

  void reconnectNow() => _socket.reconnectNow();
}
