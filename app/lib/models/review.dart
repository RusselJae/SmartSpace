/// Optional photo/video attached to a product review.
class ReviewMediaItem {
  const ReviewMediaItem({required this.url, required this.type});

  final String url;
  final String type; // image | video

  bool get isVideo => type == 'video';

  factory ReviewMediaItem.fromJson(Map<String, dynamic> json) {
    return ReviewMediaItem(
      url: json['url']?.toString() ?? '',
      type: json['type']?.toString() == 'video' ? 'video' : 'image',
    );
  }

  Map<String, dynamic> toJson() => {'url': url, 'type': type};
}

/// Review model representing customer feedback on products.
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
    this.media = const [],
    this.updatedAt,
  });

  final String id;
  final String productId;
  final String productName;
  final String userId;
  final String userName;
  final int rating;
  final String content;
  final String status;
  final List<ReviewMediaItem> media;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory Review.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) return DateTime.parse(value);
      throw FormatException('Invalid date format: $value');
    }

    final mediaRaw = json['media'];
    final media = mediaRaw is List
        ? mediaRaw
            .whereType<Map>()
            .map((e) => ReviewMediaItem.fromJson(Map<String, dynamic>.from(e)))
            .where((m) => m.url.isNotEmpty)
            .toList()
        : <ReviewMediaItem>[];

    return Review(
      id: json['id'] as String,
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      rating: json['rating'] is int ? json['rating'] as int : (json['rating'] as num).toInt(),
      content: json['content'] as String? ?? '',
      status: json['status'] as String? ?? 'published',
      media: media,
      createdAt: parseDate(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? parseDate(json['updatedAt']) : null,
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
      'media': media.map((m) => m.toJson()).toList(),
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
    List<ReviewMediaItem>? media,
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
      media: media ?? this.media,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
