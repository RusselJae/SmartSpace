/// Raw material / supply row tracked in the materials inventory panel.
class InventoryMaterial {
  const InventoryMaterial({
    required this.id,
    required this.name,
    this.sku,
    this.materialType = 'Other',
    required this.unit,
    this.costPerUnit = 0,
    required this.quantityOnHand,
    required this.reorderLevel,
    this.supplier,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Material grouping options for admin filtering.
  static const List<String> materialTypes = [
    'Lumber',
    'Hardware',
    'Finishing',
    'Fabric / Upholstery',
    'Foam / Padding',
    'Other',
  ];

  /// Supported inventory units.
  static const List<String> units = [
    'pcs',
    'sheet',
    'bd ft',
    'ml',
    'liter',
    'yard',
    'kg',
    'g',
  ];

  /// Low stock when on-hand is above zero but at or below [reorderLevel].
  static String stockStatusLabelFor({required double quantityOnHand, required double reorderLevel}) {
    if (quantityOnHand <= 0) return 'Out of stock';
    if (quantityOnHand <= reorderLevel) return 'Low stock';
    return 'In stock';
  }

  final String id;
  final String name;
  final String? sku;
  final String materialType;
  final String unit;
  final double costPerUnit;
  final double quantityOnHand;
  final double reorderLevel;
  final String? supplier;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOutOfStock => quantityOnHand <= 0;

  bool get isLowStock => quantityOnHand > 0 && quantityOnHand <= reorderLevel;

  bool get isInStock => quantityOnHand > reorderLevel;

  String get stockStatusLabel =>
      stockStatusLabelFor(quantityOnHand: quantityOnHand, reorderLevel: reorderLevel);

  factory InventoryMaterial.fromJson(Map<String, dynamic> json) {
    return InventoryMaterial(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sku: json['sku'] as String?,
      materialType: json['materialType']?.toString() ?? 'Other',
      unit: json['unit']?.toString() ?? 'pcs',
      costPerUnit: _toDouble(json['costPerUnit']),
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
