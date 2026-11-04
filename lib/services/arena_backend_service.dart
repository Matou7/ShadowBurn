import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Authenticated client for every privileged Arena and Pro operation.
/// Firestore writes are intentionally absent from this service.
class ArenaBackendService {
  ArenaBackendService._();

  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static Future<void> ensureAuthenticated() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return;
    await auth.signInAnonymously();
  }

  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    await ensureAuthenticated();
    final result = await _functions.httpsCallable(name).call(data);
    final value = result.data;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static Future<Map<String, String>> claimRoom({
    required String roomId,
    required int targetEndTimeMs,
  }) async {
    final result = await _call('claimArenaRoom', {
      'roomId': roomId,
      'targetEndTimeMs': targetEndTimeMs,
    });
    return {
      'roomId': result['roomId'].toString(),
      'adminKey': result['adminKey'].toString(),
      'joinToken': result['joinToken'].toString(),
      'instanceToken': result['instanceToken'].toString(),
    };
  }

  static Future<void> heartbeat({
    required String roomId,
    required String instanceToken,
  }) async {
    await _call('heartbeatArenaRoom', {
      'roomId': roomId,
      'instanceToken': instanceToken,
    });
  }

  static Future<void> closeRoom({
    required String roomId,
    required String instanceToken,
  }) async {
    await _call('closeArenaRoom', {
      'roomId': roomId,
      'instanceToken': instanceToken,
    });
  }

  static Future<void> setTvStatus({
    required String roomId,
    required String instanceToken,
    required String status,
  }) async {
    await _call('setArenaTvStatus', {
      'roomId': roomId,
      'instanceToken': instanceToken,
      'status': status,
    });
  }

  static Future<void> pruneHunters({
    required String roomId,
    required String instanceToken,
  }) async {
    await _call('pruneArenaHunters', {
      'roomId': roomId,
      'instanceToken': instanceToken,
    });
  }

  static Future<bool> validateJoinToken({
    required String roomId,
    required String token,
  }) async {
    final result = await _call('validateArenaJoinToken', {
      'roomId': roomId,
      'token': token,
    });
    return result['valid'] == true;
  }

  static Future<String> joinRoom({
    required String roomId,
    required String token,
    required String name,
    required String modeId,
    required String modeLabel,
  }) async {
    final result = await _call('joinArenaRoom', {
      'roomId': roomId,
      'token': token,
      'name': name,
      'modeId': modeId,
      'modeLabel': modeLabel,
    });
    return result['hunterId'].toString();
  }

  static Future<void> leaveRoom({required String roomId}) async {
    await _call('leaveArenaRoom', {'roomId': roomId});
  }

  static Future<void> submitDamage({
    required String roomId,
    required String batchId,
    required List<Map<String, dynamic>> strikes,
  }) async {
    await _call('submitArenaDamage', {
      'roomId': roomId,
      'batchId': batchId,
      'strikes': strikes,
    });
  }

  static Future<bool> verifyAdminKey({
    required String roomId,
    required String adminKey,
  }) async {
    final result = await _call('verifyArenaAdminKey', {
      'roomId': roomId,
      'adminKey': adminKey,
    });
    return result['valid'] == true;
  }

  static Future<void> adminAction({
    required String roomId,
    required String adminKey,
    required String action,
    int? damage,
    int? minutes,
    String? status,
    int? targetEndTimeMs,
  }) async {
    await _call('adminArenaAction', {
      'roomId': roomId,
      'adminKey': adminKey,
      'action': action,
      if (damage != null) 'damage': damage,
      if (minutes != null) 'minutes': minutes,
      if (status != null) 'status': status,
      if (targetEndTimeMs != null) 'targetEndTimeMs': targetEndTimeMs,
    });
  }

  static Future<String?> activateProLicense({
    required String key,
    required String deviceId,
  }) async {
    final result = await _call('activateProLicense', {
      'key': key,
      'deviceId': deviceId,
    });
    return result['key']?.toString();
  }

  static Future<String?> restoreProLicense({
    required String email,
    required String deviceId,
  }) async {
    final result = await _call('restoreProLicense', {
      'email': email,
      'deviceId': deviceId,
    });
    return result['key']?.toString();
  }

  static Future<bool> validateProLicense({
    required String key,
    required String deviceId,
  }) async {
    final result = await _call('validateProLicense', {
      'key': key,
      'deviceId': deviceId,
    });
    return result['valid'] == true;
  }
}
