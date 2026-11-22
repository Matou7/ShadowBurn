// lib/services/lan_socket_io.dart

import 'dart:async';
import 'dart:io';

WebSocket? _activeIoSocket;
StreamSubscription<dynamic>? _activeIoSub;

Future<void> platformConnectSocket(
  String url,
  void Function(String text) onMessage,
  void Function() onDone,
  void Function(Object error) onError,
  void Function(void Function(String data) sender) onReady,
) async {
  await platformCloseSocket();

  final WebSocket socket =
      await WebSocket.connect(url).timeout(const Duration(seconds: 5));
  _activeIoSocket = socket;

  onReady((String data) {
    try {
      socket.add(data);
    } catch (_) {}
  });

  _activeIoSub = socket.listen(
    (dynamic event) {
      if (event is String) {
        onMessage(event);
      }
    },
    onDone: () {
      onDone();
    },
    onError: (Object err) {
      onError(err);
    },
  );
}

Future<void> platformCloseSocket() async {
  await _activeIoSub?.cancel();
  _activeIoSub = null;
  try {
    await _activeIoSocket?.close();
  } catch (_) {}
  _activeIoSocket = null;
}
