// lib/services/lan_socket_stub.dart

import 'dart:async';

Future<void> platformConnectSocket(
  String url,
  void Function(String text) onMessage,
  void Function() onDone,
  void Function(Object error) onError,
  void Function(void Function(String data) sender) onReady,
) async {
  throw UnsupportedError(
    'Transport WebSocket non supporte sur cette plateforme : $url',
  );
}

Future<void> platformCloseSocket() async {}
