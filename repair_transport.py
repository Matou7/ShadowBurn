from pathlib import Path
import subprocess
import sys

LT = chr(60)
GT = chr(62)

PROJECT_DIR = Path(__file__).resolve().parent
SERVICES_DIR = PROJECT_DIR / "lib" / "services"

MAP_SD = f"Map{LT}String, dynamic{GT}"
STREAM_STR = f"Stream{LT}String{GT}"
STREAM_BOOL = f"Stream{LT}bool{GT}"
STREAM_MAP = f"Stream{LT}{MAP_SD}{GT}"
CTRL_STR = f"StreamController{LT}String{GT}"
CTRL_BOOL = f"StreamController{LT}bool{GT}"
CTRL_MAP = f"StreamController{LT}{MAP_SD}{GT}"
SUB_STR = f"StreamSubscription{LT}String{GT}?"
SUB_DYN = f"StreamSubscription{LT}dynamic{GT}?"
COMPLETER_VOID = f"Completer{LT}void{GT}"
FUTURE_VOID = f"Future{LT}void{GT}"
FUTURE_BOOL = f"Future{LT}bool{GT}"

STUB = f"""// lib/services/lan_socket_stub.dart

import 'dart:async';

{FUTURE_VOID} platformConnectSocket(
  String url,
  void Function(String text) onMessage,
  void Function() onDone,
  void Function(Object error) onError,
  void Function(void Function(String data) sender) onReady,
) async {{
  throw UnsupportedError(
    'Transport WebSocket non supporte sur cette plateforme : $url',
  );
}}

{FUTURE_VOID} platformCloseSocket() async {{}}
"""

WEB = f"""// lib/services/lan_socket_web.dart

import 'dart:async';
import 'dart:html' as html;

html.WebSocket? _activeWebSocket;

{FUTURE_VOID} platformConnectSocket(
  String url,
  void Function(String text) onMessage,
  void Function() onDone,
  void Function(Object error) onError,
  void Function(void Function(String data) sender) onReady,
) async {{
  await platformCloseSocket();

  final {COMPLETER_VOID} completer = {COMPLETER_VOID}();
  final html.WebSocket ws = html.WebSocket(url);
  _activeWebSocket = ws;

  ws.onOpen.first.then((_) {{
    onReady((String data) {{
      if (ws.readyState == html.WebSocket.OPEN) {{
        ws.send(data);
      }}
    }});
    if (!completer.isCompleted) {{
      completer.complete();
    }}
  }});

  ws.onError.first.then((_) {{
    if (!completer.isCompleted) {{
      completer.completeError(
        StateError('Echec ouverture WebSocket Web : $url'),
      );
    }}
  }});

  ws.onMessage.listen((html.MessageEvent event) {{
    final dynamic data = event.data;
    if (data is String) {{
      onMessage(data);
    }}
  }});

  ws.onClose.listen((_) {{
    onDone();
  }});

  await completer.future.timeout(const Duration(seconds: 5));
}}

{FUTURE_VOID} platformCloseSocket() async {{
  try {{
    _activeWebSocket?.close();
  }} catch (_) {{}}
  _activeWebSocket = null;
}}
"""

IO = f"""// lib/services/lan_socket_io.dart

import 'dart:async';
import 'dart:io';

WebSocket? _activeIoSocket;
{SUB_DYN} _activeIoSub;

{FUTURE_VOID} platformConnectSocket(
  String url,
  void Function(String text) onMessage,
  void Function() onDone,
  void Function(Object error) onError,
  void Function(void Function(String data) sender) onReady,
) async {{
  await platformCloseSocket();

  final WebSocket socket =
      await WebSocket.connect(url).timeout(const Duration(seconds: 5));
  _activeIoSocket = socket;

  onReady((String data) {{
    try {{
      socket.add(data);
    }} catch (_) {{}}
  }});

  _activeIoSub = socket.listen(
    (dynamic event) {{
      if (event is String) {{
        onMessage(event);
      }}
    }},
    onDone: () {{
      onDone();
    }},
    onError: (Object err) {{
      onError(err);
    }},
  );
}}

{FUTURE_VOID} platformCloseSocket() async {{
  await _activeIoSub?.cancel();
  _activeIoSub = null;
  try {{
    await _activeIoSocket?.close();
  }} catch (_) {{}}
  _activeIoSocket = null;
}}
"""

SERVICE = f"""// lib/services/lan_socket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'lan_socket_stub.dart'
    if (dart.library.html) 'lan_socket_web.dart'
    if (dart.library.io) 'lan_socket_io.dart';

abstract class LanSocketTransport {{
  {STREAM_STR} get incomingText;
  {FUTURE_VOID} connect();
  void sendText(String data);
  {FUTURE_VOID} close();
}}

class _PlatformLanTransport implements LanSocketTransport {{
  final String url;
  final {CTRL_STR} _controller = {CTRL_STR}.broadcast();
  void Function(String data)? _sender;

  _PlatformLanTransport(this.url);

  @override
  {STREAM_STR} get incomingText ={GT} _controller.stream;

  @override
  {FUTURE_VOID} connect() async {{
    await platformConnectSocket(
      url,
      (String text) {{
        if (!_controller.isClosed) {{
          _controller.add(text);
        }}
      }},
      () {{
        if (!_controller.isClosed) {{
          _controller.close();
        }}
      }},
      (Object _) {{
        if (!_controller.isClosed) {{
          _controller.close();
        }}
      }},
      (void Function(String data) sender) {{
        _sender = sender;
      }},
    );
  }}

  @override
  void sendText(String data) {{
    final void Function(String data)? fn = _sender;
    if (fn != null) {{
      fn(data);
    }}
  }}

  @override
  {FUTURE_VOID} close() async {{
    _sender = null;
    await platformCloseSocket();
    if (!_controller.isClosed) {{
      await _controller.close();
    }}
  }}
}}

LanSocketTransport createLanTransport(String url) ={GT} _PlatformLanTransport(url);

class LanSocketService {{
  final {CTRL_MAP} _messagesController = {CTRL_MAP}.broadcast();
  final {CTRL_BOOL} _statusController = {CTRL_BOOL}.broadcast();

  LanSocketTransport? _transport;
  {SUB_STR} _rawSub;
  bool _isConnected = false;

  {STREAM_MAP} get messages ={GT} _messagesController.stream;
  {STREAM_BOOL} get connectionChanges ={GT} _statusController.stream;
  bool get isConnected ={GT} _isConnected;

  {FUTURE_BOOL} connect(String wsUrl) async {{
    await disconnect();
    try {{
      final LanSocketTransport transport = createLanTransport(wsUrl);
      await transport.connect();
      _transport = transport;
      _isConnected = true;
      if (!_statusController.isClosed) {{
        _statusController.add(true);
      }}

      _rawSub = transport.incomingText.listen(
        (String raw) {{
          try {{
            final dynamic decoded = jsonDecode(raw);
            if (decoded is {MAP_SD}) {{
              if (!_messagesController.isClosed) {{
                _messagesController.add(decoded);
              }}
            }} else if (decoded is Map) {{
              if (!_messagesController.isClosed) {{
                _messagesController.add({MAP_SD}.from(decoded));
              }}
            }}
          }} catch (e) {{
            debugPrint('[LAN WS] JSON invalide recu : $e');
          }}
        }},
        onDone: () {{
          _isConnected = false;
          if (!_statusController.isClosed) {{
            _statusController.add(false);
          }}
        }},
        onError: (_) {{
          _isConnected = false;
          if (!_statusController.isClosed) {{
            _statusController.add(false);
          }}
        }},
      );
      return true;
    }} catch (e) {{
      debugPrint('[LAN WS] Erreur connexion ($wsUrl) : $e');
      _isConnected = false;
      if (!_statusController.isClosed) {{
        _statusController.add(false);
      }}
      return false;
    }}
  }}

  void sendJson({MAP_SD} payload) {{
    final LanSocketTransport? transport = _transport;
    if (transport == null || !_isConnected) return;
    try {{
      transport.sendText(jsonEncode(payload));
    }} catch (e) {{
      debugPrint('[LAN WS] Erreur envoi : $e');
    }}
  }}

  {FUTURE_VOID} disconnect() async {{
    await _rawSub?.cancel();
    _rawSub = null;
    final LanSocketTransport? transport = _transport;
    _transport = null;
    if (transport != null) {{
      await transport.close();
    }}
    if (_isConnected) {{
      _isConnected = false;
      if (!_statusController.isClosed) {{
        _statusController.add(false);
      }}
    }}
  }}

  void dispose() {{
    disconnect();
    if (!_messagesController.isClosed) {{
      _messagesController.close();
    }}
    if (!_statusController.isClosed) {{
      _statusController.close();
    }}
  }}
}}
"""


def main() -> int:
    SERVICES_DIR.mkdir(parents=True, exist_ok=True)
    for name, body in [
        ("lan_socket_stub.dart", STUB),
        ("lan_socket_web.dart", WEB),
        ("lan_socket_io.dart", IO),
        ("lan_socket_service.dart", SERVICE),
    ]:
        p = SERVICES_DIR / name
        p.write_text(body, encoding="utf-8", newline="\n")
        print(f"[OK] {p}")

    return subprocess.run(
        ["flutter", "run", "--release"], cwd=PROJECT_DIR, shell=True
    ).returncode


if __name__ == "__main__":
    sys.exit(main())