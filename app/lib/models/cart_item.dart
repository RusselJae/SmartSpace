import 'product.dart';

class CartItem {
  final String? id;
  final Product product;
  final int quantity;
  final double unitPrice;
  final String? notes;

  CartItem({
    this.id,
    required this.product,
    required this.quantity,
    double? unitPrice,
    this.notes,
  }) : unitPrice = unitPrice ?? product.price;

  double get subtotal => unitPrice * quantity;

  CartItem copyWith({
    String? id,
    Product? product,
    int? quantity,
    double? unitPrice,
    String? notes,
  }) {
    return CartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product.toJson(),
      'quantity': quantity,
      'unitPrice': unitPrice,
      'notes': notes,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final productJson = json['product'];
    final product = productJson is Map<String, dynamic>
        ? Product.fromJson(productJson)
        : Product.fromJson(Map<String, dynamic>.from(productJson as Map));
    return CartItem(
      id: json['id'] as String?,
      product: product,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? product.price,
      notes: json['notes'] as String?,
    );
  }
}











