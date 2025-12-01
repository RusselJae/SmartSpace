class OrderRecord {
  const OrderRecord({
    required this.id,
    required this.userId,
    required this.userName,
    required this.productIds,
    required this.totalAmount,
    required this.status,
    required this.shippingAddress,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String userName;
  final List<String> productIds;
  final double totalAmount;
  final String status;
  final Map<String, dynamic> shippingAddress;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory OrderRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value is String) {
        return DateTime.parse(value);
      } else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } else {
        return DateTime.now();
      }
    }
    return OrderRecord(
      id: json['id'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String? ?? '',
      productIds: List<String>.from(json['productIds'] as List),
      totalAmount: (json['totalAmount'] as num).toDouble(),
      status: json['status'] as String,
      shippingAddress: Map<String, dynamic>.from(
        (json['shippingAddress'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'productIds': productIds,
      'totalAmount': totalAmount,
      'status': status,
      'shippingAddress': shippingAddress,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}


