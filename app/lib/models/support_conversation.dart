class SupportConversation {
  final String id;
  final String userId;
  final String status; // 'open' | 'closed'
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final String? lastMessageSenderType; // 'user' | 'admin'
  final List<String> tags;

  SupportConversation({
    required this.id,
    required this.userId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageSenderType,
    this.tags = const [],
  });

  factory SupportConversation.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((t) => t.toString()).where((t) => t.trim().isNotEmpty).toList()
        : <String>[];

    return SupportConversation(
      id: json['id'] as String,
      userId: json['userId'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'] as String)
          : null,
      lastMessagePreview: json['lastMessagePreview'] as String?,
      lastMessageSenderType: json['lastMessageSenderType'] as String?,
      tags: tags,
    );
  }

  SupportConversation copyWith({
    String? id,
    String? userId,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    String? lastMessagePreview,
    String? lastMessageSenderType,
    List<String>? tags,
  }) {
    return SupportConversation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageSenderType: lastMessageSenderType ?? this.lastMessageSenderType,
      tags: tags ?? this.tags,
    );
  }
}

