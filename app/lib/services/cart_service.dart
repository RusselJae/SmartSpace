import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/cart_item.dart';

class CartService extends ChangeNotifier {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  final Map<String, CartItem> _itemsById = {};

  List<CartItem> get items => _itemsById.values.toList(growable: false);
  int get totalQuantity => _itemsById.values.fold(0, (sum, item) => sum + item.quantity);
  double get totalPrice => _itemsById.values.fold(0.0, (sum, item) => sum + item.subtotal);

  void add(Product product, {int quantity = 1}) {
    final existing = _itemsById[product.id];
    if (existing == null) {
      _itemsById[product.id] = CartItem(product: product, quantity: quantity);
    } else {
      _itemsById[product.id] = existing.copyWith(quantity: existing.quantity + quantity);
    }
    notifyListeners();
  }

  void increment(String productId) {
    final existing = _itemsById[productId];
    if (existing != null) {
      _itemsById[productId] = existing.copyWith(quantity: existing.quantity + 1);
      notifyListeners();
    }
  }

  void decrement(String productId) {
    final existing = _itemsById[productId];
    if (existing != null) {
      final nextQty = existing.quantity - 1;
      if (nextQty <= 0) {
        _itemsById.remove(productId);
      } else {
        _itemsById[productId] = existing.copyWith(quantity: nextQty);
      }
      notifyListeners();
    }
  }

  void remove(String productId) {
    if (_itemsById.remove(productId) != null) {
      notifyListeners();
    }
  }

  void clear() {
    if (_itemsById.isNotEmpty) {
      _itemsById.clear();
      notifyListeners();
    }
  }
}











