import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/customer_notification.dart';
import 'auth_service.dart';
import 'mysql_database_service.dart';

class CustomerNotificationsService {
  CustomerNotificationsService._internal();

  static final CustomerNotificationsService instance = CustomerNotificationsService._internal();

  final ValueNotifier<List<CustomerNotification>> notifications =
      ValueNotifier<List<CustomerNotification>>(const []);

  Timer? _timer;
  bool _refreshing = false;

  int get unreadCount => notifications.value.where((n) => !n.isRead).length;

  void startPolling({Duration interval = const Duration(seconds: 20)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refresh());
    refresh();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final auth = AuthService();
      final user = auth.currentUser;
      if (user == null) {
        notifications.value = const [];
        return;
      }
      final db = MySQLDatabaseService();
      await db.initialize();
      final items = await db.getUserNotifications(user.id, limit: 60);
      notifications.value = items;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> markRead(String notificationId) async {
    final auth = AuthService();
    final user = auth.currentUser;
    if (user == null) return;
    final db = MySQLDatabaseService();
    await db.initialize();
    await db.markUserNotificationRead(user.id, notificationId: notificationId);
    await refresh();
  }

  Future<void> markAllRead() async {
    final auth = AuthService();
    final user = auth.currentUser;
    if (user == null) return;
    final db = MySQLDatabaseService();
    await db.initialize();
    await db.markUserNotificationRead(user.id);
    await refresh();
  }
}

