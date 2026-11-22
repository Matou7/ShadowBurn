// lib/services/lan_socket_web.dart

import 'dart:async';
import 'dart:html' as html;

html.WebSocket? _activeWebSocket;

Future<void> platformConnectSocket(
  String url,
  void Function(String text) onMessage,
  void Function() onDone,
  void Function(Object error) onError,
  void Function(void Function(String data) sender) onReady,
) async {
  await platformCloseSocket();

  final Completer<void> completer = Completer<void>();
  final html.WebSocket ws = html.WebSocket(url);
  _activeWebSocket = ws;

  ws.onOpen.first.then((_) {
    onReady((String data) {
      if (ws.readyState == html.WebSocket.OPEN) {
        ws.send(data);
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

  ws.onMessage.listen((html.MessageEvent event) {
    final dynamic data = event.data;
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
