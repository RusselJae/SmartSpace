/// Named routes for every admin shell tab (hash URLs on web: `/#/admin/products`).
class AdminRoutes {
  AdminRoutes._();

  static const String legacyShell = '/admin';

  /// Primary dashboard URL (Overview + User Growth).
  static const String dashboard = '/admin/dashboard';

  /// Legacy / bookmark-friendly aliases for the same shell tab.
  static const String overview = '/admin/overview';
  static const String salesReports = '/admin/sales-reports';
  static const String userBehavior = '/admin/user-behavior';
  static const String products = '/admin/products';
  static const String inventory = '/admin/inventory';
  static const String orders = '/admin/orders';
  static const String reviews = '/admin/reviews';
  static const String users = '/admin/users';
  /// Staff management (owner / super admin). Legacy path kept for bookmarks.
  static const String staff = '/admin/staff';
  static const String admins = '/admin/admins';
  static const String support = '/admin/support';
  static const String faqs = '/admin/faqs';
  static const String legal = '/admin/legal';
  static const String activityLogs = '/admin/activity-logs';
  static const String settings = '/admin/settings';

  /// Order matches [_AdminShellState] `_destinations` indices.
  static const List<String> pathsByIndex = <String>[
    dashboard,
    salesReports,
    products,
    inventory,
    orders,
    reviews,
    users,
    staff,
    activityLogs,
    faqs,
    support,
    legal,
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
        p == userBehavior) {
      return 0;
    }
    if (p == salesReports) return 1;
    if (p == admins) return 7;
    final i = pathsByIndex.indexOf(p);
    return i < 0 ? 0 : i;
  }

  /// Sub-tab inside [AdminDashboardContainerPage] when shell index is `0`.
  /// 0 Overview, 1 User Growth.
  static int dashboardTabForRouteName(String? name) {
    final p = normalizePath(name ?? '');
    if (p == userBehavior) return 1;
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
    if (p == admins) return true;
    return pathsByIndex.contains(p);
  }
}
