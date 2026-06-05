class SupportFormRequest {
  const SupportFormRequest({
    required this.id,
    required this.conversationId,
    required this.userId,
    required this.formType,
    required this.status,
    this.payload,
    required this.formLink,
    required this.createdAt,
    this.submittedAt,
  });

  final String id;
  final String conversationId;
  final String userId;
  final String formType;
  final String status;
  final Map<String, String>? payload;
  final String formLink;
  final DateTime createdAt;
  final DateTime? submittedAt;

  bool get isSubmitted => status == 'submitted';

  factory SupportFormRequest.fromJson(Map<String, dynamic> json) {
    Map<String, String>? payload;
    final raw = json['payload'];
    if (raw is Map) {
      payload = raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
    return SupportFormRequest(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      formType: json['formType']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      payload: payload,
      formLink: json['formLink']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      submittedAt: json['submittedAt'] != null
          ? DateTime.tryParse(json['submittedAt'].toString())
          : null,
    );
  }
}
