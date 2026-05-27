import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:firebase_core/firebase_core.dart';

import '../app_nav.dart';
import '../screens/profile/notifications_center_screen.dart';
import 'auth_service.dart';
import 'customer_notifications_service.dart';
import 'mysql_database_service.dart';
import '../utils/env_loader.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // IMPORTANT:
  // - This runs in a background isolate on Android.
  // - FCM "notification" payloads may be shown by the OS automatically, but
  //   "data-only" pushes will NOT render anything unless we show a local notification.
  // - We also need Firebase initialized here before touching messaging data on some devices.
  try {
    // In case the app process was cold-started by the push, ensure env + Firebase exist.
    // (EnvLoader is resilient to missing .env and will no-op on failure.)
    await EnvLoader.load();
  } catch (_) {}

  try {
    if (Firebase.apps.isEmpty) {
      final apiKey = EnvLoader.get('FIREBASE_API_KEY');
      final appId = EnvLoader.get('FIREBASE_APP_ID');
      final messagingSenderId = EnvLoader.get('FIREBASE_MESSAGING_SENDER_ID');
      final projectId = EnvLoader.get('FIREBASE_PROJECT_ID');
      final storageBucket = EnvLoader.get('FIREBASE_STORAGE_BUCKET');

      // Only initialize when env is present; otherwise we still attempt to show a local notification below.
      if (apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
            storageBucket:
                storageBucket.isNotEmpty ? storageBucket : '$projectId.appspot.com',
          ),
        );
      }
    }
  } catch (_) {}

  // For background/killed state, show a local notification so the user still gets
  // a system notification even when the push is data-only.
  try {
    final local = FlutterLocalNotificationsPlugin();
    await local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // Ensure channel exists before showing.
    await local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
      const AndroidNotificationChannel(
        'smartspace_general',
        'General Notifications',
        description: 'SmartSpace customer notifications',
        importance: Importance.high,
      ),
    );

    final title = message.notification?.title ??
        (message.data['title']?.toString().trim().isNotEmpty == true
            ? message.data['title'].toString()
            : 'SmartSpace');
    final body = message.notification?.body ??
        (message.data['body']?.toString().trim().isNotEmpty == true
            ? message.data['body'].toString()
            : 'You have a new update.');

    await local.show(
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
  } catch (_) {}
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
      // Android 13+ requires POST_NOTIFICATIONS at runtime.
      // FirebaseMessaging.requestPermission() is mainly iOS-focused; we explicitly ask via
      // flutter_local_notifications on Android so system notifications can appear.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
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

