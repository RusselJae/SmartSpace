/// Named routes for every admin shell tab (hash URLs on web: `/#/admin/products`).
class AdminRoutes {
  AdminRoutes._();

  static const String legacyShell = '/admin';

  /// Primary dashboard URL (Overview + Sales Reports + User Behavior).
  static const String dashboard = '/admin/dashboard';

  /// Legacy / bookmark-friendly aliases for the same shell tab.
  static const String overview = '/admin/overview';
  static const String salesReports = '/admin/sales-reports';
  static const String userBehavior = '/admin/user-behavior';
  static const String products = '/admin/products';
  static const String orders = '/admin/orders';
  static const String reviews = '/admin/reviews';
  static const String users = '/admin/users';
  static const String admins = '/admin/admins';
  static const String support = '/admin/support';
  static const String faqs = '/admin/faqs';
  static const String legal = '/admin/legal';
  static const String activityLogs = '/admin/activity-logs';
  static const String settings = '/admin/settings';

  /// Order matches [_AdminShellState] `_destinations` indices.
  static const List<String> pathsByIndex = <String>[
    dashboard,
    products,
    orders,
    reviews,
    users,
    admins,
    support,
    faqs,
    legal,
    activityLogs,
    settings,
  ];

  static int get tabCount => pathsByIndex.length;

  /// Normalizes trailing slashes and query strings for lookup.
  static String normalizePath(String raw) {
    var p = raw.trim();
    if (p.contains('?')) {
      p = p.substring(0, p.indexOf('?'));
    }
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// Maps a [RouteSettings.name] to a shell tab index (default 0).
  static int indexForRouteName(String? name) {
    if (name == null || name.isEmpty) return 0;
    final p = normalizePath(name);
    if (p == legacyShell ||
        p == overview ||
        p == dashboard ||
        p == salesReports ||
        p == userBehavior) {
      return 0;
    }
    final i = pathsByIndex.indexOf(p);
    return i < 0 ? 0 : i;
  }

  /// Sub-tab inside [AdminDashboardContainerPage] when shell index is `0`.
  /// 0 Overview, 1 Sales Reports, 2 User Behavior.
  static int dashboardTabForRouteName(String? name) {
    final p = normalizePath(name ?? '');
    if (p == salesReports) return 1;
    if (p == userBehavior) return 2;
    return 0;
  }

  static String pathForIndex(int index) {
    if (index < 0 || index >= pathsByIndex.length) return dashboard;
    return pathsByIndex[index];
  }

  /// Paths accepted after login / hash restore (includes dashboard aliases).
  static bool isKnownShellPath(String? name) {
    final p = normalizePath(name ?? '');
    if (p == legacyShell ||
        p == dashboard ||
        p == overview ||
        p == salesReports ||
        p == userBehavior) {
      return true;
    }
    return pathsByIndex.contains(p);
  }
}
