import 'package:flutter/material.dart';

import 'admin_theme.dart';
import 'pages/admin_dashboard_page.dart';
import 'pages/admins_admin_page.dart';
import 'pages/orders_admin_page.dart';
import 'pages/products_admin_page.dart';
import 'pages/reviews_admin_page.dart';
import 'pages/users_admin_page.dart';
import '../../services/admin_auth_service.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  static const String route = '/admin';

  @override
  State<AdminShell> createState() => _AdminShellState();
}

typedef _AdminViewBuilder = Widget Function(VoidCallback goToReviews);

class _AdminDestination {
  const _AdminDestination({required this.label, required this.icon, required this.builder});

  final String label;
  final IconData icon;
  final _AdminViewBuilder builder;
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  bool _authChecked = false;

  late final List<_AdminDestination> _destinations = [
    _AdminDestination(
      label: 'Overview',
      icon: Icons.auto_graph_outlined,
      builder: (goToReviews) => AdminDashboardPage(onOpenReviews: goToReviews),
    ),
    _AdminDestination(
      label: 'Products',
      icon: Icons.chair_alt_outlined,
      builder: (_) => const ProductsAdminPage(),
    ),
    _AdminDestination(
      label: 'Orders',
      icon: Icons.shopping_bag_outlined,
      builder: (_) => const OrdersAdminPage(),
    ),
    _AdminDestination(
      label: 'Reviews',
      icon: Icons.reviews_outlined,
      builder: (_) => const ReviewsAdminPage(),
    ),
    _AdminDestination(
      label: 'Users',
      icon: Icons.group_outlined,
      builder: (_) => const UsersAdminPage(),
    ),
    _AdminDestination(
      label: 'Admins',
      icon: Icons.admin_panel_settings_outlined,
      builder: (_) => const AdminsAdminPage(),
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
    final Widget currentPage = _destinations[_index].builder(() => _selectTab(3));

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
                    _AdminHeader(title: _destinations[_index].label),
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
            _AdminHeader(title: _destinations[_index].label),
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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.view_in_ar_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SmartSpace',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Admin console',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        Text(
                          'SmartSpace',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, size: 18, color: Colors.white),
                    tooltip: 'Logout',
                    onPressed: () async {
                      await AdminAuthService().signOut();
                      if (!context.mounted) return;
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                      if (!context.mounted) return;
                      Navigator.of(context).pushReplacementNamed('/admin/login');
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: destinations.length,
              itemBuilder: (context, index) {
                final bool active = selectedIndex == index;
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
                      onTap: () => onSelect(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              destinations[index].icon,
                              color: active ? Colors.white : Colors.grey[800],
                            ),
                            const SizedBox(width: 12),
                            Text(
                              destinations[index].label,
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
        ],
      ),
    );
  }
}

class _AdminHeader extends StatefulWidget {
  const _AdminHeader({required this.title});

  final String title;

  @override
  State<_AdminHeader> createState() => _AdminHeaderState();
}

class _AdminHeaderState extends State<_AdminHeader> {
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
                  Text('SmartSpace / ${widget.title}', style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Spacer(),
              CircleAvatar(
                backgroundColor: AdminPalette.brown,
                radius: 18,
                child: const Text('SA', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
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
