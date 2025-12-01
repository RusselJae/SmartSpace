/// Admin model representing an administrator in the SmartSpace system.
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
  });

  final String id;
  final String email;
  final String fullName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;

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
    );
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
    };
  }
}




