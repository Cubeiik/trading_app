import 'package:flutter/services.dart';

import '../core/app_config.dart';
import '../core/network/market_data_socket.dart';
import '../core/network/websocket_transport.dart';
import '../features/alerts/data/alert_repository.dart';
import '../features/instruments/data/instrument_repository.dart';
import '../features/quotes/data/quote_repository.dart';

class AppDependencies {
  AppDependencies({
    required this.instrumentRepository,
    required this.marketDataSocket,
    required this.alertRepository,
  }) : quoteRepository = QuoteRepository(marketDataSocket);

  factory AppDependencies.production({
    required AlertRepository alertRepository,
  }) {
    return AppDependencies(
      instrumentRepository: InstrumentRepository(rootBundle),
      marketDataSocket: MarketDataSocket(
        transport: WebSocketChannelTransport(),
        uri: Uri.parse(AppConfig.wsUrl),
      ),
      alertRepository: alertRepository,
    );
  }

  final InstrumentRepository instrumentRepository;
  final MarketDataSocket marketDataSocket;
  final QuoteRepository quoteRepository;
  final AlertRepository alertRepository;
}
