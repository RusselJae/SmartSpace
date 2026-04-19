import '../models/admin.dart';

/// Role and permission checks for the admin console (mirrors backend [ADMIN_PERMISSIONS] / role matrix).
class AdminPermissions {
  AdminPermissions._();

  static const String productsWrite = 'products:write';
  static const String ordersRead = 'orders:read';
  static const String ordersWrite = 'orders:write';
  static const String usersRead = 'users:read';
  static const String reviewsModerate = 'reviews:moderate';
  static const String faqsWrite = 'faqs:write';
  static const String legalWrite = 'legal:write';
  static const String supportWrite = 'support:write';
  static const String notificationsSend = 'notifications:send';
  static const String activityRead = 'activity:read';
  static const String adminsManage = 'admins:manage';
  static const String settingsWrite = 'settings:write';
  static const String madeToOrderWrite = 'made_to_order:write';

  /// Every permission key the backend knows about (used for super_admin display / chips).
  static const List<String> allDefinedPermissions = <String>[
    activityRead,
    adminsManage,
    faqsWrite,
    legalWrite,
    madeToOrderWrite,
    notificationsSend,
    ordersRead,
    ordersWrite,
    productsWrite,
    reviewsModerate,
    settingsWrite,
    supportWrite,
    usersRead,
  ];

  /// Number of primary shell tabs (Dashboard + rail items), aligned with [AdminRoutes.pathsByIndex].
  static const int shellTabCount = 11;

  /// Permission strings granted for this [role] (mirrors backend [ROLE_MATRIX]; super = all defined).
  static List<String> permissionsForRole(String? roleRaw) {
    final role = (roleRaw ?? '').trim();
    if (role.isEmpty) {
      return const [];
    }
    if (role == 'super_admin') {
      final copy = List<String>.from(allDefinedPermissions);
      copy.sort();
      return copy;
    }
    final set = switch (role) {
      'operations_admin' => _ops,
      'support_admin' => _support,
      'social_admin' => _social,
      _ => <String>{},
    };
    final list = set.toList();
    list.sort();
    return list;
  }

  /// Short label for table / chips (e.g. `products:write` → `products: write`).
  static String formatPermissionLabel(String key) {
    return key.replaceAll('_', ' ');
  }

  /// Effective permissions after role + [Admin.extraPermissions] − [Admin.revokedPermissions].
  static List<String> effectivePermissionsFor(Admin admin) {
    final base = permissionsForRole(admin.role).toSet();
    final extra = admin.extraPermissions.toSet();
    final revoked = admin.revokedPermissions.toSet();
    final merged = {...base, ...extra};
    merged.removeWhere(revoked.contains);
    final out = merged.toList();
    out.sort();
    return out;
  }

  static final Set<String> _ops = {
    productsWrite,
    ordersRead,
    ordersWrite,
    usersRead,
    reviewsModerate,
    faqsWrite,
    legalWrite,
    supportWrite,
    notificationsSend,
    activityRead,
    madeToOrderWrite,
  };

  static final Set<String> _support = {
    ordersRead,
    ordersWrite,
    usersRead,
    supportWrite,
  };

  static final Set<String> _social = {
    ordersRead,
    reviewsModerate,
    faqsWrite,
  };

  static bool adminHasPermission(String? roleRaw, String permission) {
    final role = (roleRaw ?? '').trim();
    if (role.isEmpty) {
      return false;
    }
    if (role == 'super_admin') {
      return true;
    }
    final set = switch (role) {
      'operations_admin' => _ops,
      'support_admin' => _support,
      'social_admin' => _social,
      _ => <String>{},
    };
    return set.contains(permission);
  }

  /// Full shell index: 0 Dashboard … 10 Settings (see [AdminRoutes.pathsByIndex] order).
  static bool canAccessShellTabIndex(int fullTabIndex, String? role) {
    switch (fullTabIndex) {
      case 0:
        return true;
      case 1:
        return adminHasPermission(role, productsWrite);
      case 2:
        return adminHasPermission(role, ordersRead);
      case 3:
        return adminHasPermission(role, reviewsModerate);
      case 4:
        return adminHasPermission(role, usersRead);
      case 5:
        return adminHasPermission(role, adminsManage);
      case 6:
        return adminHasPermission(role, activityRead);
      case 7:
        return adminHasPermission(role, faqsWrite);
      case 8:
        return adminHasPermission(role, supportWrite);
      case 9:
        return adminHasPermission(role, legalWrite);
      case 10:
        return adminHasPermission(role, settingsWrite);
      default:
        return false;
    }
  }
}
