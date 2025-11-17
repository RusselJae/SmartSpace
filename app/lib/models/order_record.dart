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
}


