class User {
  final String id;
  final String email;
  final String fullName;
  final String username;
  final String? phoneNumber;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? avatarUrl;
  final List<String> addresses;
  final List<String> wishlistProductIds;
  final List<String> orderIds;
  final String preferredStyle;
  final double minBudget;
  final double maxBudget;
  final DateTime createdAt;
  final DateTime lastLoginAt;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.username,
    this.phoneNumber,
    this.gender,
    this.dateOfBirth,
    this.avatarUrl,
    required this.addresses,
    required this.wishlistProductIds,
    required this.orderIds,
    this.preferredStyle = '',
    this.minBudget = 0,
    this.maxBudget = 0,
    required this.createdAt,
    required this.lastLoginAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? value) =>
        value == null ? null : DateTime.tryParse(value);

    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String? ?? '',
      username: json['username'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String?,
      gender: json['gender'] as String?,
      dateOfBirth: parseDate(json['dateOfBirth'] as String?),
      avatarUrl: json['avatarUrl'] as String?,
      addresses: (json['addresses'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      wishlistProductIds:
          (json['wishlistProductIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      orderIds: (json['orderIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      preferredStyle: json['preferredStyle'] as String? ?? '',
      minBudget: (json['minBudget'] as num?)?.toDouble() ?? 0,
      maxBudget: (json['maxBudget'] as num?)?.toDouble() ?? 0,
      createdAt: parseDate(json['createdAt'] as String?) ?? DateTime.now(),
      lastLoginAt: parseDate(json['lastLoginAt'] as String?) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'username': username,
      'phoneNumber': phoneNumber,
      'gender': gender,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'avatarUrl': avatarUrl,
      'addresses': addresses,
      'wishlistProductIds': wishlistProductIds,
      'orderIds': orderIds,
      'preferredStyle': preferredStyle,
      'minBudget': minBudget,
      'maxBudget': maxBudget,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? fullName,
    String? username,
    String? phoneNumber,
    String? gender,
    DateTime? dateOfBirth,
    String? avatarUrl,
    List<String>? addresses,
    List<String>? wishlistProductIds,
    List<String>? orderIds,
    String? preferredStyle,
    double? minBudget,
    double? maxBudget,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      addresses: addresses ?? this.addresses,
      wishlistProductIds: wishlistProductIds ?? this.wishlistProductIds,
      orderIds: orderIds ?? this.orderIds,
      preferredStyle: preferredStyle ?? this.preferredStyle,
      minBudget: minBudget ?? this.minBudget,
      maxBudget: maxBudget ?? this.maxBudget,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}













