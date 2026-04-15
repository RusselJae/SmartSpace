class AdminActivityLog {
  const AdminActivityLog({
    required this.id,
    required this.adminId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.details,
    required this.createdAt,
    required this.adminEmail,
    required this.adminFullName,
  });

  final String id;
  final String? adminId;
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic> details;
  final DateTime createdAt;
  final String? adminEmail;
  final String? adminFullName;

  factory AdminActivityLog.fromJson(Map<String, dynamic> json) {
    return AdminActivityLog(
      id: (json['id'] ?? '').toString(),
      adminId: json['adminId']?.toString(),
      action: (json['action'] ?? '').toString(),
      entityType: (json['entityType'] ?? '').toString(),
      entityId: json['entityId']?.toString(),
      details: (json['details'] as Map<String, dynamic>?) ?? const {},
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
      adminEmail: json['adminEmail']?.toString(),
      adminFullName: json['adminFullName']?.toString(),
    );
  }
}

