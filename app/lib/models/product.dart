class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String category;
  final String style;
  final String material;
  final String color;
  final String size;
  final String modelPath; // Path to 3D model file
  final List<String> imageUrls;
  final double rating;
  final int reviewCount;
  final bool isPopular;
  final bool isNewArrival;
  final bool inStock;
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
    required this.size,
    required this.modelPath,
    required this.imageUrls,
    required this.rating,
    required this.reviewCount,
    required this.isPopular,
    required this.isNewArrival,
    required this.inStock,
    required this.createdAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      category: json['category'] as String,
      style: json['style'] as String,
      material: json['material'] as String,
      color: json['color'] as String,
      size: json['size'] as String,
      modelPath: json['modelPath'] as String,
      imageUrls: List<String>.from(json['imageUrls'] as List),
      rating: (json['rating'] as num).toDouble(),
      reviewCount: json['reviewCount'] as int,
      isPopular: json['isPopular'] as bool,
      isNewArrival: json['isNewArrival'] as bool,
      inStock: json['inStock'] as bool,
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
      'size': size,
      'modelPath': modelPath,
      'imageUrls': imageUrls,
      'rating': rating,
      'reviewCount': reviewCount,
      'isPopular': isPopular,
      'isNewArrival': isNewArrival,
      'inStock': inStock,
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
    String? size,
    String? modelPath,
    List<String>? imageUrls,
    double? rating,
    int? reviewCount,
    bool? isPopular,
    bool? isNewArrival,
    bool? inStock,
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
      size: size ?? this.size,
      modelPath: modelPath ?? this.modelPath,
      imageUrls: imageUrls ?? this.imageUrls,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      isPopular: isPopular ?? this.isPopular,
      isNewArrival: isNewArrival ?? this.isNewArrival,
      inStock: inStock ?? this.inStock,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}













