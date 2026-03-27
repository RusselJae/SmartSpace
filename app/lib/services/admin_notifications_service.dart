import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import '../models/support_conversation.dart';
import 'admin_auth_service.dart';
import 'mysql_database_service.dart';

class AdminNotificationItem {
  const AdminNotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.createdAt,
  });

  final String id;
  final String type; // 'support' | 'inventory' | 'system'
  final String title;
  final String subtitle;
  final DateTime createdAt;
}

class AdminNotificationSnapshot {
  const AdminNotificationSnapshot({
    required this.unreadSupportConversations,
    required this.unreadLowStockProducts,
    required this.lowStockProducts,
    required this.items,
    required this.lastUpdatedAt,
  });

  final int unreadSupportConversations;
  final int unreadLowStockProducts;
  final int lowStockProducts;
  final List<AdminNotificationItem> items;
  final DateTime lastUpdatedAt;

  /// Bell icon: inventory / system only (support uses the message icon in the header).
  int get bellBadgeCount => unreadLowStockProducts;

  int get totalBadgeCount => unreadSupportConversations + unreadLowStockProducts;

  static AdminNotificationSnapshot empty() => AdminNotificationSnapshot(
        unreadSupportConversations: 0,
        unreadLowStockProducts: 0,
        lowStockProducts: 0,
        items: const [],
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class AdminNotificationsService {
  AdminNotificationsService._internal();

  static final AdminNotificationsService instance = AdminNotificationsService._internal();

  static const int lowStockThreshold = 3;

  final ValueNotifier<AdminNotificationSnapshot> snapshot =
      ValueNotifier<AdminNotificationSnapshot>(AdminNotificationSnapshot.empty());

  Timer? _timer;
  bool _refreshing = false;

  void startPolling({Duration interval = const Duration(seconds: 15)}) {
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
      final auth = AdminAuthService();
      await auth.initialize();
      final adminId = auth.currentAdminId ?? auth.currentEmail;
      if (adminId == null || adminId.trim().isEmpty) {
        snapshot.value = AdminNotificationSnapshot.empty();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final db = MySQLDatabaseService();

      final results = await Future.wait([
        db.getSupportConversationsForAdmin(status: 'open'),
        db.getAllProducts(),
      ]);

      final conversations = results[0] as List<SupportConversation>;
      final products = results[1] as List<Product>;

      final unreadConvs = <SupportConversation>[];
      for (final conv in conversations) {
        // Be defensive: some records may not have `lastMessageAt`/`lastMessageSenderType`
        // populated yet. We still surface them as notification candidates so the
        // admin panel does not appear empty.
        final lastAt = conv.lastMessageAt ?? conv.updatedAt;
        final lastSender = (conv.lastMessageSenderType ?? '').toLowerCase();

        final lastReadAt = _getLastReadAt(prefs, adminId: adminId, conversationId: conv.id);
        // Treat sender-unknown conversations as unread to avoid silently hiding
        // support activity in the admin notifications panel.
        final fromUserOrUnknown = lastSender.isEmpty || lastSender == 'user';
        if (fromUserOrUnknown && (lastReadAt == null || lastAt.isAfter(lastReadAt))) {
          unreadConvs.add(conv);
        }
      }

      final lowStock = products
          .where((p) => p.inventoryQty > 0 && p.inventoryQty <= lowStockThreshold && !p.isArchived)
          .toList()
        ..sort((a, b) => a.inventoryQty.compareTo(b.inventoryQty));
      final seenLowStockIds = _getSeenLowStockIds(prefs, adminId: adminId);
      final unreadLowStockCount =
          lowStock.where((p) => !seenLowStockIds.contains(p.id)).length;

      // Support threads are surfaced only via the header message icon + Support tab — not here.
      final items = <AdminNotificationItem>[
        ...lowStock.map(
          (p) => AdminNotificationItem(
            id: 'inventory:${p.id}',
            type: 'inventory',
            title: 'Low stock',
            subtitle: '${p.name} • ${p.inventoryQty} left',
            createdAt: DateTime.now(),
          ),
        ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      snapshot.value = AdminNotificationSnapshot(
        unreadSupportConversations: unreadConvs.length,
        unreadLowStockProducts: unreadLowStockCount,
        lowStockProducts: lowStock.length,
        items: items,
        lastUpdatedAt: DateTime.now(),
      );
    } finally {
      _refreshing = false;
    }
  }

  Future<void> markConversationRead(String conversationId) async {
    final auth = AdminAuthService();
    await auth.initialize();
    final adminId = auth.currentAdminId ?? auth.currentEmail;
    if (adminId == null || adminId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastReadKey(adminId: adminId, conversationId: conversationId), DateTime.now().toIso8601String());
    await refresh();
  }

  Future<void> markAllSupportRead() async {
    final auth = AdminAuthService();
    await auth.initialize();
    final adminId = auth.currentAdminId ?? auth.currentEmail;
    if (adminId == null || adminId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final nowIso = DateTime.now().toIso8601String();
    final db = MySQLDatabaseService();
    await db.initialize();
    final convs = await db.getSupportConversationsForAdmin(status: 'open');
    for (final c in convs) {
      await prefs.setString(_lastReadKey(adminId: adminId, conversationId: c.id), nowIso);
    }
    await refresh();
  }

  /// Marks all current inventory notifications as seen so the bell badge clears.
  Future<void> markLowStockSeen() async {
    final auth = AdminAuthService();
    await auth.initialize();
    final adminId = auth.currentAdminId ?? auth.currentEmail;
    if (adminId == null || adminId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final inventoryIds = snapshot.value.items
        .where((i) => i.type == 'inventory')
        .map((i) => i.id.split(':').length == 2 ? i.id.split(':')[1] : '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    await prefs.setStringList(_seenLowStockKey(adminId: adminId), inventoryIds);
    await refresh();
  }

  static DateTime? _getLastReadAt(SharedPreferences prefs, {required String adminId, required String conversationId}) {
    final raw = prefs.getString(_lastReadKey(adminId: adminId, conversationId: conversationId));
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static String _lastReadKey({required String adminId, required String conversationId}) =>
      'smartspace.admin.support.lastReadAt.$adminId.$conversationId';

  static String _seenLowStockKey({required String adminId}) =>
      'smartspace.admin.inventory.seenLowStock.$adminId';

  static Set<String> _getSeenLowStockIds(SharedPreferences prefs, {required String adminId}) {
    final raw = prefs.getStringList(_seenLowStockKey(adminId: adminId)) ?? const <String>[];
    return raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  /// Same rules as [refresh] unread detection: show a dot when the last message is from the
  /// user (or unknown) and is newer than the admin’s last read time for this thread.
  static bool computeConversationUnread(
    SupportConversation conv,
    SharedPreferences prefs,
    String adminId,
  ) {
    final lastAt = conv.lastMessageAt ?? conv.updatedAt;
    final lastSender = (conv.lastMessageSenderType ?? '').toLowerCase();
    final lastReadAt = _getLastReadAt(prefs, adminId: adminId, conversationId: conv.id);
    final fromUserOrUnknown = lastSender.isEmpty || lastSender == 'user';
    return fromUserOrUnknown && (lastReadAt == null || lastAt.isAfter(lastReadAt));
  }
}

