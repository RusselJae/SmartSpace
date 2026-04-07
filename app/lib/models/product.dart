import '../utils/model_path_helper.dart';

class ProductSetComponent {
  final String name;
  final int quantity;
  final double widthMeters;
  final double heightMeters;
  final double depthMeters;
  final String? modelPath;
  final String? notes;

  const ProductSetComponent({
    required this.name,
    required this.quantity,
    required this.widthMeters,
    required this.heightMeters,
    required this.depthMeters,
    this.modelPath,
    this.notes,
  });

  factory ProductSetComponent.fromJson(Map<String, dynamic> json) {
    return ProductSetComponent(
      name: (json['name'] ?? '').toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      widthMeters: (json['widthM'] as num?)?.toDouble() ?? 0,
      heightMeters: (json['heightM'] as num?)?.toDouble() ?? 0,
      depthMeters: (json['depthM'] as num?)?.toDouble() ?? 0,
      modelPath: (json['modelPath'] as String?)?.trim().isEmpty == true
          ? null
          : (json['modelPath'] as String?),
      notes: (json['notes'] as String?)?.trim().isEmpty == true
          ? null
          : (json['notes'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'widthM': widthMeters,
      'heightM': heightMeters,
      'depthM': depthMeters,
      if (modelPath != null) 'modelPath': modelPath,
      if (notes != null) 'notes': notes,
    };
  }
}

class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String category;
  final String style;
  final String material;
  final String color;
  final String modelPath; // Path to 3D model file
  final List<ProductSetComponent> components; // Optional per-piece dimensions for set products.
  final double? realWidthMeters;
  final double? realHeightMeters;
  final double? realDepthMeters;
  final double modelBaseScale;
  final List<String> imageUrls;
  final double rating;
  final int reviewCount;
  final int? orderCount; // Number of orders for this product (for best seller sorting)
  final bool isPopular;
  final bool isNewArrival;
  final bool inStock;
  final int inventoryQty;
  final bool isArchived;
  final DateTime createdAt;

  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.style,
    required this.material,
    required this.color,
    required this.modelPath,
    this.components = const [],
    required this.realWidthMeters,
    required this.realHeightMeters,
    required this.realDepthMeters,
    required this.modelBaseScale,
    required this.imageUrls,
    required this.rating,
    required this.reviewCount,
    this.orderCount,
    required this.isPopular,
    required this.isNewArrival,
    required this.inStock,
    required this.inventoryQty,
    this.isArchived = false,
    required this.createdAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawImages = List<String>.from(json['imageUrls'] as List);
    final rawComponents = (json['components'] as List?) ?? const [];
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      category: json['category'] as String,
      style: json['style'] as String,
      material: json['material'] as String,
      color: json['color'] as String,
      // Resolve `/uploads/...` against the same API origin the app uses (critical on phones).
      modelPath: ModelPathHelper.normalize(json['modelPath'] as String),
      components: rawComponents
          .whereType<Map>()
          .map((item) => ProductSetComponent.fromJson(Map<String, dynamic>.from(item)))
          .where((item) =>
              item.name.trim().isNotEmpty &&
              item.quantity > 0 &&
              item.widthMeters > 0 &&
              item.heightMeters > 0 &&
              item.depthMeters > 0)
          .toList(growable: false),
      realWidthMeters: (json['realWidthM'] as num?)?.toDouble(),
      realHeightMeters: (json['realHeightM'] as num?)?.toDouble(),
      realDepthMeters: (json['realDepthM'] as num?)?.toDouble(),
      modelBaseScale: (json['modelBaseScale'] as num?)?.toDouble() ?? 1.0,
      imageUrls: rawImages.map(ModelPathHelper.normalizeImageUrl).toList(),
      rating: (json['rating'] as num).toDouble(),
      reviewCount: json['reviewCount'] as int,
      orderCount: (json['orderCount'] as num?)?.toInt(),
      isPopular: json['isPopular'] as bool,
      isNewArrival: json['isNewArrival'] as bool,
      inStock: json['inStock'] as bool,
      inventoryQty: (json['inventoryQty'] ?? json['inventory_qty'] ?? 0) as int,
      isArchived: (json['isArchived'] ?? json['is_archived'] ?? false) as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'category': category,
      'style': style,
      'material': material,
      'color': color,
      'modelPath': modelPath,
      'components': components.map((c) => c.toJson()).toList(growable: false),
      'realWidthM': realWidthMeters,
      'realHeightM': realHeightMeters,
      'realDepthM': realDepthMeters,
      'modelBaseScale': modelBaseScale,
      'imageUrls': imageUrls,
      'rating': rating,
      'reviewCount': reviewCount,
      if (orderCount != null) 'orderCount': orderCount,
      'isPopular': isPopular,
      'isNewArrival': isNewArrival,
      'inStock': inStock,
      'inventoryQty': inventoryQty,
      'isArchived': isArchived,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Product copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    String? category,
    String? style,
    String? material,
    String? color,
    String? modelPath,
    List<ProductSetComponent>? components,
    double? realWidthMeters,
    double? realHeightMeters,
    double? realDepthMeters,
    double? modelBaseScale,
    List<String>? imageUrls,
    double? rating,
    int? reviewCount,
    int? orderCount,
    bool? isPopular,
    bool? isNewArrival,
    bool? inStock,
    int? inventoryQty,
    bool? isArchived,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      category: category ?? this.category,
      style: style ?? this.style,
      material: material ?? this.material,
      color: color ?? this.color,
      modelPath: modelPath ?? this.modelPath,
      components: components ?? this.components,
      realWidthMeters: realWidthMeters ?? this.realWidthMeters,
      realHeightMeters: realHeightMeters ?? this.realHeightMeters,
      realDepthMeters: realDepthMeters ?? this.realDepthMeters,
      modelBaseScale: modelBaseScale ?? this.modelBaseScale,
      imageUrls: imageUrls ?? this.imageUrls,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      orderCount: orderCount ?? this.orderCount,
      isPopular: isPopular ?? this.isPopular,
      isNewArrival: isNewArrival ?? this.isNewArrival,
      inStock: inStock ?? this.inStock,
      inventoryQty: inventoryQty ?? this.inventoryQty,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}













