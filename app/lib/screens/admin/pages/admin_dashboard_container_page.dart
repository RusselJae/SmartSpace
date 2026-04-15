import 'package:flutter/material.dart';

import 'admin_dashboard_page.dart';
import 'admin_user_behavior_page.dart';
import 'sales_reports_admin_page.dart';
import '../widgets/admin_analytics_components.dart';

/// Parent **Dashboard** area with sub-tabs: Overview, Sales Reports, User Behavior.
/// Matches Apple HIG: clear hierarchy, segmented navigation, calm spacing.
class AdminDashboardContainerPage extends StatefulWidget {
  const AdminDashboardContainerPage({
    super.key,
    required this.initialSubTab,
    required this.onOpenOrders,
    required this.onOpenReviews,
    this.onDashboardSubTabChanged,
  });

  /// 0 Overview, 1 Sales Reports, 2 User Behavior
  final int initialSubTab;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenReviews;
  /// Notifies [AdminShell] so the content header subtitle matches the selected dashboard sub-tab.
  final ValueChanged<int>? onDashboardSubTabChanged;

  @override
  State<AdminDashboardContainerPage> createState() => _AdminDashboardContainerPageState();
}

class _AdminDashboardContainerPageState extends State<AdminDashboardContainerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSubTab.clamp(0, 2);
    _tabController = TabController(length: 3, vsync: this, initialIndex: initial);
    _tabController.addListener(_onDashboardTabTick);
    // First frame: shell header subtitle should match the initial route (e.g. /admin/user-behavior).
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitDashboardSubTab(_tabController.index));
  }

  void _onDashboardTabTick() {
    if (!mounted) return;
    // Fire when the tab animation settles so we do not spam parent [setState] mid-swipe.
    if (!_tabController.indexIsChanging) {
      _emitDashboardSubTab(_tabController.index);
    }
  }

  void _emitDashboardSubTab(int rawIndex) {
    final i = rawIndex.clamp(0, 2);
    widget.onDashboardSubTabChanged?.call(i);
  }

  @override
  void didUpdateWidget(covariant AdminDashboardContainerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSubTab != widget.initialSubTab) {
      final next = widget.initialSubTab.clamp(0, 2);
      if (_tabController.index != next) {
        _tabController.animateTo(next);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onDashboardTabTick);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF8D6E63),
            unselectedLabelColor: AdminAnalyticsColors.muted,
            indicatorColor: const Color(0xFF8D6E63),
            indicatorWeight: 2.5,
            labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Sales Reports'),
              Tab(text: 'User Behavior'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              AdminDashboardPage(onOpenOrders: widget.onOpenOrders),
              const SalesReportsAdminPage(),
              AdminUserBehaviorPage(onOpenReviews: widget.onOpenReviews),
            ],
          ),
        ),
      ],
    );
  }
}
