abstract final class AppConfig {
  static const wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'wss://webquotes.geeksoft.pl/websocket/quotes',
  );

  static const instrumentsAsset = 'assets/instruments.json';
}
