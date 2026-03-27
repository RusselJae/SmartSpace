import 'package:flutter/material.dart';

import 'admin_theme.dart';
import 'pages/admin_dashboard_page.dart';
import 'pages/admins_admin_page.dart';
import 'pages/admin_profile_page.dart';
import 'pages/orders_admin_page.dart';
import 'pages/products_admin_page.dart';
import 'pages/reviews_admin_page.dart';
import 'pages/faqs_admin_page.dart';
import 'pages/legal_content_admin_page.dart';
import 'pages/settings_admin_page.dart';
import 'pages/support_inbox_admin_page.dart';
import 'pages/users_admin_page.dart';
import '../../services/admin_auth_service.dart';
import '../../services/admin_notifications_service.dart';
import '../../widgets/loading_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  static const String route = '/admin';

  @override
  State<AdminShell> createState() => _AdminShellState();
}

typedef _AdminViewBuilder = Widget Function(VoidCallback goToReviews, VoidCallback goToOrders);

class _AdminDestination {
  const _AdminDestination({required this.label, required this.icon, required this.builder});

  final String label;
  final IconData icon;
  final _AdminViewBuilder builder;
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  bool _authChecked = false;
  final AdminNotificationsService _notifications = AdminNotificationsService.instance;
  final GlobalKey _notificationsAnchorKey = GlobalKey();

  Future<void> _openSupportInboxFromHeader() async {
    await _notifications.markAllSupportRead();
    if (!mounted) return;
    _selectTab(6);
  }

  Future<void> _openNotificationsFromHeader(BuildContext context) async {
    await _notifications.markLowStockSeen();
    if (!mounted) return;
    _showNotificationsFloatingPanel(context);
  }

  void _showNotificationsFloatingPanel(BuildContext context) {
    final box = _notificationsAnchorKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.sizeOf(context);
    const double panelWidth = 360;
    const double panelHeight = 420;
    const double padding = 12;

    double left = screenSize.width - panelWidth - padding;
    double top = 72;

    if (box != null && box.hasSize) {
      final pos = box.localToGlobal(Offset.zero);
      final size = box.size;
      left = pos.dx + size.width / 2 - panelWidth / 2;
      if (left < padding) left = padding;
      if (left + panelWidth > screenSize.width - padding) {
        left = screenSize.width - panelWidth - padding;
      }
      top = pos.dy + size.height + 8;
    }
    if (top + panelHeight > screenSize.height - padding) {
      top = screenSize.height - panelHeight - padding;
    }
    if (top < 16) top = 16;

    // Use a standard dialog shell with explicit outside-tap dismiss handling.
    // This avoids edge cases where general dialog barriers can immediately consume
    // the same pointer event used to open the panel on web.
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.14),
      builder: (ctx) => SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(ctx).pop(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 28,
                shadowColor: Colors.black.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: panelWidth,
                    height: panelHeight,
                    child: _InlineNotificationsPanel(
                      service: _notifications,
                      onClose: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows profile as a centered modal matching the admin content container size.
  void _showProfileModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Modal header with back/close
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(ctx).pop(),
                        tooltip: 'Close',
                      ),
                      Expanded(
                        child: Text(
                          AdminProfilePage.title,
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: const AdminProfilePage(embedded: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  late final List<_AdminDestination> _destinations = [
    _AdminDestination(
      label: 'Overview',
      icon: Icons.auto_graph_outlined,
      builder: (goToReviews, goToOrders) => AdminDashboardPage(
        onOpenReviews: goToReviews,
        onOpenOrders: goToOrders,
      ),
    ),
    _AdminDestination(
      label: 'Products',
      icon: Icons.chair_alt_outlined,
      builder: (_, __) => const ProductsAdminPage(),
    ),
    _AdminDestination(
      label: 'Orders',
      icon: Icons.shopping_bag_outlined,
      builder: (_, __) => const OrdersAdminPage(),
    ),
    _AdminDestination(
      label: 'Reviews',
      icon: Icons.reviews_outlined,
      builder: (_, __) => const ReviewsAdminPage(),
    ),
    _AdminDestination(
      label: 'Users',
      icon: Icons.group_outlined,
      builder: (_, __) => const UsersAdminPage(),
    ),
    _AdminDestination(
      label: 'Admins',
      icon: Icons.admin_panel_settings_outlined,
      builder: (_, __) => const AdminsAdminPage(),
    ),
    _AdminDestination(
      label: 'Support',
      icon: Icons.support_agent_outlined,
      builder: (_, __) => const SupportInboxAdminPage(),
    ),
    _AdminDestination(
      label: 'FAQs',
      icon: Icons.help_outline,
      builder: (_, __) => const FaqsAdminPage(),
    ),
    _AdminDestination(
      label: 'Legal',
      icon: Icons.description_outlined,
      builder: (_, __) => const LegalContentAdminPage(),
    ),
    _AdminDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      builder: (_, __) => const SettingsAdminPage(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _verifyAdminSession();
  }

  Future<void> _verifyAdminSession() async {
    final adminAuth = AdminAuthService();
    await adminAuth.initialize();
    if (!mounted) return;
    if (!adminAuth.isAuthenticated) {
      // No active admin session – send the user back to the admin login screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/admin/login');
      });
    } else {
      setState(() {
        _authChecked = true;
      });
      _notifications.startPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_authChecked) {
      return Theme(
        data: buildAdminTheme(),
        child: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final bool wide = MediaQuery.of(context).size.width >= 1100;
    final Widget currentPage = _destinations[_index].builder(
      () => _selectTab(3), // Go to Reviews
      () => _selectTab(2), // Go to Orders
    );

    return Theme(
      data: buildAdminTheme(),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFE7EBF0),
        ),
        child: wide ? _buildWideLayout(currentPage) : _buildCompactLayout(currentPage),
      ),
    );
  }

  Widget _buildWideLayout(Widget page) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Row(
          children: [
            _SideRail(
              destinations: _destinations,
              selectedIndex: _index,
              onSelect: _selectTab,
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AdminPalette.surface, AdminPalette.sand],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    _AdminHeader(
                      title: _destinations[_index].label,
                      notifications: _notifications,
                      onOpenSupport: _openSupportInboxFromHeader,
                      onOpenSettings: () => _selectTab(9),
                      onOpenProfile: () => _showProfileModal(context),
                      onOpenNotifications: () => _openNotificationsFromHeader(context),
                      notificationsAnchorKey: _notificationsAnchorKey,
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _AdminContentWrapper(key: ValueKey(_index), child: page),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLayout(Widget page) {
    return Scaffold(
      backgroundColor: AdminPalette.sand,
      body: SafeArea(
        child: Column(
          children: [
            _AdminHeader(
              title: _destinations[_index].label,
              notifications: _notifications,
              onOpenSupport: _openSupportInboxFromHeader,
              onOpenSettings: () => _selectTab(9),
              onOpenProfile: () => _showProfileModal(context),
              onOpenNotifications: () => _openNotificationsFromHeader(context),
              notificationsAnchorKey: _notificationsAnchorKey,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _AdminContentWrapper(key: ValueKey(_index), child: page),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: _destinations
            .map(
              (dest) => NavigationDestination(
                icon: Icon(dest.icon),
                label: dest.label,
              ),
            )
            .toList(),
      ),
    );
  }

  void _selectTab(int value) {
    setState(() => _index = value);
  }
}

class _SideRailEntry {
  _SideRailEntry(this.destination, this.index);

  final _AdminDestination destination;
  final int index;
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_AdminDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    // The Support destination is accessed via the header message icon, not the left rail.
    final entries = <_SideRailEntry>[
      for (var i = 0; i < destinations.length; i++)
        if (destinations[i].label != 'Support')
          _SideRailEntry(destinations[i], i),
    ];

    return Container(
      width: 260,
      margin: const EdgeInsets.fromLTRB(16, 12, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Row(
              children: [
                // Logo image
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.view_in_ar_rounded, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Wood Home Furniture Trading',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Admin console',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final bool active = selectedIndex == entry.index;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF111827) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onSelect(entry.index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              entry.destination.icon,
                              color: active ? Colors.white : Colors.grey[800],
                            ),
                            const SizedBox(width: 12),
                            Text(
                              entry.destination.label,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: active ? Colors.white : Colors.grey[800],
                                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Logout button at the bottom with same design as other navigation buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () async {
                  await AdminAuthService().signOut();
                  if (!context.mounted) return;
                  // Show loading screen before navigating to login
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const LoadingScreen(
                        message: 'Signing out...',
                        nextRoute: '/admin/login',
                      ),
                    ),
                    (route) => false,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.logout,
                        color: Colors.grey[800],
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Logout',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminHeader extends StatefulWidget {
  const _AdminHeader({
    required this.title,
    required this.notifications,
    required this.onOpenSupport,
    required this.onOpenNotifications,
    required this.onOpenProfile,
    required this.onOpenSettings,
    required this.notificationsAnchorKey,
  });

  final String title;
  final AdminNotificationsService notifications;
  final VoidCallback onOpenSupport;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSettings;
  final GlobalKey notificationsAnchorKey;

  @override
  State<_AdminHeader> createState() => _AdminHeaderState();
}

class _AdminHeaderState extends State<_AdminHeader> {
  final AdminAuthService _auth = AdminAuthService();
  String _initials = 'A';

  @override
  void initState() {
    super.initState();
    _primeAvatar();
  }

  Future<void> _primeAvatar() async {
    await _auth.initialize();
    if (!mounted) return;
    final name = (_auth.currentFullName ?? _auth.currentEmail ?? '').trim();
    setState(() => _initials = _deriveInitials(name));
  }

  static String _deriveInitials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wood Home Furniture Trading / ${widget.title}', style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Spacer(),
              // Support inbox (message icon) — unread support count; sits left of the bell.
              ValueListenableBuilder<AdminNotificationSnapshot>(
                valueListenable: widget.notifications.snapshot,
                builder: (context, snap, _) {
                  final supportUnread = snap.unreadSupportConversations;
                  return IconButton(
                    onPressed: widget.onOpenSupport,
                    tooltip: 'Support inbox',
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.chat_bubble_rounded, size: 24),
                        if (supportUnread > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.all(Radius.circular(999)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                supportUnread > 99 ? '99+' : '$supportUnread',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              // Inventory / system notifications (bell); support is excluded from this badge.
              ValueListenableBuilder<AdminNotificationSnapshot>(
                valueListenable: widget.notifications.snapshot,
                builder: (context, AdminNotificationSnapshot snap, _) {
                  final count = snap.bellBadgeCount;
                  return IconButton(
                    key: widget.notificationsAnchorKey,
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.notifications_outlined, size: 24),
                        if (count > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.all(Radius.circular(999)),
                              ),
                              child: Text(
                                count > 99 ? '99+' : '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    onPressed: widget.onOpenNotifications,
                    tooltip: 'Notifications',
                  );
                },
              ),
              const SizedBox(width: 8),
              // Account dropdown
              PopupMenuButton<String>(
                offset: const Offset(0, 50),
                child: CircleAvatar(
                  backgroundColor: AdminPalette.brown,
                  radius: 18,
                  child: Text(_initials, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'profile',
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 20),
                        const SizedBox(width: 12),
                        Text('Profile Information', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: [
                        const Icon(Icons.settings_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text('Settings', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
                onSelected: (String value) {
                  if (value == 'profile') {
                    widget.onOpenProfile();
                  } else if (value == 'settings') {
                    widget.onOpenSettings();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _InlineNotificationsPanel extends StatelessWidget {
  const _InlineNotificationsPanel({required this.service, this.onClose});

  final AdminNotificationsService service;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminNotificationSnapshot>(
      valueListenable: service.snapshot,
      builder: (context, snap, _) {
        return DecoratedBox(
          decoration: const BoxDecoration(color: Colors.white),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
                ),
                child: Row(
                  children: [
                    Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: service.refresh,
                      tooltip: 'Refresh',
                      visualDensity: VisualDensity.compact,
                    ),
                    if (onClose != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: onClose,
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: snap.items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'All quiet.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: snap.items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final item = snap.items[index];
                          const color = Color(0xFFF97316);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.inventory_2_outlined, color: color, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AdminContentWrapper extends StatelessWidget {
  const _AdminContentWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 18, right: 18, bottom: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );
  }
}
