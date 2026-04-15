import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_nav.dart';
import '../screens/profile/notifications_center_screen.dart';
import 'auth_service.dart';
import 'customer_notifications_service.dart';
import 'mysql_database_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background handler kept intentionally lightweight.
}

class PushNotificationsService {
  PushNotificationsService._internal();
  static final PushNotificationsService instance = PushNotificationsService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openAppSub;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) {
        appNavigatorKey.currentState?.push(
          CupertinoPageRoute(builder: (_) => const NotificationsCenterScreen()),
        );
      },
    );
    } catch (_) {}

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
      const AndroidNotificationChannel(
        'smartspace_general',
        'General Notifications',
        description: 'SmartSpace customer notifications',
        importance: Importance.high,
      ),
    );

    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      await registerTokenForCurrentUser();
    } catch (_) {}

    _tokenSub = _messaging.onTokenRefresh.listen((_) {
      registerTokenForCurrentUser();
    });

    _foregroundSub = FirebaseMessaging.onMessage.listen((message) async {
      await _showForegroundNotification(message);
      await CustomerNotificationsService.instance.refresh();
    });

    _openAppSub = FirebaseMessaging.onMessageOpenedApp.listen((_) {
      appNavigatorKey.currentState?.push(
        CupertinoPageRoute(builder: (_) => const NotificationsCenterScreen()),
      );
    });

    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        appNavigatorKey.currentState?.push(
          CupertinoPageRoute(builder: (_) => const NotificationsCenterScreen()),
        );
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _foregroundSub?.cancel();
    await _openAppSub?.cancel();
    _tokenSub = null;
    _foregroundSub = null;
    _openAppSub = null;
    _initialized = false;
  }

  Future<void> registerTokenForCurrentUser() async {
    final auth = AuthService();
    final user = auth.currentUser;
    if (user == null) return;
    final token = await _messaging.getToken();
    if (token == null || token.trim().isEmpty) return;
    final db = MySQLDatabaseService();
    await db.initialize();
    await db.registerUserDeviceToken(
      userId: user.id,
      token: token,
      platform: defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios',
    );
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? 'SmartSpace';
    final body = message.notification?.body ?? 'You have a new update.';
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'smartspace_general',
          'General Notifications',
          channelDescription: 'SmartSpace customer notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}

