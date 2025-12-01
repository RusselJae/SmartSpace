/// Review model representing customer feedback on products.
/// Follows the same clean structure as other models in the app.
class Review {
  const Review({
    required this.id,
    required this.productId,
    required this.productName,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.content,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String productId;
  final String productName;
  final String userId;
  final String userName;
  final int rating; // 1-5 stars
  final String content;
  final String status; // 'pending', 'published', 'flagged', 'rejected'
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      rating: json['rating'] as int,
      content: json['content'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'productName': productName,
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'content': content,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  Review copyWith({
    String? id,
    String? productId,
    String? productName,
    String? userId,
    String? userName,
    int? rating,
    String? content,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Review(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      rating: rating ?? this.rating,
      content: content ?? this.content,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}








