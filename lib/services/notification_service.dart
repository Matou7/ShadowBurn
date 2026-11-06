// lib/services/notification_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/log.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const int _serviceId = 9999;
  static const int _antiFlemmeId = 9001;

  static bool _isInitialized = false;

  static int _lastProgress = -1;
  static String _lastBody = '';
  static DateTime _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      await _plugin.initialize(const InitializationSettings(android: androidSettings));

      const AndroidNotificationChannel serviceChannel = AndroidNotificationChannel(
        'foreground_service_channel',
        'Système Actif',
        description: 'Suivi permanent du Chasseur',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );

      final AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
        'alert_channel',
        'Alertes Système',
        description: 'Notifications importantes',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1500, 800, 1500]),
      );

      final AndroidNotificationChannel flemmeChannel = AndroidNotificationChannel(
        'antiflemme_channel',
        'Rappels de Discipline',
        description: 'Piques tactiques contre la procrastination',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      );

      final android = _android;
      if (android != null) {
        await android.createNotificationChannel(serviceChannel);
        await android.createNotificationChannel(alertChannel);
        await android.createNotificationChannel(flemmeChannel);
        await android.requestNotificationsPermission();
      }

      _isInitialized = true;
    } catch (e) {
      dlog("Erreur initialisation NotificationService : $e");
    }
  }

  /// Vérifie si le joueur est actuellement sous immunité de Zone Blanche
  static Future<bool> _isWhiteZoneActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool introCompleted = prefs.getBool('has_completed_intro') ?? false;
      if (!introCompleted) return true;

      final String? rawSave = prefs.getString('save_v3');
      if (rawSave == null || rawSave.isEmpty) return true;

      final dynamic decoded = jsonDecode(rawSave);
      if (decoded is! Map<String, dynamic>) return true;

      final now = DateTime.now();
      final String todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final dynamic calendar = decoded['calendar'];

      if (calendar is Map && calendar[todayStr] is Map) {
        return calendar[todayStr]['status'] == 'white_zone';
      }
    } catch (_) {}
    return false;
  }

  static Future<void> showNotification(
    String title,
    String body, {
    String? type,
    bool isUrgent = false,
  }) async {
    if (!_isInitialized) return;

    // SILENCE CIBLÉ : Ne bloque QUE les notifications de type "penalty" (quêtes incomplètes) en zone blanche.
    // Laisse passer les victoires, les validations de cycle et les level-up.
    final bool isWhiteZone = await _isWhiteZoneActive();
    if (isWhiteZone && (type == 'penalty' || title.contains("incomplète") || body.contains("incomplète"))) {
      dlog("Pénalité annulée (Zone Blanche) : $title");
      return;
    }

    try {
      final bool isCritical = type == 'dungeon' || type == 'penalty';

      final AndroidNotificationDetails details = AndroidNotificationDetails(
        'alert_channel',
        'Alertes Système',
        importance: Importance.max,
        priority: Priority.high,
        color: isCritical ? const Color(0xFFFF0044) : const Color(0xFF00E5FF),
        fullScreenIntent: isCritical,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        ticker: 'Alerte Chasseur',
      );
      final int id = (type ?? 'default').hashCode & 0x3fffffff;
      await _plugin.show(id, title, body, NotificationDetails(android: details));
    } catch (e) {
      dlog("Erreur notification : $e");
    }
  }

  static Future<void> showAntiFlemmeAlert(String title, String body) async {
    if (!_isInitialized) return;

    // Les rappels anti-flemme sont de retour, même le premier jour !
    try {
      const AndroidNotificationDetails details = AndroidNotificationDetails(
        'antiflemme_channel',
        'Rappels de Discipline',
        importance: Importance.high,
        priority: Priority.high,
        color: Color(0xFFE53935),
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
      );
      await _plugin.show(_antiFlemmeId, title, body, const NotificationDetails(android: details));
    } catch (e) {
      dlog("Erreur alerte anti-flemme : $e");
    }
  }

  static Future<void> updateTrackingNotification(
    String title,
    String body, {
    required Color color,
    required int progress,
    int maxProgress = 100,
  }) async {
    if (!_isInitialized) return;

    final DateTime now = DateTime.now();

    if (_lastProgress == progress && _lastBody == body) {
      return;
    }

    if (now.difference(_lastUpdateTime).inMilliseconds < 1000) {
      return;
    }

    _lastProgress = progress;
    _lastBody = body;
    _lastUpdateTime = now;

    final AndroidNotificationDetails details = AndroidNotificationDetails(
      'foreground_service_channel',
      'Système Actif',
      channelDescription: 'Suivi permanent du Chasseur',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: false,
      category: AndroidNotificationCategory.service,
      color: color,
      colorized: true,
      subText: "SYSTÈME",
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      indeterminate: false,
    );

    try {
      await _plugin.show(
        _serviceId,
        title,
        body,
        NotificationDetails(android: details),
      );
    } catch (e) {
      dlog("Erreur notification permanente : $e");
    }
  }

  static Future<void> stopTrackingService() async {
    try {
      await _plugin.cancel(_serviceId);
    } catch (e) {
      dlog("Arrêt de la notification permanente impossible : $e");
    }
  }
}