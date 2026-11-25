// lib/services/lan_socket_web.dart

import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

web.WebSocket? _activeWebSocket;

Future<void> platformConnectSocket(
  String url,
  void Function(String text) onMessage,
  void Function() onDone,
  void Function(Object error) onError,
  void Function(void Function(String data) sender) onReady,
) async {
  await platformCloseSocket();

  final Completer<void> completer = Completer<void>();
  final web.WebSocket ws = web.WebSocket(url);
  _activeWebSocket = ws;

  ws.onOpen.first.then((_) {
    onReady((String data) {
      if (ws.readyState == web.WebSocket.OPEN) {
        ws.send(data.toJS);
      }
    });
    if (!completer.isCompleted) {
      completer.complete();
    }
  });

  ws.onError.first.then((_) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('Echec ouverture WebSocket Web : $url'),
      );
    }
  });

  ws.onMessage.listen((web.MessageEvent event) {
    final dynamic data = event.data.dartify();
    if (data is String) {
      onMessage(data);
    }
  });

  ws.onClose.listen((_) {
    onDone();
  });

  await completer.future.timeout(const Duration(seconds: 5));
}

Future<void> platformCloseSocket() async {
  try {
    _activeWebSocket?.close();
  } catch (_) {}
  _activeWebSocket = null;
}