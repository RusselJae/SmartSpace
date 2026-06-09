/// Raw material / supply row tracked in the materials inventory panel.
class InventoryMaterial {
  const InventoryMaterial({
    required this.id,
    required this.name,
    this.sku,
    required this.unit,
    required this.quantityOnHand,
    required this.reorderLevel,
    this.supplier,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Low stock when on-hand is 1–3; in stock when > 3; out of stock when 0.
  static const double lowStockThreshold = 3;

  final String id;
  final String name;
  final String? sku;
  final String unit;
  final double quantityOnHand;
  final double reorderLevel;
  final String? supplier;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOutOfStock => quantityOnHand <= 0;

  bool get isLowStock =>
      quantityOnHand > 0 && quantityOnHand <= lowStockThreshold;

  bool get isInStock => quantityOnHand > lowStockThreshold;

  String get stockStatusLabel {
    if (isOutOfStock) return 'Out of stock';
    if (isLowStock) return 'Low stock';
    return 'In stock';
  }

  factory InventoryMaterial.fromJson(Map<String, dynamic> json) {
    return InventoryMaterial(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sku: json['sku'] as String?,
      unit: json['unit']?.toString() ?? 'pcs',
      quantityOnHand: _toDouble(json['quantityOnHand']),
      reorderLevel: _toDouble(json['reorderLevel']),
      supplier: json['supplier'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
