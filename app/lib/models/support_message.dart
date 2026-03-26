class SupportMessage {
  final String id;
  final String conversationId;
  final String senderType; // 'user' | 'admin'
  final String? senderUserId;
  final String? senderAdminId;
  final String body;
  final String? attachmentUrl;
  final String? attachmentType; // 'image' | 'file'
  final String? attachmentMime;
  final String? attachmentFilename;
  final DateTime createdAt;

  SupportMessage({
    required this.id,
    required this.conversationId,
    required this.senderType,
    this.senderUserId,
    this.senderAdminId,
    required this.body,
    this.attachmentUrl,
    this.attachmentType,
    this.attachmentMime,
    this.attachmentFilename,
    required this.createdAt,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderType: json['senderType'] as String,
      senderUserId: json['senderUserId'] as String?,
      senderAdminId: json['senderAdminId'] as String?,
      body: json['body'] as String,
      attachmentUrl: json['attachmentUrl'] as String?,
      attachmentType: json['attachmentType'] as String?,
      attachmentMime: json['attachmentMime'] as String?,
      attachmentFilename: json['attachmentFilename'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

