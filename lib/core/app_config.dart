abstract final class AppConfig {
  static const wsUrl = String.fromEnvironment('WS_URL');

  static const instrumentsAsset = 'assets/instruments.json';

  static bool get useFakeFeed => wsUrl.isEmpty;
}
