import 'package:flutter/material.dart';

import 'admin_theme.dart';
import 'pages/orders_admin_page.dart';
import 'pages/products_admin_page.dart';
import 'pages/reviews_admin_page.dart';
import 'pages/users_admin_page.dart';
import 'widgets/admin_summary_card.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  static const String route = '/admin';

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminTab {
  const _AdminTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  final ScrollController _scrollController = ScrollController();

  final List<_AdminTab> _tabs = const [
    _AdminTab(label: 'Dashboard', icon: Icons.dashboard_outlined),
    _AdminTab(label: 'Products', icon: Icons.chair_alt_outlined),
    _AdminTab(label: 'Orders', icon: Icons.shopping_bag_outlined),
    _AdminTab(label: 'Reviews', icon: Icons.reviews_outlined),
    _AdminTab(label: 'Users', icon: Icons.group_outlined),
  ];
  final List<AdminSummaryMetric> _metrics = const [
    AdminSummaryMetric(
      title: 'Revenue',
      value: '\$24.8K',
      deltaLabel: '+12% vs last week',
      icon: Icons.attach_money,
      background: AdminPalette.brown,
    ),
    AdminSummaryMetric(
      title: 'Orders',
      value: '328',
      deltaLabel: '+18 new today',
      icon: Icons.receipt_long,
      background: AdminPalette.accent,
    ),
    AdminSummaryMetric(
      title: 'Returning users',
      value: '64%',
      deltaLabel: '4% above average',
      icon: Icons.group,
      background: AdminPalette.dark,
    ),
    AdminSummaryMetric(
      title: 'Open tickets',
      value: '12',
      deltaLabel: '5 escalated',
      icon: Icons.warning_amber_rounded,
      background: AdminPalette.clay,
    ),
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAdminTheme(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF5F5F7),
          body: SafeArea(
            child: Row(
              children: [
                _SidebarMenu(tabs: _tabs, index: _index, onChanged: _selectTab),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(activeTab: _tabs[_index].label),
                      Expanded(
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                            children: [
                              _SummaryGrid(metrics: _metrics, wide: MediaQuery.of(context).size.width > 1200),
                              const SizedBox(height: 24),
                              _ContentCard(child: _buildPage(_index)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 1:
        return const ProductsAdminPage();
      case 2:
        return const OrdersAdminPage();
      case 3:
        return const ReviewsAdminPage();
      case 4:
        return const UsersAdminPage();
      default:
        return const _DashboardPlaceholder();
    }
  }

  void _selectTab(int value) {
    setState(() => _index = value);
  }
}

class _DashboardPlaceholder extends StatelessWidget {
  const _DashboardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Control center', style: TextStyle(fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text('Select a module to manage details.'),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.activeTab});

  final String activeTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(color: Colors.white),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard / $activeTab', style: Theme.of(context).textTheme.labelLarge),
              Text(activeTab, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(width: 32),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search here...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                filled: true,
                fillColor: const Color(0xFFF2F2F2),
              ),
            ),
          ),
          const SizedBox(width: 24),
          CircleAvatar(
            backgroundColor: AdminPalette.brown,
            child: const Text('SA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _SidebarMenu extends StatelessWidget {
  const _SidebarMenu({required this.tabs, required this.index, required this.onChanged});

  final List<_AdminTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 32),
          const FlutterLogo(size: 48),
          const SizedBox(height: 32),
          for (int i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: index == i ? AdminPalette.brown.withAlpha((0.15 * 255).round()) : Colors.transparent,
                leading: Icon(tabs[i].icon, color: index == i ? AdminPalette.brown : Colors.grey),
                title: Text(tabs[i].label, style: TextStyle(color: index == i ? AdminPalette.brown : Colors.grey[700])),
                onTap: () => onChanged(i),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.metrics, required this.wide});

  final List<AdminSummaryMetric> metrics;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final int columns = wide ? 4 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.4,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) => AdminSummaryCard(metric: metrics[index]),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}
