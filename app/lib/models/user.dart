class User {
  final String id;
  final String email;
  final String fullName;
  final String? phoneNumber;
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
    this.phoneNumber,
    required this.addresses,
    required this.wishlistProductIds,
    required this.orderIds,
    required this.preferredStyle,
    required this.minBudget,
    required this.maxBudget,
    required this.createdAt,
    required this.lastLoginAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String,
      phoneNumber: json['phoneNumber'] as String?,
      addresses: List<String>.from(json['addresses'] as List),
      wishlistProductIds: List<String>.from(json['wishlistProductIds'] as List),
      orderIds: List<String>.from(json['orderIds'] as List),
      preferredStyle: json['preferredStyle'] as String,
      minBudget: (json['minBudget'] as num).toDouble(),
      maxBudget: (json['maxBudget'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastLoginAt: DateTime.parse(json['lastLoginAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
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
    String? phoneNumber,
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
      phoneNumber: phoneNumber ?? this.phoneNumber,
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













