// lib/services/web_cleanup_web.dart
library web_cleanup;

import 'web/web_interop_stub.dart' if (dart.library.html) 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';

void registerTabCloseCleanup(
  bool Function() isJoined, 
  String Function() getRoomId, 
  String Function() getSessionId,
) {
  // Sur le web, on écoute la fermeture pour détacher proprement le chasseur de la liste
  html.window.onBeforeUnload.listen((event) {
    if (isJoined() && getRoomId().isNotEmpty) {
      try {
        final roomId = getRoomId();
        final sessionId = getSessionId();
        
        // Suppression synchrone/urgente du chasseur de la liste des hunters
        // Note: On utilise une écriture directe bloquante si possible ou on laisse le TTL expirer.
        final docRef = FirebaseFirestore.instance.collection('current_raids').doc(roomId);
        
        // On retire le chasseur immédiatement de la liste active
        docRef.get().then((doc) {
          if (doc.exists) {
            final data = doc.data() ?? {};
            final List hunterList = data['hunters'] is Iterable ? List.from(data['hunters']) : [];
            hunterList.removeWhere((h) => h is Map && h['id'] == sessionId);
            
            if (hunterList.isEmpty) {
              docRef.delete();
              FirebaseFirestore.instance.collection('current_raid').doc(roomId).delete();
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