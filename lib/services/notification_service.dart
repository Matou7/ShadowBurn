import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    
    await _notificationsPlugin.initialize(initializationSettings);
    
    // 1. Canal SERVICE
    const AndroidNotificationChannel serviceChannel = AndroidNotificationChannel(
      'foreground_service_channel', 
      'Système Actif', 
      description: 'Interface du Système',
      importance: Importance.low, 
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );

    // 2. Canal ALERTES
    const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
      'alert_channel',
      'Alertes Système',
      description: 'Notifications importantes',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlatform = 
        _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlatform != null) {
      await androidPlatform.createNotificationChannel(serviceChannel);
      await androidPlatform.createNotificationChannel(alertChannel);
    }
  }

  static Future<void> showNotification(String title, String body, {String? type}) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'alert_channel',
      'Alertes Système',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF9C27B0), 
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(type.hashCode, title, body, platformDetails);
  }

  // --- NOTIFICATION PERMANENTE (CORRIGÉE VISIBILITÉ) ---
  static Future<void> showForegroundServiceNotification(
      String title, 
      String body, 
      {
        required Color color, 
        required int progress,
        required int maxProgress
      }) async {
        
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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
      
      // CONFIGURATION COULEUR (Tentative de forçage Violet)
      color: const Color(0xFF9C27B0), 
      colorized: true, // Force le fond coloré sur certains Androids
      
      // CONFIGURATION TEXTE INTELLIGENTE
      // "subText" apparaît à côté du nom de l'app (parfait pour "SYSTEME")
      subText: "SYSTEME", 
      
      // CONFIGURATION BARRE
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      indeterminate: false,
    );

    final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    
    await _notificationsPlugin.show(9999, title, body, platformDetails);
  }
}