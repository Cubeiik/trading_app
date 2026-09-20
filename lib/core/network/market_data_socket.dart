import 'dart:async';
import 'dart:convert';

import '../../features/quotes/domain/quote.dart';
import '../errors.dart';
import 'quote_parser.dart';
import 'websocket_transport.dart';

enum ConnectionStatus { disconnected, connecting, connected, reconnecting }

class MarketDataSocket {
  MarketDataSocket({required WebSocketTransport transport, required Uri uri})
    : _transport = transport,
      _uri = uri;

  static const _subscribePath = '/subscribe/addlist';
  static const _unsubscribePath = '/subscribe/removelist';
  static const _backoffSeconds = [1, 2, 4, 8, 16, 30];
  static const _stableConnectionThreshold = Duration(seconds: 10);

  final WebSocketTransport _transport;
  final Uri _uri;

  final _quotes = StreamController<Quote>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  final _subscribedSymbols = <String>{};

  StreamSubscription<dynamic>? _messagesSubscription;
  Timer? _reconnectTimer;
  Timer? _stabilityTimer;
  int _failedAttempts = 0;
  bool _isOpening = false;
  bool _isDisposed = false;
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;

  Stream<Quote> get quotes => _quotes.stream;

  Stream<ConnectionStatus> get status => _status.stream;

  ConnectionStatus get currentStatus => _currentStatus;

  Future<void> connect() async {
    if (_isDisposed || _currentStatus == ConnectionStatus.connected) {
      return;
    }
    await _open(ConnectionStatus.connecting);
  }

  void subscribe(Iterable<String> symbols) {
    final added = <String>[];
    for (final symbol in symbols) {
      if (_subscribedSymbols.add(symbol)) {
        added.add(symbol);
      }
    }

    if (added.isEmpty || _currentStatus != ConnectionStatus.connected) {
      return;
    }
    _send(_buildSubscriptionFrame(_subscribePath, added));
  }

  void unsubscribe(String symbol) {
    if (!_subscribedSymbols.remove(symbol)) {
      return;
    }
    if (_currentStatus != ConnectionStatus.connected) {
      return;
    }
    _send(_buildSubscriptionFrame(_unsubscribePath, [symbol]));
  }

  void reconnectNow() {
    if (_isDisposed) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _failedAttempts = 0;
    unawaited(_open(ConnectionStatus.reconnecting));
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _teardownConnection();
    _emitStatus(ConnectionStatus.disconnected);

    await _quotes.close();
    await _status.close();
  }

  Future<void> _open(ConnectionStatus pendingStatus) async {
    if (_isOpening) {
      return;
    }
    _isOpening = true;

    try {
      await _teardownConnection();
      _emitStatus(pendingStatus);

      await _transport.connect(_uri);
      if (_isDisposed) {
        await _transport.close();
        return;
      }

      _messagesSubscription = _transport.messages.listen(
        _onMessage,
        onError: _onTransportError,
        onDone: _onTransportClosed,
        cancelOnError: false,
      );

      _emitStatus(ConnectionStatus.connected);
      _stabilityTimer = Timer(
        _stableConnectionThreshold,
        () => _failedAttempts = 0,
      );
      _replaySubscriptions();
    } catch (error, stackTrace) {
      logError(error, stackTrace, 'MarketDataSocket.connect');
      _scheduleReconnect();
    } finally {
      _isOpening = false;
    }
  }

  Future<void> _teardownConnection() async {
    _stabilityTimer?.cancel();
    _stabilityTimer = null;

    await _messagesSubscription?.cancel();
    _messagesSubscription = null;

    try {
      await _transport.close();
    } catch (error, stackTrace) {
      logError(error, stackTrace, 'MarketDataSocket.close');
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed) {
      return;
    }

    _reconnectTimer?.cancel();
    _emitStatus(ConnectionStatus.reconnecting);

    final index = _failedAttempts.clamp(0, _backoffSeconds.length - 1);
    _failedAttempts++;

    _reconnectTimer = Timer(
      Duration(seconds: _backoffSeconds[index]),
      () => unawaited(_open(ConnectionStatus.reconnecting)),
    );
  }

  void _replaySubscriptions() {
    if (_subscribedSymbols.isEmpty) {
      return;
    }
    _send(_buildSubscriptionFrame(_subscribePath, _subscribedSymbols));
  }

  void _onMessage(dynamic message) {
    try {
      if (_quotes.isClosed) {
        return;
      }
      for (final quote in parseQuotes(message)) {
        _quotes.add(quote);
      }
    } catch (error, stackTrace) {
      logError(error, stackTrace, 'MarketDataSocket.onMessage');
    }
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    logError(error, stackTrace, 'MarketDataSocket.transport');
    _scheduleReconnect();
  }

  void _onTransportClosed() => _scheduleReconnect();

  void _send(String frame) {
    try {
      _transport.send(frame);
    } catch (error, stackTrace) {
      logError(error, stackTrace, 'MarketDataSocket.send');
    }
  }

  void _emitStatus(ConnectionStatus status) {
    if (_currentStatus == status) {
      return;
    }

    _currentStatus = status;
    if (!_status.isClosed) {
      _status.add(status);
    }
  }

  String _buildSubscriptionFrame(String path, Iterable<String> symbols) =>
      jsonEncode({'p': path, 'd': symbols.toList()});
}
