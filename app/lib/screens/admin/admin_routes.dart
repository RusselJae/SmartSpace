/// Named routes for every admin shell tab (hash URLs on web: `/#/admin/products`).
class AdminRoutes {
  AdminRoutes._();

  static const String legacyShell = '/admin';

  static const String overview = '/admin/overview';
  static const String salesReports = '/admin/sales-reports';
  static const String products = '/admin/products';
  static const String orders = '/admin/orders';
  static const String reviews = '/admin/reviews';
  static const String users = '/admin/users';
  static const String admins = '/admin/admins';
  static const String support = '/admin/support';
  static const String faqs = '/admin/faqs';
  static const String legal = '/admin/legal';
  static const String settings = '/admin/settings';

  /// Order matches [_AdminShellState] `_destinations` indices.
  static const List<String> pathsByIndex = <String>[
    overview,
    salesReports,
    products,
    orders,
    reviews,
    users,
    admins,
    support,
    faqs,
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
    if (p == legacyShell) return 0;
    final i = pathsByIndex.indexOf(p);
    return i < 0 ? 0 : i;
  }

  static String pathForIndex(int index) {
    if (index < 0 || index >= pathsByIndex.length) return overview;
    return pathsByIndex[index];
  }
}
