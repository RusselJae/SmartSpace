class CustomerNotification {
  const CustomerNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, String> data;
  final bool isRead;
  final DateTime createdAt;

  CustomerNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? body,
    Map<String, String>? data,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return CustomerNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory CustomerNotification.fromJson(Map<String, dynamic> json) {
    return CustomerNotification(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'system',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      data: (json['data'] as Map<String, dynamic>? ?? const <String, dynamic>{})
          .map((key, value) => MapEntry(key, value.toString())),
      isRead: json['isRead'] == true || json['isRead'] == 1,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

