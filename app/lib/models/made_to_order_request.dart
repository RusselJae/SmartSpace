class MadeToOrderRequest {
  const MadeToOrderRequest({
    required this.id,
    required this.requestRef,
    required this.userId,
    required this.userName,
    required this.itemName,
    required this.downPaymentAmount,
    required this.status,
    required this.createdAt,
    this.preferredSize,
    this.materials,
    this.notes,
    this.validIdUrl,
    this.referenceUrls = const [],
    this.quotedTotal,
    this.quotedDownpayment,
    this.quotedRemaining,
    this.adminMessage,
    this.orderId,
    this.updatedAt,
  });

  final String id;
  final String requestRef;
  final String userId;
  final String userName;
  final String itemName;
  final String? preferredSize;
  final String? materials;
  final String? notes;
  final double downPaymentAmount;
  final String status;
  final String? validIdUrl;
  final List<String> referenceUrls;
  final DateTime createdAt;

  /// Set when admin sends a quote (PHP amounts).
  final double? quotedTotal;
  final double? quotedDownpayment;
  final double? quotedRemaining;

  /// Admin note (quote context or decline reason).
  final String? adminMessage;

  /// Linked catalog order after user accepts quote and checks out.
  final String? orderId;

  final DateTime? updatedAt;

  factory MadeToOrderRequest.fromJson(Map<String, dynamic> json) {
    final refs = json['referenceUrlsJson'];
    List<String> parsedRefs = const [];
    if (refs is List) {
      parsedRefs = refs.map((e) => e.toString()).toList(growable: false);
    } else if (refs is String && refs.isNotEmpty) {
      parsedRefs = refs
          .replaceAll('[', '')
          .replaceAll(']', '')
          .split(',')
          .map((e) => e.replaceAll('"', '').trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    double? parseOpt(dynamic v) {
      if (v == null) return null;
      return double.tryParse(v.toString());
    }

    return MadeToOrderRequest(
      id: json['id']?.toString() ?? '',
      requestRef: json['requestRef']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      itemName: json['itemName']?.toString() ?? '',
      preferredSize: json['preferredSize']?.toString(),
      materials: json['materials']?.toString(),
      notes: json['notes']?.toString(),
      downPaymentAmount: double.tryParse(json['downPaymentAmount']?.toString() ?? '0') ?? 0,
      status: json['status']?.toString() ?? 'pending_review',
      validIdUrl: json['validIdUrl']?.toString(),
      referenceUrls: parsedRefs,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      quotedTotal: parseOpt(json['quotedTotal']),
      quotedDownpayment: parseOpt(json['quotedDownpayment']),
      quotedRemaining: parseOpt(json['quotedRemaining']),
      adminMessage: json['adminMessage']?.toString(),
      orderId: json['orderId']?.toString(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}
