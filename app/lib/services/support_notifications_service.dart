import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'mysql_database_service.dart';

class SupportNotificationsService {
  SupportNotificationsService._internal();

  static final SupportNotificationsService instance = SupportNotificationsService._internal();

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  Timer? _timer;
  bool _refreshing = false;

  void startPolling({Duration interval = const Duration(seconds: 12)}) {
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
        unreadCount.value = 0;
        return;
      }

      final db = MySQLDatabaseService();
      await db.initialize();
      final conv = await db.getOrCreateSupportConversation(
        user.id,
        email: user.email,
      );
      final prefs = await SharedPreferences.getInstance();
      final lastReadAt = _getLastReadAt(prefs, userId: user.id, conversationId: conv.id);
      final lastAt = conv.lastMessageAt ?? conv.updatedAt;
      final lastSender = (conv.lastMessageSenderType ?? '').toLowerCase();
      final fromAdmin = lastSender == 'admin';
      unreadCount.value = (fromAdmin && (lastReadAt == null || lastAt.isAfter(lastReadAt))) ? 1 : 0;
    } catch (_) {
      // Keep previous unread value on transient failures.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> markConversationRead({
    required String userId,
    required String conversationId,
    DateTime? lastMessageAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = (lastMessageAt ?? DateTime.now()).toIso8601String();
    await prefs.setString(_lastReadKey(userId: userId, conversationId: conversationId), timestamp);
    await refresh();
  }

  static DateTime? _getLastReadAt(
    SharedPreferences prefs, {
    required String userId,
    required String conversationId,
  }) {
    final raw = prefs.getString(_lastReadKey(userId: userId, conversationId: conversationId));
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static String _lastReadKey({
    required String userId,
    required String conversationId,
  }) =>
      'smartspace.user.support.lastReadAt.$userId.$conversationId';
}

