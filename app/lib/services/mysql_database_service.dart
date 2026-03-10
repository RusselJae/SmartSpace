import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show SocketException;
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
    try {
      _useApi = await _checkApiAvailability();
      if (!_useApi) {
        developer.log('⚠️ API unavailable, using mock data');
        developer.log('💡 To connect to database:');
        developer.log('   1. Make sure backend is running: cd backend && npm start');
        developer.log('   2. Check API_BASE_URL in .env file (default: http://localhost:4000/api)');
        developer.log('   3. For Android emulator, use: http://10.0.2.2:4000/api');
        developer.log('   4. For physical device, use your computer IP: http://YOUR_IP:4000/api');
        _initializeMockData();
      } else {
        developer.log('✅ Successfully connected to API and database');
      }
    } catch (e) {
      developer.log('❌ Error during database initialization: $e');
      developer.log('⚠️ Falling back to mock data');
      _useApi = false;
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
    final baseUrl = ApiConfig.baseUrl;
    developer.log('🔍 Checking API availability...');
    developer.log('   Base URL: $baseUrl');
    developer.log('   Full URI: $uri');
    developer.log('   Host: ${uri.host}');
    developer.log('   Port: ${uri.port}');
    developer.log('   Scheme: ${uri.scheme}');
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
      developer.log('💡 Troubleshooting steps:');
      developer.log('   1. Make sure backend is running: cd backend && npm run dev');
      developer.log('   2. Test in browser: ${ApiConfig.baseUrl}/health');
      developer.log('   3. If using IPv4 address, verify it\'s correct: ${uri.host}');
      developer.log('   4. Check Windows Firewall - allow port ${uri.port}');
      developer.log('   5. Verify backend is listening on 0.0.0.0 (not just localhost)');
      developer.log('   6. If accessing from another device, ensure same network');
      
      // Additional help for IPv4 addresses
      if (uri.host.contains('.') && !uri.host.contains('localhost')) {
        developer.log('');
        developer.log('🌐 IPv4 Connection Tips:');
        developer.log('   - Backend must be started with: npm run dev (listens on 0.0.0.0)');
        developer.log('   - Test directly in browser: http://${uri.host}:${uri.port}/api/health');
        developer.log('   - If browser test works but app doesn\'t, check browser console for CORS errors');
        developer.log('   - Windows Firewall may need to allow Node.js on port ${uri.port}');
      }
    }
    return false;
  }

  Uri _buildUri(String path) {
    // Get the base URL and ensure it has no fragments
    String normalizedBase = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    
    // Remove any hash fragments from base URL (shouldn't be there, but just in case)
    if (normalizedBase.contains('#')) {
      normalizedBase = normalizedBase.substring(0, normalizedBase.indexOf('#'));
    }
    
    // Normalize the path
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    
    // Parse base URL to extract components
    final baseUri = Uri.parse(normalizedBase);
    
    // Build URI using constructor to avoid any parsing issues with fragments
    return Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.port,
      path: '${baseUri.path}$normalizedPath',
      query: baseUri.query,
      // Explicitly no fragment - fragments are not sent to server
    );
  }

  Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};

  Future<dynamic> _sendRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(path);
    final encodedBody = body == null ? null : jsonEncode(body);
    
    // Log request details for debugging
    developer.log('📤 API Request: $method $uri');
    
    late http.Response response;
    try {
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
    } on TimeoutException {
      developer.log('⏱️  API request timed out after ${ApiConfig.timeout.inSeconds}s');
      developer.log('💡 Check if backend is running at: ${ApiConfig.baseUrl}');
      developer.log('💡 Verify your IPv4 address is correct if connecting from another device');
      developer.log('💡 Check firewall settings - port ${uri.port} must be open');
      rethrow;
    } on SocketException catch (e) {
      developer.log('🔌 Network connection failed: $e');
      developer.log('💡 Backend URL: ${ApiConfig.baseUrl}');
      developer.log('💡 Make sure backend server is running');
      developer.log('💡 If using IPv4 address, verify it\'s correct: ${uri.host}');
      developer.log('💡 Check that backend is listening on 0.0.0.0 (not just localhost)');
      developer.log('💡 Ensure both devices are on the same network');
      developer.log('💡 Check Windows Firewall - it may be blocking port ${uri.port}');
      rethrow;
    } catch (e) {
      developer.log('❌ API request failed: $e');
      developer.log('💡 Request was: $method $uri');
      rethrow;
    }

    developer.log('📥 API Response: ${response.statusCode}');
    
    if (response.statusCode < 200 || response.statusCode >= 300) {
      developer.log('❌ API returned error status: ${response.statusCode}');
      developer.log('📄 Response body: ${response.body}');
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
    required String modelPath,
    double? realWidthM,
    double? realHeightM,
    double? realDepthM,
    double modelBaseScale = 1.0,
    required List<String> imageUrls,
    int? inventoryQty,
    required bool inStock,
    bool isArchived = false,
    // Note: isPopular and isNewArrival are now calculated automatically by the backend
  }) {
    return {
      'name': name,
      'description': description,
      'price': price,
      'category': category,
      'style': style,
      'material': material,
      'color': color,
      'modelPath': modelPath,
      if (realWidthM != null) 'realWidthM': realWidthM,
      if (realHeightM != null) 'realHeightM': realHeightM,
      if (realDepthM != null) 'realDepthM': realDepthM,
      'modelBaseScale': modelBaseScale,
      'imageUrls': imageUrls,
      if (inventoryQty != null) 'inventoryQty': inventoryQty,
      'inStock': inStock,
      'isArchived': isArchived,
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

  /// Get top rated products sorted by rating (highest first)
  /// Only includes products with at least one review (rating > 0)
  Future<List<Product>> getTopRatedProducts() async {
    final products = await getAllProducts();
    // Filter products with ratings and sort by rating descending
    final topRated = products
        .where((product) => product.rating > 0)
        .toList()
      ..sort((a, b) {
        // Sort by rating descending, then by review count as tiebreaker
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.reviewCount.compareTo(a.reviewCount);
      });
    return topRated;
  }

  /// Get best seller products sorted by number of orders (highest first)
  /// Products with no orders (orderCount = 0 or null) are excluded
  Future<List<Product>> getBestSellerProducts() async {
    final products = await getAllProducts();
    // Filter products with orders and sort by order count descending
    final bestSellers = products
        .where((product) => (product.orderCount ?? 0) > 0)
        .toList()
      ..sort((a, b) {
        // Sort by order count descending
        final aCount = a.orderCount ?? 0;
        final bCount = b.orderCount ?? 0;
        return bCount.compareTo(aCount);
      });
    return bestSellers;
  }

  Future<Product> createProduct({
    required String name,
    required String description,
    required double price,
    required String category,
    required String style,
    required String material,
    required String color,
    required String modelPath,
    double? realWidthM,
    double? realHeightM,
    double? realDepthM,
    double modelBaseScale = 1.0,
    List<String> imageUrls = const [],
    int? inventoryQty,
    bool inStock = true,
    // Note: isPopular and isNewArrival are now calculated automatically
    // - isNewArrival: Products created within the last week
    // - isPopular: Products with orders
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
        modelPath: modelPath,
        realWidthMeters: realWidthM,
        realHeightMeters: realHeightM,
        realDepthMeters: realDepthM,
        modelBaseScale: modelBaseScale,
        imageUrls: List.unmodifiable(imageUrls),
        rating: 0,
        reviewCount: 0,
        // Popular and new arrival are calculated automatically
        isPopular: false, // Will be calculated based on orders
        isNewArrival: true, // New products are automatically new arrivals
        inStock: inStock,
        inventoryQty: inventoryQty ?? (inStock ? 10 : 0),
        isArchived: false, // New products are not archived by default
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
      modelPath: modelPath,
      realWidthM: realWidthM,
      realHeightM: realHeightM,
      realDepthM: realDepthM,
      modelBaseScale: modelBaseScale,
      imageUrls: imageUrls,
      inventoryQty: inventoryQty,
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
      modelPath: product.modelPath,
      realWidthM: product.realWidthMeters,
      realHeightM: product.realHeightMeters,
      realDepthM: product.realDepthMeters,
      modelBaseScale: product.modelBaseScale,
      imageUrls: product.imageUrls,
      inventoryQty: product.inventoryQty,
      inStock: product.inStock,
      isArchived: product.isArchived,
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

  /// Upload payment proof image for an order
  Future<String> uploadPaymentProof({
    required String orderId,
    required List<int> imageBytes,
    required String fileName,
  }) async {
    if (!_useApi) {
      developer.log('⚠️ Upload payment proof in MOCK MODE - returning placeholder URL');
      return 'https://placehold.co/400x600?text=Payment+Proof';
    }
    
    final uri = Uri.parse('${ApiConfig.baseUrl}/payment-proofs/upload');
    final request = http.MultipartRequest('POST', uri);
    
    // Add file
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        imageBytes,
        filename: fileName,
      ),
    );
    
    // Add order ID
    request.fields['orderId'] = orderId;
    
    // Send request
    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 60),
    );
    
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        errorBody['message']?.toString() ?? 'Upload failed with status ${response.statusCode}',
      );
    }
    
    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    
    if (responseData['success'] != true) {
      throw Exception(responseData['message']?.toString() ?? 'Upload failed');
    }
    
    final data = responseData['data'] as Map<String, dynamic>;
    final downloadUrl = data['downloadUrl'] as String;
    
    // Convert relative URL to absolute URL
    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    final absoluteUrl = downloadUrl.startsWith('http')
        ? downloadUrl
        : '$baseUrl$downloadUrl';
    
    return absoluteUrl;
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

  /// Get all published reviews for a specific product.
  /// Only returns reviews with 'published' status.
  /// Returns reviews from ALL users who have reviewed this product.
  Future<List<Review>> getReviewsByProductId(String productId) async {
    if (!_useApi) {
      developer.log('⚠️ Using MOCK data for reviews (API not connected)');
      // Filter mock reviews by product ID - return ALL published reviews regardless of user
      final allMock = _getMockReviews();
      final filtered = allMock.where((r) => r.productId == productId && r.status == 'published').toList();
      developer.log('✅ Loaded ${filtered.length} mock reviews for product $productId');
      return filtered;
    }
    developer.log('📡 Fetching reviews for product $productId from API...');
    try {
      final response = await _sendRequest(method: 'GET', path: '/reviews?productId=$productId');
      developer.log('📥 Raw response type: ${response.runtimeType}');
      developer.log('📥 Raw response: $response');
      
      // The backend returns { success: true, data: reviews[] }
      // _sendRequest extracts 'data', so response should be the reviews array directly
      List<dynamic> rawList;
      
      if (response is List) {
        // Response is already a list - this is the expected case
        rawList = response;
        developer.log('✅ Response is a List with ${rawList.length} items');
      } else if (response is Map<String, dynamic>) {
        // Response might be wrapped in another structure
        if (response.containsKey('data') && response['data'] is List) {
          rawList = response['data'] as List;
          developer.log('✅ Found reviews in response.data with ${rawList.length} items');
        } else if (response.containsKey('reviews') && response['reviews'] is List) {
          rawList = response['reviews'] as List;
          developer.log('✅ Found reviews in response.reviews with ${rawList.length} items');
        } else {
          developer.log('❌ Unexpected response structure: $response');
          throw Exception('Invalid response format: expected List or Map with data/reviews key');
        }
      } else {
        developer.log('❌ Unexpected response type: ${response.runtimeType}');
        throw Exception('Invalid response type: expected List or Map, got ${response.runtimeType}');
      }
      
      // Convert to List<Map<String, dynamic>>
      final list = rawList
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      
      developer.log('📋 Parsed ${list.length} review items from response');
      
      // Parse each review
      final reviews = <Review>[];
      for (final map in list) {
        try {
          final review = Review.fromJson(map);
          reviews.add(review);
          developer.log('  ✓ Parsed review from ${review.userName} (${review.rating} stars)');
        } catch (e) {
          developer.log('❌ Error parsing review: $e');
          developer.log('📄 Review data: $map');
          // Continue with other reviews instead of failing completely
        }
      }
      
      // Backend already filters to only published reviews (including null status)
      // Review.fromJson also defaults null status to 'published'
      // So we should receive all valid reviews, but double-check status just in case
      final publishedReviews = reviews.where((r) {
        // Accept 'published' status or empty/null (which Review.fromJson converts to 'published')
        final status = r.status.trim().toLowerCase();
        return status == 'published' || status.isEmpty;
      }).toList();
      
      developer.log('✅ Loaded ${publishedReviews.length} published reviews for product $productId (from ${reviews.length} total parsed)');
      
      // Log any filtered out reviews for debugging
      final filteredOut = reviews.where((r) {
        final status = r.status.trim().toLowerCase();
        return status != 'published' && status.isNotEmpty;
      }).toList();
      if (filteredOut.isNotEmpty) {
        developer.log('⚠️ Filtered out ${filteredOut.length} non-published reviews: ${filteredOut.map((r) => '${r.userName} (status: "${r.status}")').join(", ")}');
      }
      
      if (publishedReviews.isNotEmpty) {
        developer.log('👥 Reviews from users: ${publishedReviews.map((r) => '${r.userName} (${r.rating}⭐, status: "${r.status}")').join(", ")}');
      } else {
        developer.log('⚠️ No published reviews found for product $productId');
        developer.log('💡 Troubleshooting:');
        developer.log('   1. Check if reviews exist in database: SELECT * FROM reviews WHERE product_id = "$productId"');
        developer.log('   2. Verify review status is "published" or NULL');
        developer.log('   3. Check backend logs for query results');
        developer.log('   4. Verify productId format matches between product and review records');
      }
      
      return publishedReviews;
    } catch (e, stackTrace) {
      developer.log('❌ Error loading reviews for product $productId: $e');
      developer.log('📚 Stack trace: $stackTrace');
      // Return empty list instead of throwing to prevent UI from breaking
      // The error is logged for debugging
      return [];
    }
  }

  /// Check if the current user has purchased a specific product.
  /// Returns true if the user has at least one order containing this product.
  Future<bool> hasUserPurchasedProduct(String userId, String productId) async {
    if (!_useApi) {
      // In mock mode, assume user has purchased if they have any orders
      final orders = await getAllOrders();
      final userOrders = orders.where((order) => order.userId == userId).toList();
      return userOrders.any((order) => order.productIds.contains(productId));
    }
    try {
      // Fetch user's orders and check if any contain this product
      final orders = await getAllOrders();
      final userOrders = orders.where((order) => order.userId == userId).toList();
      return userOrders.any((order) => order.productIds.contains(productId));
    } catch (e) {
      developer.log('❌ Error checking purchase status: $e');
      return false;
    }
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
        status: 'published',
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
    try {
      developer.log('📤 Creating review for product: $productId');
      final data = await _sendRequest(method: 'POST', path: '/reviews', body: payload);
      developer.log('📥 Received review response: $data');
      
      if (data == null) {
        throw Exception('Server returned empty response');
      }
      
      final map = _asMap(data, 'review');
      developer.log('✅ Parsed review map: $map');
      
      // Ensure dates are properly formatted strings
      if (map['createdAt'] is DateTime) {
        map['createdAt'] = (map['createdAt'] as DateTime).toIso8601String();
      }
      if (map['updatedAt'] != null && map['updatedAt'] is DateTime) {
        map['updatedAt'] = (map['updatedAt'] as DateTime).toIso8601String();
      }
      
      final review = Review.fromJson(map);
      developer.log('✅ Successfully created review: ${review.id}');
      return review;
    } catch (e) {
      developer.log('❌ Error creating review: $e');
      rethrow;
    }
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
        modelPath: 'assets/chair.glb',
        realWidthMeters: 0.45,
        realHeightMeters: 0.88,
        realDepthMeters: 0.52,
        modelBaseScale: 1.0,
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
        modelPath: 'assets/chair.glb',
        realWidthMeters: 0.6,
        realHeightMeters: 1.1,
        realDepthMeters: 0.65,
        modelBaseScale: 1.0,
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

