import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'lan_socket_stub.dart'
    if (dart.library.html) 'lan_socket_web.dart'
    if (dart.library.io) 'lan_socket_io.dart';

abstract class LanSocketTransport {
  Stream<String> get incomingText;
  Future<void> connect();
  void sendText(String data);
  Future<void> close();
}

class _PlatformLanTransport implements LanSocketTransport {
  final String url;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  void Function(String data)? _sender;

  _PlatformLanTransport(this.url);

  @override
  Stream<String> get incomingText => _controller.stream;

  @override
  Future<void> connect() async {
    await platformConnectSocket(
      url,
      (String text) {
        if (!_controller.isClosed) {
          _controller.add(text);
        }
      },
      () {
        if (!_controller.isClosed) {
          _controller.close();
        }
      },
      (Object _) {
        if (!_controller.isClosed) {
          _controller.close();
        }
      },
      (void Function(String data) sender) {
        _sender = sender;
      },
    );
  }

  @override
  void sendText(String data) {
    final void Function(String data)? fn = _sender;
    if (fn != null) {
      fn(data);
    }
  }

  @override
  Future<void> close() async {
    _sender = null;
    await platformCloseSocket();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

LanSocketTransport createLanTransport(String url) => _PlatformLanTransport(url);

class LanSocketService {
  final StreamController<Map<String, dynamic>> _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _statusController =
      StreamController<bool>.broadcast();

  LanSocketTransport? _transport;
  StreamSubscription<String>? _rawSub;
  bool _isConnected = false;

  Stream<Map<String, dynamic>> get messages => _messagesController.stream;
  Stream<bool> get connectionChanges => _statusController.stream;
  bool get isConnected => _isConnected;

  Future<bool> connect(String wsUrl) async {
    await disconnect();
    try {
      final LanSocketTransport transport = createLanTransport(wsUrl);
      await transport.connect();
      _transport = transport;
      _isConnected = true;
      if (!_statusController.isClosed) {
        _statusController.add(true);
      }

      _rawSub = transport.incomingText.listen(
        (String raw) {
          try {
            final dynamic decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              if (!_messagesController.isClosed) {
                _messagesController.add(decoded);
              }
            } else if (decoded is Map) {
              if (!_messagesController.isClosed) {
                _messagesController.add(Map<String, dynamic>.from(decoded));
              }
            }
          } catch (e) {
            debugPrint('[LAN WS] JSON invalide recu : $e');
          }
        },
        onDone: () {
          _isConnected = false;
          if (!_statusController.isClosed) {
            _statusController.add(false);
          }
        },
        onError: (_) {
          _isConnected = false;
          if (!_statusController.isClosed) {
            _statusController.add(false);
          }
        },
      );
      return true;
    } catch (e) {
      debugPrint('[LAN WS] Erreur connexion ($wsUrl) : $e');
      _isConnected = false;
      if (!_statusController.isClosed) {
        _statusController.add(false);
      }
      return false;
    }
  }

  void sendJson(Map<String, dynamic> payload) {
    final LanSocketTransport? transport = _transport;
    if (transport == null || !_isConnected) return;
    try {
      transport.sendText(jsonEncode(payload));
    } catch (e) {
      debugPrint('[LAN WS] Erreur envoi : $e');
    }
  }

  Future<void> disconnect() async {
    await _rawSub?.cancel();
    _rawSub = null;
    final LanSocketTransport? transport = _transport;
    _transport = null;
    if (transport != null) {
      await transport.close();
    }
    if (_isConnected) {
      _isConnected = false;
      if (!_statusController.isClosed) {
        _statusController.add(false);
      }
    }
  }

  void dispose() {
    disconnect();
    if (!_messagesController.isClosed) {
      _messagesController.close();
    }
    if (!_statusController.isClosed) {
      _statusController.close();
    }
  }
}