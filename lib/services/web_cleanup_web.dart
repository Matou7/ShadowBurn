// lib/services/web_cleanup_web.dart
library web_cleanup;

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';

void registerTabCloseCleanup(
  bool Function() isJoined,
  String Function() getRoomId,
  String Function() getSessionId,
) {
  html.window.onBeforeUnload.listen((event) {
    if (isJoined() && getRoomId().isNotEmpty) {
      try {
        final roomId = getRoomId();
        final sessionId = getSessionId();

        final docRef = FirebaseFirestore.instance.collection('current_raids').doc(roomId);

        docRef.get().then((doc) {
          if (doc.exists) {
            final data = doc.data() ?? {};
            final List hunterList = data['hunters'] is Iterable ? List.from(data['hunters']) : [];
            hunterList.removeWhere((h) => h is Map && h['id'] == sessionId);

            if (hunterList.isEmpty) {
              docRef.delete();
            } else {
              docRef.update({
                'hunters': hunterList,
                'arena_last_seen': FieldValue.serverTimestamp(),
              });
            }
          }
        });
      } catch (_) {}
    }
  });
}