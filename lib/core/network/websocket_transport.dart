import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

abstract interface class WebSocketTransport {
  Future<void> connect(Uri uri);

  Stream<dynamic> get messages;

  void send(String data);

  Future<void> close();
}

class WebSocketChannelTransport implements WebSocketTransport {
  WebSocketChannel? _channel;

  @override
  Future<void> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;
  }

  @override
  Stream<dynamic> get messages =>
      _channel?.stream ?? const Stream<dynamic>.empty();

  @override
  void send(String data) => _channel?.sink.add(data);

  @override
  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    await channel?.sink.close(ws_status.normalClosure);
  }
}
