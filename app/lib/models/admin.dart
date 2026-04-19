/// Admin model representing an administrator in the Wood Home Furniture Trading system.
///
/// Admins have full access to the admin console and can manage
/// products, orders, reviews, users, and other admins.
class Admin {
  const Admin({
    required this.id,
    required this.email,
    required this.fullName,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
    this.emailVerified = true,
    this.role = 'operations_admin',
    this.isDisabled = false,
    this.extraPermissions = const [],
    this.revokedPermissions = const [],
  });

  final String id;
  final String email;
  final String fullName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;
  /// False until the admin completes email verification (new accounts).
  final bool emailVerified;

  /// RBAC role from the API (`super_admin`, `operations_admin`, `support_admin`, `social_admin`).
  final String role;

  /// When true, API and login reject this account until a super admin re-enables it.
  final bool isDisabled;

  /// Extra capability keys granted beyond the role baseline (server-validated).
  final List<String> extraPermissions;

  /// Capability keys explicitly revoked (overrides role and extras).
  final List<String> revokedPermissions;

  /// Creates an Admin from a JSON map (typically from the API).
  factory Admin.fromJson(Map<String, dynamic> json) {
    return Admin(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.parse(json['lastLoginAt'] as String)
          : null,
      emailVerified: json['emailVerified'] as bool? ?? true,
      role: json['role'] as String? ?? 'operations_admin',
      isDisabled: json['isDisabled'] as bool? ?? false,
      extraPermissions: _parseStringList(json['extraPermissions']),
      revokedPermissions: _parseStringList(json['revokedPermissions']),
    );
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList(growable: false);
  }

  /// Converts this Admin to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'emailVerified': emailVerified,
      'role': role,
      'isDisabled': isDisabled,
      'extraPermissions': extraPermissions,
      'revokedPermissions': revokedPermissions,
    };
  }
}
