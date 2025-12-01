import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/address_entry.dart';
import '../models/admin.dart';
import '../models/cart_item.dart';
import '../models/order_record.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../models/user.dart';

/// Service that now talks to the Node.js API and falls back to mock data if needed.
class MySQLDatabaseService {
  static final MySQLDatabaseService _instance = MySQLDatabaseService._internal();
  factory MySQLDatabaseService() => _instance;
  MySQLDatabaseService._internal();

  final http.Client _client = http.Client();
  final Random _random = Random();
  bool _useApi = false;

  final List<Product> _mockProducts = [];
  final List<User> _mockUsers = [];
  final List<OrderRecord> _mockOrders = [];
  final Map<String, List<CartItem>> _mockCartByUser = {};

  bool get isConnected => _useApi;

  String get connectionStatus {
    if (_useApi) {
      return 'Connected to API at ${ApiConfig.baseUrl}';
    }
    return 'Using mock data (API unavailable)';
  }

  Future<void> initialize() async {
    _useApi = await _checkApiAvailability();
    if (!_useApi) {
      developer.log('API unavailable, using mock data');
      _initializeMockData();
    }
  }

  /// Manually retry API connection (useful for troubleshooting)
  Future<bool> retryConnection() async {
    developer.log('🔄 Retrying API connection...');
    _useApi = await _checkApiAvailability();
    if (!_useApi) {
      developer.log('API still unavailable after retry');
      _initializeMockData();
    }
    return _useApi;
  }

  Future<bool> _checkApiAvailability() async {
    final uri = _buildUri('/health');
    developer.log('🔍 Checking API availability at: $uri');
    try {
      final response = await _client.get(uri).timeout(ApiConfig.timeout);
      developer.log('📡 API response status: ${response.statusCode}');
      developer.log('📡 API response body: ${response.body}');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        developer.log('📦 Decoded response: $decoded');
        
        // Check if response has the expected format
        if (decoded['success'] == true) {
          final data = decoded['data'] as Map<String, dynamic>?;
          if (data != null) {
            final dbStatus = data['database'] as String?;
            developer.log('🗄️ Database status: $dbStatus');
            final isConnected = dbStatus == 'connected';
            if (isConnected) {
              developer.log('✅ API is connected and database is ready');
            } else {
              developer.log('❌ API responded but database is disconnected');
              developer.log('💡 Check backend logs - MySQL connection might be failing');
            }
            return isConnected;
          } else {
            developer.log('⚠️ API responded but missing data field');
            developer.log('💡 Response format: $decoded');
            // If it's the root route response, try to be helpful
            if (decoded.containsKey('message')) {
              developer.log('💡 You might be hitting the root route instead of /api/health');
              developer.log('💡 Make sure you\'re using: ${ApiConfig.baseUrl}/health');
            }
          }
        } else {
          developer.log('❌ API returned success: false');
        }
      } else {
        developer.log('❌ API returned status code: ${response.statusCode}');
      }
    } catch (error) {
      developer.log('❌ API health check failed: $error');
      developer.log('💡 Make sure backend is running at ${ApiConfig.baseUrl}');
      developer.log('💡 Test in browser: ${ApiConfig.baseUrl}/health');
    }
    return false;
  }

  Uri _buildUri(String path) {
    final normalizedBase = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};

  Future<dynamic> _sendRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(path);
    final encodedBody = body == null ? null : jsonEncode(body);
    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri).timeout(ApiConfig.timeout);
        break;
      case 'POST':
        response =
            await _client.post(uri, headers: _jsonHeaders, body: encodedBody).timeout(ApiConfig.timeout);
        break;
      case 'PUT':
        response =
            await _client.put(uri, headers: _jsonHeaders, body: encodedBody).timeout(ApiConfig.timeout);
        break;
      case 'PATCH':
        response =
            await _client.patch(uri, headers: _jsonHeaders, body: encodedBody).timeout(ApiConfig.timeout);
        break;
      case 'DELETE':
        response = await _client.delete(uri, headers: _jsonHeaders).timeout(ApiConfig.timeout);
        break;
      default:
        throw UnsupportedError('Unsupported HTTP method $method');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API request failed (${response.statusCode}): ${response.body}');
    }

    if (response.statusCode == 204 || response.body.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      if (decoded['success'] == false) {
        throw Exception(decoded['message']?.toString() ?? 'API request failed');
      }
      if (decoded.containsKey('data')) {
        return decoded['data'];
      }
    }
    return decoded;
  }

  List<Map<String, dynamic>> _asMapList(dynamic value, String context) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    throw Exception('Invalid $context payload');
  }

  Map<String, dynamic> _asMap(dynamic value, String context) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    throw Exception('Invalid $context payload');
  }

  Map<String, dynamic> _productPayload({
    required String name,
    required String description,
    required double price,
    required String category,
    required String style,
    required String material,
    required String color,
    required String size,
    required String modelPath,
    required List<String> imageUrls,
    int? inventoryQty,
    required bool isPopular,
    required bool isNewArrival,
    required bool inStock,
  }) {
    return {
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
      if (inventoryQty != null) 'inventoryQty': inventoryQty,
      'isPopular': isPopular,
      'isNewArrival': isNewArrival,
      'inStock': inStock,
    };
  }

  CartItem _cartItemFromMap(Map<String, dynamic> map) {
    final productMap = _asMap(map['product'], 'cart.product');
    final product = Product.fromJson(productMap);
    return CartItem(
      id: map['id'] as String?,
      product: product,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? product.price,
      notes: map['notes'] as String?,
    );
  }

  List<CartItem> _mockCartForUser(String userId) {
    return _mockCartByUser.putIfAbsent(userId, () => <CartItem>[]);
  }

  Product _findMockProduct(String productId) {
    if (_mockProducts.isEmpty) {
      _initializeMockData();
    }
    return _mockProducts.firstWhere(
      (product) => product.id == productId,
      orElse: () => throw Exception('Product not found'),
    );
  }

  Future<List<Product>> getAllProducts() async {
    if (!_useApi) {
      developer.log('⚠️ Using MOCK data for products (API not connected)');
      _initializeMockData();
      return List.unmodifiable(_mockProducts);
    }
    developer.log('📡 Fetching products from API...');
    final data = await _sendRequest(method: 'GET', path: '/products');
    final list = _asMapList(data, 'products');
    final products = list.map(Product.fromJson).toList();
    developer.log('✅ Loaded ${products.length} products from database');
    return products;
  }

  Future<List<Product>> getPopularProducts() async {
    final products = await getAllProducts();
    return products.where((product) => product.isPopular).toList();
  }

  Future<List<Product>> getNewArrivalProducts() async {
    final products = await getAllProducts();
    return products.where((product) => product.isNewArrival).toList();
  }

  Future<Product> createProduct({
    required String name,
    required String description,
    required double price,
    required String category,
    required String style,
    required String material,
    required String color,
    required String size,
    required String modelPath,
    List<String> imageUrls = const [],
    int? inventoryQty,
    bool isPopular = false,
    bool isNewArrival = false,
    bool inStock = true,
  }) async {
    if (!_useApi) {
      developer.log('⚠️ Creating product in MOCK MODE - data will NOT be saved to database!');
      developer.log('💡 Make sure your backend is running at ${ApiConfig.baseUrl}');
      final product = Product(
        id: _generateId('p'),
        name: name,
        description: description,
        price: price,
        category: category,
        style: style,
        material: material,
        color: color,
        size: size,
        modelPath: modelPath,
        imageUrls: List.unmodifiable(imageUrls),
        rating: 0,
        reviewCount: 0,
        isPopular: isPopular,
        isNewArrival: isNewArrival,
        inStock: inStock,
        inventoryQty: inventoryQty ?? (inStock ? 10 : 0),
        createdAt: DateTime.now(),
      );
      _mockProducts.insert(0, product);
      return product;
    }
    developer.log('✅ Creating product via API at ${ApiConfig.baseUrl}');
    final payload = _productPayload(
      name: name,
      description: description,
      price: price,
      category: category,
      style: style,
      material: material,
      color: color,
      size: size,
      modelPath: modelPath,
      imageUrls: imageUrls,
      inventoryQty: inventoryQty,
      isPopular: isPopular,
      isNewArrival: isNewArrival,
      inStock: inStock,
    );
    final data = await _sendRequest(method: 'POST', path: '/products', body: payload);
    final map = _asMap(data, 'product');
    return Product.fromJson(map);
  }

  Future<Product?> updateProduct(Product product) async {
    if (!_useApi) {
      final index = _mockProducts.indexWhere((item) => item.id == product.id);
      if (index != -1) {
        _mockProducts[index] = product;
        return product;
      }
      return null;
    }
    final payload = _productPayload(
      name: product.name,
      description: product.description,
      price: product.price,
      category: product.category,
      style: product.style,
      material: product.material,
      color: product.color,
      size: product.size,
      modelPath: product.modelPath,
      imageUrls: product.imageUrls,
      inventoryQty: product.inventoryQty,
      isPopular: product.isPopular,
      isNewArrival: product.isNewArrival,
      inStock: product.inStock,
    );
    final data = await _sendRequest(method: 'PUT', path: '/products/${product.id}', body: payload);
    final map = _asMap(data, 'product');
    return Product.fromJson(map);
  }

  Future<void> deleteProduct(String id) async {
    if (!_useApi) {
      _mockProducts.removeWhere((product) => product.id == id);
      return;
    }
    await _sendRequest(method: 'DELETE', path: '/products/$id');
  }

  Future<List<User>> getAllUsers() async {
    if (!_useApi) {
      developer.log('⚠️ Using MOCK data for users (API not connected)');
      _initializeMockData();
      return List.unmodifiable(_mockUsers);
    }
    developer.log('📡 Fetching users from API...');
    final data = await _sendRequest(method: 'GET', path: '/users');
    final list = _asMapList(data, 'users');
    final users = list.map(User.fromJson).toList();
    developer.log('✅ Loaded ${users.length} users from database');
    return users;
  }

  Future<User> createUser({
    required String email,
    required String fullName,
    String? username,
    String? phoneNumber,
    String? gender,
  }) async {
    if (!_useApi) {
      final user = User(
        id: _generateId('u'),
        email: email,
        fullName: fullName,
        username: username ?? _suggestUsername(fullName, email),
        phoneNumber: phoneNumber,
        gender: gender,
        addresses: const [],
        wishlistProductIds: const [],
        orderIds: const [],
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      _mockUsers.insert(0, user);
      return user;
    }
    final payload = {
      'email': email,
      'fullName': fullName,
      if (username != null && username.isNotEmpty) 'username': username,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (gender != null && gender.isNotEmpty) 'gender': gender,
    };
    final data = await _sendRequest(method: 'POST', path: '/users', body: payload);
    final map = _asMap(data, 'user');
    return User.fromJson(map);
  }

  Future<User> updateUser({
    required String userId,
    String? fullName,
    String? username,
    String? phoneNumber,
    String? gender,
    DateTime? dateOfBirth,
    String? avatarUrl,
  }) async {
    if (!_useApi) {
      developer.log('⚠️ Updating user in MOCK MODE - data will NOT be saved to database!');
      final existing = _mockUsers.firstWhere((u) => u.id == userId, orElse: () => throw Exception('User not found'));
      final updated = existing.copyWith(
        fullName: fullName ?? existing.fullName,
        username: username ?? existing.username,
        phoneNumber: phoneNumber ?? existing.phoneNumber,
        gender: gender ?? existing.gender,
        dateOfBirth: dateOfBirth ?? existing.dateOfBirth,
        avatarUrl: avatarUrl ?? existing.avatarUrl,
      );
      final index = _mockUsers.indexWhere((u) => u.id == userId);
      if (index != -1) {
        _mockUsers[index] = updated;
      }
      return updated;
    }
    final payload = <String, dynamic>{};
    if (fullName != null) payload['fullName'] = fullName;
    if (username != null) payload['username'] = username;
    if (phoneNumber != null) payload['phoneNumber'] = phoneNumber;
    if (gender != null) payload['gender'] = gender;
    if (dateOfBirth != null) payload['dateOfBirth'] = dateOfBirth.toIso8601String();
    if (avatarUrl != null) payload['avatarUrl'] = avatarUrl;
    final data = await _sendRequest(method: 'PATCH', path: '/users/$userId', body: payload);
    final map = _asMap(data, 'user');
    return User.fromJson(map);
  }

  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!_useApi) {
      developer.log('⚠️ Upload avatar in MOCK MODE - returning placeholder URL');
      return 'https://placehold.co/200x200?text=${Uri.encodeComponent(userId)}';
    }
    final uri = _buildUri('/users/$userId/avatar');
    final request = http.MultipartRequest('POST', uri);
    final multipart = http.MultipartFile.fromBytes(
      'avatar',
      bytes,
      filename: fileName,
    );
    request.files.add(multipart);
    final streamed = await request.send().timeout(ApiConfig.timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to upload avatar: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid avatar upload response');
    }
    if (decoded['success'] == false) {
      throw Exception(decoded['message']?.toString() ?? 'Failed to upload avatar');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid avatar upload payload');
    }
    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Avatar upload response missing url');
    }
    return url;
  }

  Future<List<CartItem>> getCartItems(String userId) async {
    if (!_useApi) {
      final cart = List<CartItem>.from(_mockCartForUser(userId));
      return List.unmodifiable(cart);
    }
    final data = await _sendRequest(method: 'GET', path: '/cart/$userId');
    final list = _asMapList(data, 'cart items');
    return list.map(_cartItemFromMap).toList();
  }

  Future<CartItem> addCartItem({
    required String userId,
    required String productId,
    int quantity = 1,
    String? notes,
  }) async {
    if (!_useApi) {
      final cart = _mockCartForUser(userId);
      final product = _findMockProduct(productId);
      final index = cart.indexWhere((item) => item.product.id == productId);
      if (index == -1) {
        final item = CartItem(
          id: _generateId('cart'),
          product: product,
          quantity: quantity,
          unitPrice: product.price,
          notes: notes,
        );
        cart.add(item);
        return item;
      }
      final updated = cart[index].copyWith(
        quantity: cart[index].quantity + quantity,
        notes: notes ?? cart[index].notes,
      );
      cart[index] = updated;
      return updated;
    }
    final payload = {
      'userId': userId,
      'productId': productId,
      'quantity': quantity,
      if (notes != null) 'notes': notes,
    };
    final data = await _sendRequest(method: 'POST', path: '/cart', body: payload);
    final map = _asMap(data, 'cart item');
    return _cartItemFromMap(map);
  }

  Future<CartItem?> setCartItemQuantity({
    required String userId,
    required String productId,
    required int quantity,
    String? notes,
  }) async {
    if (!_useApi) {
      final cart = _mockCartForUser(userId);
      final index = cart.indexWhere((item) => item.product.id == productId);
      if (index == -1) return null;
      if (quantity <= 0) {
        cart.removeAt(index);
        return null;
      }
      final updated = cart[index].copyWith(
        quantity: quantity,
        notes: notes ?? cart[index].notes,
      );
      cart[index] = updated;
      return updated;
    }
    final payload = {
      'userId': userId,
      'productId': productId,
      'quantity': quantity,
      if (notes != null) 'notes': notes,
    };
    final data = await _sendRequest(method: 'PATCH', path: '/cart', body: payload);
    if (data == null) return null;
    final map = _asMap(data, 'cart item');
    return _cartItemFromMap(map);
  }

  Future<void> removeCartItem({
    required String userId,
    required String productId,
  }) async {
    if (!_useApi) {
      final cart = _mockCartForUser(userId);
      cart.removeWhere((item) => item.product.id == productId);
      return;
    }
    await _sendRequest(method: 'DELETE', path: '/cart/$userId/$productId');
  }

  Future<void> clearCart(String userId) async {
    if (!_useApi) {
      _mockCartByUser[userId] = [];
      return;
    }
    await _sendRequest(method: 'DELETE', path: '/cart/$userId');
  }

  Future<List<OrderRecord>> getAllOrders() async {
    if (!_useApi) {
      developer.log('⚠️ Using MOCK data for orders (API not connected)');
      _initializeMockData();
      return List.unmodifiable(_mockOrders);
    }
    developer.log('📡 Fetching orders from API...');
    final data = await _sendRequest(method: 'GET', path: '/orders');
    final list = _asMapList(data, 'orders');
    final orders = list.map(OrderRecord.fromJson).toList();
    developer.log('✅ Loaded ${orders.length} orders from database');
    return orders;
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    if (!_useApi) {
      final index = _mockOrders.indexWhere((order) => order.id == orderId);
      if (index != -1) {
        final existing = _mockOrders[index];
        _mockOrders[index] = OrderRecord(
          id: existing.id,
          userId: existing.userId,
          userName: existing.userName,
          productIds: existing.productIds,
          totalAmount: existing.totalAmount,
          status: status,
          shippingAddress: existing.shippingAddress,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now(),
        );
      }
      return;
    }
    await _sendRequest(
      method: 'PATCH',
      path: '/orders/$orderId/status',
      body: {'status': status},
    );
  }

  Future<OrderRecord> createOrder({
    required String userId,
    required String userName,
    required List<String> productIds,
    required double totalAmount,
    required Map<String, dynamic> shippingAddress,
    String status = 'pending',
  }) async {
    if (!_useApi) {
      return _createLocalOrder(
        userId: userId,
        userName: userName,
        productIds: productIds,
        totalAmount: totalAmount,
        status: status,
        shippingAddress: shippingAddress,
      );
    }

    final payload = {
      'userId': userId,
      'userName': userName,
      'productIds': productIds,
      'totalAmount': totalAmount,
      'status': status,
      'shippingAddress': shippingAddress,
    };
    try {
      final data = await _sendRequest(method: 'POST', path: '/orders', body: payload);
      final map = _asMap(data, 'order');
      return OrderRecord.fromJson(map);
    } catch (error) {
      developer.log('❌ Failed to create order via API: $error');
      developer.log('⚠️ Falling back to local order creation');
      return _createLocalOrder(
        userId: userId,
        userName: userName,
        productIds: productIds,
        totalAmount: totalAmount,
        status: status,
        shippingAddress: shippingAddress,
      );
    }
  }

  OrderRecord _createLocalOrder({
    required String userId,
    required String userName,
    required List<String> productIds,
    required double totalAmount,
    required String status,
    required Map<String, dynamic> shippingAddress,
  }) {
    final order = OrderRecord(
      id: _generateId('o'),
      userId: userId,
      userName: userName,
      productIds: List.unmodifiable(productIds),
      totalAmount: totalAmount,
      status: status,
      shippingAddress: Map<String, dynamic>.from(shippingAddress),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _mockOrders.insert(0, order);
    return order;
  }

  Future<List<AddressEntry>> getAddresses(String userId) async {
    if (!_useApi) {
      developer.log('⚠️ Using MOCK data for addresses (API not connected)');
      return [];
    }
    developer.log('📡 Fetching addresses from API for user: $userId');
    final data = await _sendRequest(method: 'GET', path: '/addresses/$userId');
    final list = _asMapList(data, 'addresses');
    final addresses = list.map((map) => AddressEntry.fromJson(map)).toList();
    developer.log('✅ Loaded ${addresses.length} addresses from database for user: $userId');
    return addresses;
  }

  Future<AddressEntry> createAddress({
    required String userId,
    required String fullName,
    required String phoneNumber,
    required String region,
    required String street,
    String? postalCode,
    String label = 'Home',
    bool isDefault = false,
  }) async {
    if (!_useApi) {
      developer.log('⚠️ Creating address in MOCK MODE - data will NOT be saved to database!');
      return AddressEntry(
        id: _generateId('addr'),
        fullName: fullName,
        phoneNumber: phoneNumber,
        region: region,
        postalCode: postalCode ?? '',
        street: street,
        label: label,
        isDefault: isDefault,
      );
    }
    developer.log('✅ Creating address via API for user: $userId');
    final payload = {
      'userId': userId,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'region': region,
      'street': street,
      if (postalCode != null) 'postalCode': postalCode,
      'label': label,
      'isDefault': isDefault,
    };
    final data = await _sendRequest(method: 'POST', path: '/addresses', body: payload);
    final map = _asMap(data, 'address');
    return AddressEntry.fromJson(map);
  }

  Future<AddressEntry> updateAddress({
    required String addressId,
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? region,
    String? street,
    String? postalCode,
    String? label,
    bool? isDefault,
  }) async {
    if (!_useApi) {
      developer.log('⚠️ Updating address in MOCK MODE - data will NOT be saved to database!');
      return AddressEntry(
        id: addressId,
        fullName: fullName ?? '',
        phoneNumber: phoneNumber ?? '',
        region: region ?? '',
        postalCode: postalCode ?? '',
        street: street ?? '',
        label: label ?? 'Home',
        isDefault: isDefault ?? false,
      );
    }
    developer.log('✅ Updating address via API: $addressId');
    final payload = <String, dynamic>{
      'userId': userId,
      if (fullName != null) 'fullName': fullName,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (region != null) 'region': region,
      if (street != null) 'street': street,
      if (postalCode != null) 'postalCode': postalCode,
      if (label != null) 'label': label,
      if (isDefault != null) 'isDefault': isDefault,
    };
    final data = await _sendRequest(method: 'PATCH', path: '/addresses/$addressId', body: payload);
    final map = _asMap(data, 'address');
    return AddressEntry.fromJson(map);
  }

  Future<void> deleteAddress(String addressId, String userId) async {
    if (!_useApi) {
      developer.log('⚠️ Deleting address in MOCK MODE - data will NOT be saved to database!');
      return;
    }
    developer.log('✅ Deleting address via API: $addressId');
    await _sendRequest(
      method: 'DELETE',
      path: '/addresses/$addressId',
      body: {'userId': userId},
    );
  }

  Future<List<Review>> getAllReviews() async {
    if (!_useApi) {
      developer.log('⚠️ Using MOCK data for reviews (API not connected)');
      return _getMockReviews();
    }
    developer.log('📡 Fetching reviews from API...');
    final data = await _sendRequest(method: 'GET', path: '/reviews');
    final list = _asMapList(data, 'reviews');
    final reviews = list.map(Review.fromJson).toList();
    developer.log('✅ Loaded ${reviews.length} reviews from database');
    return reviews;
  }

  Future<Review> createReview({
    required String productId,
    required String productName,
    required String userId,
    required String userName,
    required int rating,
    required String content,
  }) async {
    if (!_useApi) {
      return Review(
        id: _generateId('r'),
        productId: productId,
        productName: productName,
        userId: userId,
        userName: userName,
        rating: rating,
        content: content,
        status: 'pending',
        createdAt: DateTime.now(),
      );
    }
    final payload = {
      'productId': productId,
      'productName': productName,
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'content': content,
    };
    final data = await _sendRequest(method: 'POST', path: '/reviews', body: payload);
    final map = _asMap(data, 'review');
    return Review.fromJson(map);
  }

  Future<void> updateReviewStatus(String reviewId, String status) async {
    if (!_useApi) {
      return;
    }
    await _sendRequest(
      method: 'PATCH',
      path: '/reviews/$reviewId/status',
      body: {'status': status},
    );
  }

  Future<void> deleteReview(String reviewId) async {
    if (!_useApi) {
      return;
    }
    await _sendRequest(method: 'DELETE', path: '/reviews/$reviewId');
  }

  String _suggestUsername(String fullName, String email) {
    final normalizedName = fullName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (normalizedName.isNotEmpty) {
      return normalizedName.length >= 3 ? normalizedName : '$normalizedName${_random.nextInt(999)}';
    }
    final emailPrefix = email.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (emailPrefix.isNotEmpty) {
      return emailPrefix;
    }
    return 'user_${_random.nextInt(9999)}';
  }

  String _generateId(String prefix) {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final rand = _random.nextInt(9999).toString().padLeft(4, '0');
    return '$prefix$millis$rand';
  }

  void _initializeMockData() {
    if (_mockProducts.isNotEmpty) {
      return;
    }
    final now = DateTime.now();
    _mockProducts.addAll([
      Product(
        id: 'p1',
        name: 'Modern Dining Chair',
        description: 'Elegant wooden dining chair with comfortable cushioning',
        price: 299.99,
        category: 'Dining',
        style: 'Modern',
        material: 'Wood',
        color: 'Brown',
        size: 'M',
        modelPath: 'assets/chair.glb',
        imageUrls: const [],
        rating: 4.5,
        reviewCount: 128,
        isPopular: true,
        isNewArrival: false,
        inStock: true,
        inventoryQty: 15,
        createdAt: now.subtract(const Duration(days: 30)),
      ),
      Product(
        id: 'p2',
        name: 'Executive Office Chair',
        description: 'Premium leather office chair with ergonomic design',
        price: 599.99,
        category: 'Office',
        style: 'Classic',
        material: 'Leather',
        color: 'Black',
        size: 'L',
        modelPath: 'assets/chair.glb',
        imageUrls: const [],
        rating: 4.8,
        reviewCount: 89,
        isPopular: true,
        isNewArrival: true,
        inStock: true,
        inventoryQty: 8,
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ]);
    if (_mockUsers.isEmpty) {
      _mockUsers.addAll([
        User(
          id: 'u1',
          email: 'jane.appleseed@example.com',
          fullName: 'Jane Appleseed',
          username: 'jane_appleseed',
          phoneNumber: '+1 555 0100',
          gender: 'female',
          addresses: const ['123 Maple St, Springfield'],
          wishlistProductIds: const ['p1'],
          orderIds: const ['o1'],
          preferredStyle: 'Modern',
          minBudget: 100,
          maxBudget: 2000,
          createdAt: now.subtract(const Duration(days: 40)),
          lastLoginAt: now.subtract(const Duration(hours: 3)),
        ),
        User(
          id: 'u2',
          email: 'marcus.tan@example.com',
          fullName: 'Marcus Tan',
          username: 'marcus_tan',
          phoneNumber: '+65 8000 1234',
          gender: 'male',
          addresses: const ['55 River Valley Rd, Singapore'],
          wishlistProductIds: const ['p2'],
          orderIds: const ['o2'],
          preferredStyle: 'Minimal',
          minBudget: 200,
          maxBudget: 5000,
          createdAt: now.subtract(const Duration(days: 60)),
          lastLoginAt: now.subtract(const Duration(hours: 10)),
        ),
      ]);
    }
    if (_mockOrders.isEmpty) {
      _mockOrders.addAll([
        OrderRecord(
          id: 'o1',
          userId: 'u1',
          userName: 'Jane Appleseed',
          productIds: const ['p1', 'p2'],
          totalAmount: 899.98,
          status: 'pending',
          shippingAddress: const {'line1': '123 Maple St', 'city': 'Springfield', 'country': 'USA'},
          createdAt: now.subtract(const Duration(days: 2)),
          updatedAt: now.subtract(const Duration(days: 1)),
        ),
        OrderRecord(
          id: 'o2',
          userId: 'u2',
          userName: 'Marcus Tan',
          productIds: const ['p2'],
          totalAmount: 599.99,
          status: 'confirmed',
          shippingAddress: const {'line1': '55 River Valley Rd', 'city': 'Singapore', 'country': 'SG'},
          createdAt: now.subtract(const Duration(days: 4)),
          updatedAt: now.subtract(const Duration(days: 3)),
        ),
      ]);
    }
    if (_mockCartByUser.isEmpty && _mockProducts.isNotEmpty) {
      _mockCartByUser['u1'] = [
        CartItem(
          id: _generateId('cart'),
          product: _mockProducts[0],
          quantity: 1,
          unitPrice: _mockProducts[0].price,
        ),
        if (_mockProducts.length > 2)
          CartItem(
            id: _generateId('cart'),
            product: _mockProducts[2],
            quantity: 2,
            unitPrice: _mockProducts[2].price,
          ),
      ];
    }
  }

  List<Review> _getMockReviews() {
    final now = DateTime.now();
    return [
      Review(
        id: 'r1',
        productId: 'p1',
        productName: 'Modern Dining Chair',
        userId: 'u1',
        userName: 'Jane Appleseed',
        rating: 5,
        content: 'Incredible craftsmanship. The chair is both beautiful and comfortable.',
        status: 'published',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      Review(
        id: 'r2',
        productId: 'p2',
        productName: 'Executive Office Chair',
        userId: 'u2',
        userName: 'Marcus Tan',
        rating: 4,
        content: 'Sturdy and elegant. Great for long work sessions.',
        status: 'published',
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      Review(
        id: 'r3',
        productId: 'p1',
        productName: 'Modern Dining Chair',
        userId: 'u2',
        userName: 'Marcus Tan',
        rating: 2,
        content: 'Arrived with scratches on the legs. Otherwise decent quality.',
        status: 'flagged',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ];
  }

  // ============================================================================
  // Admin Management Methods
  // ============================================================================

  /// Fetches all admins from the API.
  /// Returns an empty list if API is unavailable (no mock fallback for security).
  Future<List<Admin>> getAllAdmins() async {
    if (!_useApi) {
      developer.log('⚠️ Admin management requires API connection');
      return const [];
    }
    developer.log('📡 Fetching admins from API...');
    final data = await _sendRequest(method: 'GET', path: '/admins');
    final list = _asMapList(data, 'admins');
    final admins = list.map(Admin.fromJson).toList();
    developer.log('✅ Loaded ${admins.length} admins from database');
    return admins;
  }

  /// Creates a new admin account.
  /// 
  /// Requires: email, password (min 6 chars), and fullName.
  /// Password is hashed on the backend before storage.
  Future<Admin> createAdmin({
    required String email,
    required String password,
    required String fullName,
  }) async {
    if (!_useApi) {
      throw Exception('Admin creation requires API connection');
    }
    final payload = {
      'email': email.trim(),
      'password': password,
      'fullName': fullName.trim(),
    };
    final data = await _sendRequest(method: 'POST', path: '/admins', body: payload);
    final map = _asMap(data, 'admin');
    return Admin.fromJson(map);
  }

  /// Updates an admin's information.
  /// 
  /// SECURITY: Email and password cannot be updated through this method.
  /// Only fullName can be updated.
  Future<Admin> updateAdmin({
    required String adminId,
    String? fullName,
  }) async {
    if (!_useApi) {
      throw Exception('Admin update requires API connection');
    }
    final payload = <String, dynamic>{};
    if (fullName != null) {
      payload['fullName'] = fullName.trim();
    }
    final data = await _sendRequest(
      method: 'PATCH',
      path: '/admins/$adminId',
      body: payload,
    );
    final map = _asMap(data, 'admin');
    return Admin.fromJson(map);
  }
}

