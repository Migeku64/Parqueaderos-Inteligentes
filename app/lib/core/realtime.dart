import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Evento recibido por WebSocket: spots | movement | assignments | notification
class RtEvent {
  RtEvent(this.event, this.data);

  final String event;
  final Map<String, dynamic> data;
}

/// Conexión WebSocket con reconexión automática (sincronización en tiempo real).
class Realtime {
  final _controller = StreamController<RtEvent>.broadcast();
  WebSocket? _socket;
  Timer? _retry;
  String? _url;
  bool _closed = true;
  int _attempt = 0;

  Stream<RtEvent> get events => _controller.stream;
  bool get connected => _socket != null;

  void connect(String baseUrl, String token) {
    disconnect();
    final wsBase = baseUrl.replaceFirst(RegExp(r'^http'), 'ws').replaceAll(RegExp(r'/+$'), '');
    _url = '$wsBase/ws?token=${Uri.encodeQueryComponent(token)}';
    _closed = false;
    _attempt = 0;
    _open();
  }

  Future<void> _open() async {
    final url = _url;
    if (_closed || url == null) return;
    try {
      final socket = await WebSocket.connect(url).timeout(const Duration(seconds: 10));
      if (_closed) {
        await socket.close();
        return;
      }
      _socket = socket;
      _attempt = 0;
      socket.pingInterval = const Duration(seconds: 25);
      socket.listen(
        (msg) {
          try {
            final m = jsonDecode(msg as String);
            if (m is Map) {
              final data = m['data'];
              _controller.add(RtEvent(
                (m['event'] ?? '').toString(),
                data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
              ));
            }
          } catch (_) {}
        },
        onDone: _scheduleRetry,
        onError: (_) => _scheduleRetry(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _socket = null;
    if (_closed) return;
    _retry?.cancel();
    _attempt++;
    final seconds = _attempt > 6 ? 30 : 2 * _attempt;
    _retry = Timer(Duration(seconds: seconds), _open);
  }

  void disconnect() {
    _closed = true;
    _retry?.cancel();
    _socket?.close();
    _socket = null;
  }
}
