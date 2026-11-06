library web_cleanup;

import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';

void registerTabCloseCleanup(bool Function() isJoined, String Function() getRoomId, String Function() getSessionId) {
  web.window.addEventListener(
    'beforeunload',
    (web.Event event) {
      if (isJoined() && getRoomId().isNotEmpty) {
        try {
          final roomId = getRoomId();
          final sessionId = getSessionId();
          FirebaseFirestore.instance.collection('current_raids').doc(roomId).get().then((doc) {
            if (doc.exists) {
              final data = doc.data() ?? {};
              final dynamic rawHunters = data['hunters'];
              final List hunterList = rawHunters is Iterable ? List.from(rawHunters) : [];
              hunterList.removeWhere((h) => h is Map && h['id'] == sessionId);
              
              if (hunterList.isEmpty) {
                FirebaseFirestore.instance.collection('current_raids').doc(roomId).delete();
                FirebaseFirestore.instance.collection('current_raid').doc(roomId).delete();
              } else {
                FirebaseFirestore.instance.collection('current_raids').doc(roomId).update({'hunters': hunterList});
                FirebaseFirestore.instance.collection('current_raid').doc(roomId).update({'hunters': hunterList});
              }
            }
          });
        } catch (_) {}
      }
    }.toJS,
  );
}