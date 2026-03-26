import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import 'mysql_database_service.dart';

class CartService extends ChangeNotifier {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  static const String _storagePrefix = 'cart_items_';

  final Map<String, CartItem> _itemsById = {};
  final MySQLDatabaseService _db = MySQLDatabaseService();
  SharedPreferences? _prefs;
  String? _userId;
  bool _hydrated = false;

  List<CartItem> get items => _itemsById.values.toList(growable: false);
  int get totalQuantity => _itemsById.values.fold(0, (sum, item) => sum + item.quantity);
  /// Returns the number of unique products in the cart (not total quantity)
  int get productCount => _itemsById.length;
  double get totalPrice => _itemsById.values.fold(0.0, (sum, item) => sum + item.subtotal);
  bool get isHydrated => _hydrated;

  static const String _guestStorageKey = 'cart_items_guest';

  Future<void> syncWithUser(String? userId) async {
    _prefs ??= await SharedPreferences.getInstance();
    final sameUser = _userId == userId && _hydrated;
    if (sameUser) return;

    final previousUserId = _userId;

    // Before clearing: when switching to guest (logout), persist current cart to guest storage.
    if (userId == null && previousUserId != null && _itemsById.isNotEmpty) {
      final payload = _itemsById.values.map((item) => item.toJson()).toList();
      await _prefs!.setString(_guestStorageKey, jsonEncode(payload));
    }

    _userId = userId;
    _itemsById.clear();

    if (userId == null) {
      await _restoreGuestCart();
      _hydrated = true;
      notifyListeners();
      return;
    }

    var restored = false;
    if (_db.isConnected) {
      try {
        final remoteItems = await _db.getCartItems(userId);
        for (final item in remoteItems) {
          _itemsById[item.product.id] = item;
        }
        restored = true;
      } catch (_) {
        // swallow and fall back to local cache
      }
    }
    if (!restored) {
      await _restoreFromLocal(userId);
    }
    await _persistLocal();
    _hydrated = true;
    notifyListeners();
  }

  void add(Product product, {int quantity = 1}) {
    final maxQty = product.inventoryQty.clamp(1, 999999);
    final delta = (quantity < 1 ? 1 : quantity).clamp(1, maxQty);
    final existing = _itemsById[product.id];
    if (existing == null) {
      _itemsById[product.id] = CartItem(product: product, quantity: delta);
      _saveSnapshot();
      notifyListeners();
      _syncRemoteAdd(product.id, delta);
    } else {
      final newQty = (existing.quantity + delta).clamp(1, maxQty);
      final actualDelta = newQty - existing.quantity;
      if (actualDelta > 0) {
        _itemsById[product.id] = existing.copyWith(quantity: newQty);
        _saveSnapshot();
        notifyListeners();
        _syncRemoteAdd(product.id, actualDelta);
      }
    }
  }

  void increment(String productId) {
    final existing = _itemsById[productId];
    if (existing == null) return;
    final maxQty = existing.product.inventoryQty.clamp(1, 999999);
    if (existing.quantity >= maxQty) return;
    _itemsById[productId] = existing.copyWith(quantity: existing.quantity + 1);
    _saveSnapshot();
    notifyListeners();
    _syncRemoteAdd(productId, 1);
  }

  void decrement(String productId) {
    final existing = _itemsById[productId];
    if (existing != null) {
      final nextQty = existing.quantity - 1;
      if (nextQty <= 0) {
        _itemsById.remove(productId);
        _syncRemoteRemove(productId);
      } else {
        _itemsById[productId] = existing.copyWith(quantity: nextQty);
        _syncRemoteSet(productId, nextQty);
      }
      _saveSnapshot();
      notifyListeners();
    }
  }

  void remove(String productId) {
    if (_itemsById.remove(productId) != null) {
      _saveSnapshot();
      notifyListeners();
      _syncRemoteRemove(productId);
    }
  }

  void clear() {
    if (_itemsById.isNotEmpty) {
      _itemsById.clear();
      _saveSnapshot();
      _syncRemoteClear();
      notifyListeners();
    } else if (_userId == null) {
      notifyListeners();
    }
  }

  Future<void> _restoreFromLocal(String userId) async {
    try {
      final raw = _prefs!.getString('$_storagePrefix$userId');
      if (raw == null) return;
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      for (final entry in decoded) {
        final map = Map<String, dynamic>.from(entry as Map);
        final productMap = Map<String, dynamic>.from(map['product'] as Map);
        final product = Product.fromJson(productMap);
        _itemsById[product.id] = CartItem(
          id: map['id'] as String?,
          product: product,
          quantity: (map['quantity'] as num?)?.toInt() ?? 1,
          unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? product.price,
          notes: map['notes'] as String?,
        );
      }
    } catch (_) {
      // ignore malformed cache
    }
  }

  Future<void> _persistLocal() async {
    _prefs ??= await SharedPreferences.getInstance();
    final key = _userId != null ? '$_storagePrefix$_userId' : _guestStorageKey;
    if (_itemsById.isEmpty) {
      await _prefs!.remove(key);
      return;
    }
    final payload = _itemsById.values.map((item) => item.toJson()).toList();
    await _prefs!.setString(key, jsonEncode(payload));
  }

  Future<void> _restoreGuestCart() async {
    try {
      final raw = _prefs!.getString(_guestStorageKey);
      if (raw == null) return;
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      for (final entry in decoded) {
        final map = Map<String, dynamic>.from(entry as Map);
        final productMap = Map<String, dynamic>.from(map['product'] as Map);
        final product = Product.fromJson(productMap);
        _itemsById[product.id] = CartItem(
          id: map['id'] as String?,
          product: product,
          quantity: (map['quantity'] as num?)?.toInt() ?? 1,
          unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? product.price,
          notes: map['notes'] as String?,
        );
      }
    } catch (_) {
      // ignore malformed cache
    }
  }

  void _saveSnapshot() {
    unawaited(_persistLocal());
  }

  void _syncRemoteAdd(String productId, int quantity) {
    final userId = _userId;
    if (userId == null || !_db.isConnected) return;
    final future = _db.addCartItem(userId: userId, productId: productId, quantity: quantity);
    future.catchError((error) {
      // Silently handle errors - cart sync failures shouldn't break the app
      debugPrint('Cart sync error: $error');
      // Re-throw to satisfy return type, but we're using unawaited so it won't matter
      throw error;
    });
    unawaited(future);
  }

  void _syncRemoteSet(String productId, int quantity) {
    final userId = _userId;
    if (userId == null || !_db.isConnected) return;
    unawaited(
      _db
          .setCartItemQuantity(userId: userId, productId: productId, quantity: quantity)
          .catchError((error) {
        debugPrint('Cart sync error: $error');
        // Return null which is valid for Future<CartItem?>
        return null;
      }),
    );
  }

  void _syncRemoteRemove(String productId) {
    final userId = _userId;
    if (userId == null || !_db.isConnected) return;
    unawaited(
      _db.removeCartItem(userId: userId, productId: productId).catchError((error) {
        debugPrint('Cart sync error: $error');
        // void return is fine here
      }),
    );
  }

  void _syncRemoteClear() {
    final userId = _userId;
    if (userId == null || !_db.isConnected) return;
    unawaited(
      _db.clearCart(userId).catchError((error) {
        debugPrint('Cart sync error: $error');
        // void return is fine here
      }),
    );
  }
}











