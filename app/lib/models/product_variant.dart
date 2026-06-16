/// Sellable size/dimension option for a catalog product, with its own BOM.
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    this.dimensionsLabel,
    this.priceAdjustment = 0,
    this.isDefault = false,
    this.realWidthM,
    this.realHeightM,
    this.realDepthM,
    this.modelBaseScale = 1,
    this.bomLines = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String productId;
  final String name;
  final String? dimensionsLabel;
  final double priceAdjustment;
  final bool isDefault;
  final double? realWidthM;
  final double? realHeightM;
  final double? realDepthM;
  final double modelBaseScale;
  final List<ProductVariantBomLine> bomLines;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    final rawBom = json['bomLines'];
    final bom = rawBom is List
        ? rawBom
            .whereType<Map>()
            .map((e) => ProductVariantBomLine.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ProductVariantBomLine>[];

    return ProductVariant(
      id: json['id']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      dimensionsLabel: json['dimensionsLabel'] as String?,
      priceAdjustment: _toDouble(json['priceAdjustment']),
      isDefault: json['isDefault'] == true,
      realWidthM: _toNullableDouble(json['realWidthM']),
      realHeightM: _toNullableDouble(json['realHeightM']),
      realDepthM: _toNullableDouble(json['realDepthM']),
      modelBaseScale: _toDouble(json['modelBaseScale'], fallback: 1),
      bomLines: bom,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toWriteJson() {
    return {
      'name': name,
      if (dimensionsLabel != null) 'dimensionsLabel': dimensionsLabel,
      'priceAdjustment': priceAdjustment,
      'isDefault': isDefault,
      'realWidthM': realWidthM,
      'realHeightM': realHeightM,
      'realDepthM': realDepthM,
      'modelBaseScale': modelBaseScale,
      'bomLines': bomLines
          .where((line) => line.inventoryMaterialId.isNotEmpty && line.quantityRequired > 0)
          .map((line) => line.toWriteJson())
          .toList(),
    };
  }

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class ProductVariantBomLine {
  const ProductVariantBomLine({
    required this.id,
    required this.variantId,
    required this.inventoryMaterialId,
    required this.materialName,
    this.materialSku,
    required this.materialUnit,
    required this.quantityRequired,
  });

  final String id;
  final String variantId;
  final String inventoryMaterialId;
  final String materialName;
  final String? materialSku;
  final String materialUnit;
  final double quantityRequired;

  factory ProductVariantBomLine.fromJson(Map<String, dynamic> json) {
    return ProductVariantBomLine(
      id: json['id']?.toString() ?? '',
      variantId: json['variantId']?.toString() ?? '',
      inventoryMaterialId: json['inventoryMaterialId']?.toString() ?? '',
      materialName: json['materialName']?.toString() ?? '',
      materialSku: json['materialSku'] as String?,
      materialUnit: json['materialUnit']?.toString() ?? 'pcs',
      quantityRequired: ProductVariant._toDouble(json['quantityRequired']),
    );
  }

  Map<String, dynamic> toWriteJson() {
    return {
      'inventoryMaterialId': inventoryMaterialId,
      'quantityRequired': quantityRequired,
    };
  }
}
