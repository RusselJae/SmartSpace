import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory_material.dart';
import '../models/order_record.dart';
import '../models/support_conversation.dart';
import '../models/made_to_order_request.dart';
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
    required this.unreadCancelledOrders,
    required this.unreadLowStockProducts,
    required this.unreadMadeToOrderRequests,
    required this.cancelledOrders,
    required this.lowStockProducts,
    required this.items,
    required this.lastUpdatedAt,
  });

  final int unreadSupportConversations;
  final int unreadCancelledOrders;
  final int unreadLowStockProducts;
  final int unreadMadeToOrderRequests;
  final int cancelledOrders;
  final int lowStockProducts;
  final List<AdminNotificationItem> items;
  final DateTime lastUpdatedAt;

  /// Bell icon: inventory / system only (support uses the message icon in the header).
  int get bellBadgeCount =>
      unreadLowStockProducts + unreadCancelledOrders + unreadMadeToOrderRequests;

  int get totalBadgeCount =>
      unreadSupportConversations +
      unreadLowStockProducts +
      unreadCancelledOrders +
      unreadMadeToOrderRequests;

  static AdminNotificationSnapshot empty() => AdminNotificationSnapshot(
    unreadSupportConversations: 0,
    unreadCancelledOrders: 0,
    unreadLowStockProducts: 0,
    unreadMadeToOrderRequests: 0,
    cancelledOrders: 0,
    lowStockProducts: 0,
    items: const [],
    lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class AdminNotificationsService {
  AdminNotificationsService._internal();

  static final AdminNotificationsService instance =
      AdminNotificationsService._internal();

  final ValueNotifier<AdminNotificationSnapshot> snapshot =
      ValueNotifier<AdminNotificationSnapshot>(
        AdminNotificationSnapshot.empty(),
      );

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
        db.getInventoryMaterials(),
        db.getAllOrders(),
        db.getMadeToOrderRequests(),
      ]);

      final conversations = results[0] as List<SupportConversation>;
      final materials = results[1] as List<InventoryMaterial>;
      final orders = results[2] as List<OrderRecord>;
      final madeToOrderRequests = results[3] as List<MadeToOrderRequest>;

      final unreadConvs = <SupportConversation>[];
      for (final conv in conversations) {
        // Be defensive: some records may not have `lastMessageAt`/`lastMessageSenderType`
        // populated yet. We still surface them as notification candidates so the
        // admin panel does not appear empty.
        final lastAt = conv.lastMessageAt ?? conv.updatedAt;
        final lastSender = (conv.lastMessageSenderType ?? '').toLowerCase();

        final lastReadAt = _getLastReadAt(
          prefs,
          adminId: adminId,
          conversationId: conv.id,
        );
        // Treat sender-unknown conversations as unread to avoid silently hiding
        // support activity in the admin notifications panel.
        final fromUserOrUnknown = lastSender.isEmpty || lastSender == 'user';
        if (fromUserOrUnknown &&
            (lastReadAt == null || lastAt.isAfter(lastReadAt))) {
          unreadConvs.add(conv);
        }
      }

      final lowStock = materials
          .where((m) => m.isLowStock || m.isOutOfStock)
          .toList()
        ..sort((a, b) => a.quantityOnHand.compareTo(b.quantityOnHand));
      final seenLowStockIds = _getSeenLowStockIds(prefs, adminId: adminId);
      final unreadLowStock = lowStock
          .where((m) => !seenLowStockIds.contains(m.id))
          .toList(growable: false);
      final unreadLowStockCount = unreadLowStock.length;
      final cancelledOrders =
          orders.where((o) => o.status.toLowerCase() == 'cancelled').toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final seenCancelledOrderIds = _getSeenCancelledOrderIds(
        prefs,
        adminId: adminId,
      );
      final unreadCancelled = cancelledOrders
          .where((o) => !seenCancelledOrderIds.contains(o.id))
          .toList(growable: false);
      final unreadCancelledOrders = unreadCancelled.length;

      final pendingMto = madeToOrderRequests
          .where((r) => r.status == 'pending_review')
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final seenMtoIds = _getSeenMadeToOrderRequestIds(prefs, adminId: adminId);
      final unreadMto = pendingMto
          .where((r) => !seenMtoIds.contains(r.id))
          .toList(growable: false);
      final unreadMadeToOrderRequests = unreadMto.length;

      final items = <AdminNotificationItem>[
        ...unreadConvs.map(
          (c) => AdminNotificationItem(
            id: 'support:${c.id}',
            type: 'support',
            title: 'New customer message',
            subtitle: c.lastMessagePreview ?? 'Customer sent a support message',
            createdAt: c.lastMessageAt ?? c.updatedAt,
          ),
        ),
        ...unreadCancelled
            .take(20)
            .map(
              (o) => AdminNotificationItem(
                id: 'order_cancelled:${o.id}',
                type: 'system',
                title: 'Order cancelled',
                subtitle:
                    '#${o.id.length >= 8 ? o.id.substring(0, 8) : o.id} • ${o.userName.isEmpty ? 'Guest' : o.userName}',
                createdAt: o.updatedAt,
              ),
            ),
        ...unreadLowStock.map(
          (m) => AdminNotificationItem(
            id: 'inventory:${m.id}',
            type: 'inventory',
            title: m.isOutOfStock ? 'Material out of stock' : 'Low material stock',
            subtitle: '${m.name} • ${m.quantityOnHand} ${m.unit} on hand',
            createdAt: DateTime.now(),
          ),
        ),
        ...unreadMto
            .take(20)
            .map(
              (r) => AdminNotificationItem(
                id: 'made_to_order:${r.id}',
                type: 'system',
                title: 'New made-to-order request',
                subtitle: '${r.userName.isEmpty ? 'Customer' : r.userName} • ${r.itemName}',
                createdAt: r.createdAt,
              ),
            ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      snapshot.value = AdminNotificationSnapshot(
        unreadSupportConversations: unreadConvs.length,
        unreadCancelledOrders: unreadCancelledOrders,
        unreadLowStockProducts: unreadLowStockCount,
        unreadMadeToOrderRequests: unreadMadeToOrderRequests,
        cancelledOrders: cancelledOrders.length,
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
    final db = MySQLDatabaseService();
    await db.initialize();
    final convs = await db.getSupportConversationsForAdmin(status: 'open');
    SupportConversation? conv;
    for (final c in convs) {
      if (c.id == conversationId) {
        conv = c;
        break;
      }
    }
    final timestamp = (conv?.lastMessageAt ?? conv?.updatedAt ?? DateTime.now())
        .toIso8601String();
    await prefs.setString(
      _lastReadKey(adminId: adminId, conversationId: conversationId),
      timestamp,
    );
    await refresh();
  }

  Future<void> markAllSupportRead() async {
    final auth = AdminAuthService();
    await auth.initialize();
    final adminId = auth.currentAdminId ?? auth.currentEmail;
    if (adminId == null || adminId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final db = MySQLDatabaseService();
    await db.initialize();
    final convs = await db.getSupportConversationsForAdmin(status: 'open');
    for (final c in convs) {
      final timestamp = (c.lastMessageAt ?? c.updatedAt).toIso8601String();
      await prefs.setString(
        _lastReadKey(adminId: adminId, conversationId: c.id),
        timestamp,
      );
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
    // IMPORTANT:
    // Use the live product list instead of `snapshot.items` so the badge clears
    // even when the UI only renders a subset of notifications.
    final db = MySQLDatabaseService();
    await db.initialize();
    final materials = await db.getInventoryMaterials();
    final inventoryIds = materials
        .where((m) => m.isLowStock || m.isOutOfStock)
        .map((m) => m.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    await prefs.setStringList(_seenLowStockKey(adminId: adminId), inventoryIds);
    await refresh();
  }

  Future<void> markMadeToOrderRequestsSeen() async {
    final auth = AdminAuthService();
    await auth.initialize();
    final adminId = auth.currentAdminId ?? auth.currentEmail;
    if (adminId == null || adminId.trim().isEmpty) return;

    final db = MySQLDatabaseService();
    await db.initialize();
    final requests = await db.getMadeToOrderRequests();
    final pendingIds = requests
        .where((r) => r.status == 'pending_review')
        .map((r) => r.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _seenMadeToOrderRequestsKey(adminId: adminId),
      pendingIds,
    );
    await refresh();
  }

  Future<void> markCancelledOrdersSeen() async {
    final auth = AdminAuthService();
    await auth.initialize();
    final adminId = auth.currentAdminId ?? auth.currentEmail;
    if (adminId == null || adminId.trim().isEmpty) return;
    // IMPORTANT:
    // The snapshot only includes a capped list of items; marking "seen" from that
    // can leave old cancelled orders unseen and keep the red badge stuck on.
    final db = MySQLDatabaseService();
    await db.initialize();
    final orders = await db.getAllOrders();
    final cancelledIds = orders
        .where((o) => o.status.toLowerCase() == 'cancelled')
        .map((o) => o.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _seenCancelledOrdersKey(adminId: adminId),
      cancelledIds,
    );
    await refresh();
  }

  /// Clears all currently visible notifications for this admin.
  /// This is intentionally implemented as a "mark as seen/read" action so that
  /// new events still appear automatically on the next refresh cycle.
  Future<void> clearAllNotifications() async {
    await markAllSupportRead();
    await markLowStockSeen();
    await markCancelledOrdersSeen();
    await markMadeToOrderRequestsSeen();
  }

  static DateTime? _getLastReadAt(
    SharedPreferences prefs, {
    required String adminId,
    required String conversationId,
  }) {
    final raw = prefs.getString(
      _lastReadKey(adminId: adminId, conversationId: conversationId),
    );
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static String _lastReadKey({
    required String adminId,
    required String conversationId,
  }) => 'smartspace.admin.support.lastReadAt.$adminId.$conversationId';

  static String _seenLowStockKey({required String adminId}) =>
      'smartspace.admin.inventory.seenLowStock.$adminId';
  static String _seenCancelledOrdersKey({required String adminId}) =>
      'smartspace.admin.orders.seenCancelled.$adminId';
  static String _seenMadeToOrderRequestsKey({required String adminId}) =>
      'smartspace.admin.mto.seenPending.$adminId';

  static Set<String> _getSeenLowStockIds(
    SharedPreferences prefs, {
    required String adminId,
  }) {
    final raw =
        prefs.getStringList(_seenLowStockKey(adminId: adminId)) ??
        const <String>[];
    return raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  static Set<String> _getSeenCancelledOrderIds(
    SharedPreferences prefs, {
    required String adminId,
  }) {
    final raw =
        prefs.getStringList(_seenCancelledOrdersKey(adminId: adminId)) ??
        const <String>[];
    return raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  static Set<String> _getSeenMadeToOrderRequestIds(
    SharedPreferences prefs, {
    required String adminId,
  }) {
    final raw =
        prefs.getStringList(_seenMadeToOrderRequestsKey(adminId: adminId)) ??
        const <String>[];
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
    final lastReadAt = _getLastReadAt(
      prefs,
      adminId: adminId,
      conversationId: conv.id,
    );
    final fromUserOrUnknown = lastSender.isEmpty || lastSender == 'user';
    return fromUserOrUnknown &&
        (lastReadAt == null || lastAt.isAfter(lastReadAt));
  }
}
