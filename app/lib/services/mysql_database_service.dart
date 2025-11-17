import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:mysql1/mysql1.dart';

import '../config/database_config.dart';
import '../models/order_record.dart';
import '../models/product.dart';
import '../models/user.dart';

/// Service that persists products, users, and orders either in MySQL or in-memory.
class MySQLDatabaseService {
  static final MySQLDatabaseService _instance = MySQLDatabaseService._internal();
  factory MySQLDatabaseService() => _instance;
  MySQLDatabaseService._internal();

  MySqlConnection? _connection;
  final Random _random = Random();

  final List<Product> _mockProducts = [];
  final List<User> _mockUsers = [];
  final List<OrderRecord> _mockOrders = [];

  Future<void> initialize() async {
    try {
      final settings = ConnectionSettings(
        host: DatabaseConfig.host,
        port: DatabaseConfig.port,
        user: DatabaseConfig.username,
        password: DatabaseConfig.password,
        db: DatabaseConfig.database,
        timeout: Duration(seconds: DatabaseConfig.timeout),
      );
      _connection = await MySqlConnection.connect(settings);
      await _createTables();
      await _seedIfEmpty();
      developer.log('Connected to MySQL');
    } catch (e) {
      developer.log('MySQL unavailable, using mock data: $e');
      _initializeMockData();
    }
  }

  Future<void> _createTables() async {
    if (_connection == null) return;
    await _connection!.query('''
      CREATE TABLE IF NOT EXISTS products (
        id VARCHAR(50) PRIMARY KEY,
        name VARCHAR(255),
        description TEXT,
        price DECIMAL(10,2),
        category VARCHAR(120),
        style VARCHAR(120),
        material VARCHAR(120),
        color VARCHAR(80),
        size VARCHAR(50),
        model_path VARCHAR(500),
        image_urls TEXT,
        rating DECIMAL(3,2) DEFAULT 0,
        review_count INT DEFAULT 0,
        is_popular TINYINT(1) DEFAULT 0,
        is_new_arrival TINYINT(1) DEFAULT 0,
        in_stock TINYINT(1) DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await _connection!.query('''
      CREATE TABLE IF NOT EXISTS users (
        id VARCHAR(50) PRIMARY KEY,
        email VARCHAR(255) UNIQUE,
        full_name VARCHAR(255),
        phone_number VARCHAR(30),
        addresses TEXT,
        wishlist_product_ids TEXT,
        order_ids TEXT,
        preferred_style VARCHAR(120),
        min_budget DECIMAL(10,2),
        max_budget DECIMAL(10,2),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_login_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await _connection!.query('''
      CREATE TABLE IF NOT EXISTS orders (
        id VARCHAR(50) PRIMARY KEY,
        user_id VARCHAR(50),
        product_ids TEXT,
        total_amount DECIMAL(10,2),
        status VARCHAR(20),
        shipping_address TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<void> _seedIfEmpty() async {
    if (_connection == null) return;
    final products = await _connection!.query('SELECT COUNT(*) as count FROM products');
    if ((products.first['count'] as int) == 0) {
      await _insertSampleProducts();
    }
    final users = await _connection!.query('SELECT COUNT(*) as count FROM users');
    if ((users.first['count'] as int) == 0) {
      await _insertSampleUsers();
    }
    final orders = await _connection!.query('SELECT COUNT(*) as count FROM orders');
    if ((orders.first['count'] as int) == 0) {
      await _insertSampleOrders();
    }
  }

  Future<void> _insertSampleProducts() async {
    if (_connection == null) return;
    final data = [
      _productMap('Modern Dining Chair', 'Dining', 299.99),
      _productMap('Executive Office Chair', 'Office', 599.99),
      _productMap('Minimalist Lounge Chair', 'Living Room', 449.99),
    ];
    for (final product in data) {
      await _connection!.query('''
        INSERT INTO products (
          id, name, description, price, category, style, material, color, size,
          model_path, image_urls, rating, review_count, is_popular, is_new_arrival, in_stock
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        product['id'],
        product['name'],
        product['description'],
        product['price'],
        product['category'],
        product['style'],
        product['material'],
        product['color'],
        product['size'],
        product['model_path'],
        product['image_urls'],
        product['rating'],
        product['review_count'],
        product['is_popular'],
        product['is_new_arrival'],
        product['in_stock'],
      ]);
    }
  }

  Future<void> _insertSampleUsers() async {
    if (_connection == null) return;
    final users = [
      {
        'id': 'u1',
        'email': 'jane.appleseed@example.com',
        'full_name': 'Jane Appleseed',
        'phone_number': '+1 555 0100',
        'addresses': jsonEncode(['123 Maple St, Springfield']),
        'wishlist_product_ids': jsonEncode(['p1']),
        'order_ids': jsonEncode(['o1']),
        'preferred_style': 'Modern',
        'min_budget': 100,
        'max_budget': 2000,
      },
      {
        'id': 'u2',
        'email': 'marcus.tan@example.com',
        'full_name': 'Marcus Tan',
        'phone_number': '+65 8000 1234',
        'addresses': jsonEncode(['55 River Valley Rd, Singapore']),
        'wishlist_product_ids': jsonEncode(['p2']),
        'order_ids': jsonEncode(['o2']),
        'preferred_style': 'Minimal',
        'min_budget': 200,
        'max_budget': 5000,
      },
    ];
    for (final user in users) {
      await _connection!.query('''
        INSERT INTO users (
          id, email, full_name, phone_number, addresses, wishlist_product_ids, order_ids,
          preferred_style, min_budget, max_budget
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        user['id'],
        user['email'],
        user['full_name'],
        user['phone_number'],
        user['addresses'],
        user['wishlist_product_ids'],
        user['order_ids'],
        user['preferred_style'],
        user['min_budget'],
        user['max_budget'],
      ]);
    }
  }

  Future<void> _insertSampleOrders() async {
    if (_connection == null) return;
    final orders = [
      {
        'id': 'o1',
        'user_id': 'u1',
        'product_ids': jsonEncode(['p1', 'p2']),
        'total_amount': 899.98,
        'status': 'pending',
        'shipping_address': jsonEncode({'line1': '123 Maple St', 'city': 'Springfield', 'country': 'USA'}),
      },
      {
        'id': 'o2',
        'user_id': 'u2',
        'product_ids': jsonEncode(['p3']),
        'total_amount': 449.99,
        'status': 'confirmed',
        'shipping_address': jsonEncode({'line1': '55 River Valley Rd', 'city': 'Singapore', 'country': 'SG'}),
      },
    ];
    for (final order in orders) {
      await _connection!.query('''
        INSERT INTO orders (id, user_id, product_ids, total_amount, status, shipping_address)
        VALUES (?, ?, ?, ?, ?, ?)
      ''', [
        order['id'],
        order['user_id'],
        order['product_ids'],
        order['total_amount'],
        order['status'],
        order['shipping_address'],
      ]);
    }
  }

  Map<String, dynamic> _productMap(String name, String category, double price) {
    return {
      'id': _generateId('p'),
      'name': name,
      'description': '$name description',
      'price': price,
      'category': category,
      'style': 'Modern',
      'material': 'Wood',
      'color': 'Brown',
      'size': 'M',
      'model_path': 'assets/chair.glb',
      'image_urls': jsonEncode([]),
      'rating': 4.5,
      'review_count': 24,
      'is_popular': 1,
      'is_new_arrival': 1,
      'in_stock': 1,
    };
  }

  String _generateId(String prefix) {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final rand = _random.nextInt(9999);
    return '$prefix$millis$rand';
  }

  void _initializeMockData() {
    if (_mockProducts.isNotEmpty) return;
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
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ]);

    _mockUsers.addAll([
      User(
        id: 'u1',
        email: 'jane.appleseed@example.com',
        fullName: 'Jane Appleseed',
        phoneNumber: '+1 555 0100',
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
        phoneNumber: '+65 8000 1234',
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

  Future<List<Product>> getAllProducts() async {
    if (_connection == null) {
      _initializeMockData();
      return List.unmodifiable(_mockProducts);
    }
    final results = await _connection!.query('SELECT * FROM products ORDER BY created_at DESC');
    return results.map(_productFromRow).toList();
  }

  Future<List<Product>> getPopularProducts() async {
    if (_connection == null) {
      _initializeMockData();
      return _mockProducts.where((p) => p.isPopular).toList();
    }
    final results = await _connection!.query('SELECT * FROM products WHERE is_popular = 1');
    return results.map(_productFromRow).toList();
  }

  Future<List<Product>> getNewArrivalProducts() async {
    if (_connection == null) {
      _initializeMockData();
      return _mockProducts.where((p) => p.isNewArrival).toList();
    }
    final results = await _connection!.query('SELECT * FROM products WHERE is_new_arrival = 1 ORDER BY created_at DESC');
    return results.map(_productFromRow).toList();
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
    bool isPopular = false,
    bool isNewArrival = false,
    bool inStock = true,
  }) async {
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
      createdAt: DateTime.now(),
    );

    if (_connection == null) {
      _mockProducts.insert(0, product);
      return product;
    }

    await _connection!.query('''
      INSERT INTO products (
        id, name, description, price, category, style, material, color, size,
        model_path, image_urls, rating, review_count, is_popular, is_new_arrival, in_stock
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      product.id,
      product.name,
      product.description,
      product.price,
      product.category,
      product.style,
      product.material,
      product.color,
      product.size,
      product.modelPath,
      jsonEncode(product.imageUrls),
      product.rating,
      product.reviewCount,
      product.isPopular,
      product.isNewArrival,
      product.inStock,
    ]);

    return product;
  }

  Future<Product?> updateProduct(Product product) async {
    if (_connection == null) {
      final index = _mockProducts.indexWhere((p) => p.id == product.id);
      if (index != -1) {
        _mockProducts[index] = product;
        return product;
      }
      return null;
    }

    await _connection!.query('''
      UPDATE products SET
        name = ?, description = ?, price = ?, category = ?, style = ?, material = ?,
        color = ?, size = ?, model_path = ?, image_urls = ?, is_popular = ?, is_new_arrival = ?, in_stock = ?
      WHERE id = ?
    ''', [
      product.name,
      product.description,
      product.price,
      product.category,
      product.style,
      product.material,
      product.color,
      product.size,
      product.modelPath,
      jsonEncode(product.imageUrls),
      product.isPopular,
      product.isNewArrival,
      product.inStock,
      product.id,
    ]);
    return product;
  }

  Future<void> deleteProduct(String id) async {
    if (_connection == null) {
      _mockProducts.removeWhere((p) => p.id == id);
      return;
    }
    await _connection!.query('DELETE FROM products WHERE id = ?', [id]);
  }

  Future<List<User>> getAllUsers() async {
    if (_connection == null) {
      _initializeMockData();
      return List.unmodifiable(_mockUsers);
    }
    final results = await _connection!.query('SELECT * FROM users ORDER BY created_at DESC');
    return results.map(_userFromRow).toList();
  }

  Future<List<OrderRecord>> getAllOrders() async {
    if (_connection == null) {
      _initializeMockData();
      return List.unmodifiable(_mockOrders);
    }
    final results = await _connection!.query('''
      SELECT o.*, u.full_name AS user_name
      FROM orders o
      LEFT JOIN users u ON o.user_id = u.id
      ORDER BY o.created_at DESC
    ''');
    return results.map(_orderFromRow).toList();
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    if (_connection == null) {
      final index = _mockOrders.indexWhere((o) => o.id == orderId);
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
    await _connection!.query('UPDATE orders SET status = ? WHERE id = ?', [status, orderId]);
  }

  Product _productFromRow(ResultRow row) {
    return Product(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String? ?? '',
      price: (row['price'] as num).toDouble(),
      category: row['category'] as String,
      style: row['style'] as String? ?? '',
      material: row['material'] as String? ?? '',
      color: row['color'] as String? ?? '',
      size: row['size'] as String? ?? '',
      modelPath: row['model_path'] as String? ?? 'assets/chair.glb',
      imageUrls: _decodeStringList(row['image_urls']),
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: row['review_count'] as int? ?? 0,
      isPopular: _asBool(row['is_popular']),
      isNewArrival: _asBool(row['is_new_arrival']),
      inStock: _asBool(row['in_stock']),
      createdAt: row['created_at'] as DateTime? ?? DateTime.now(),
    );
  }

  User _userFromRow(ResultRow row) {
    return User(
      id: row['id'] as String,
      email: row['email'] as String,
      fullName: row['full_name'] as String,
      phoneNumber: row['phone_number'] as String?,
      addresses: _decodeStringList(row['addresses']),
      wishlistProductIds: _decodeStringList(row['wishlist_product_ids']),
      orderIds: _decodeStringList(row['order_ids']),
      preferredStyle: row['preferred_style'] as String? ?? '',
      minBudget: (row['min_budget'] as num?)?.toDouble() ?? 0,
      maxBudget: (row['max_budget'] as num?)?.toDouble() ?? 0,
      createdAt: row['created_at'] as DateTime? ?? DateTime.now(),
      lastLoginAt: row['last_login_at'] as DateTime? ?? DateTime.now(),
    );
  }

  OrderRecord _orderFromRow(ResultRow row) {
    return OrderRecord(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      userName: row['user_name'] as String? ?? '',
      productIds: _decodeStringList(row['product_ids']),
      totalAmount: (row['total_amount'] as num).toDouble(),
      status: row['status'] as String,
      shippingAddress: _decodeMap(row['shipping_address']),
      createdAt: row['created_at'] as DateTime? ?? DateTime.now(),
      updatedAt: row['updated_at'] as DateTime? ?? DateTime.now(),
    );
  }

  List<String> _decodeStringList(dynamic value) {
    if (value == null) return [];
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    }
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  Map<String, dynamic> _decodeMap(dynamic value) {
    if (value == null) return {};
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, val) => MapEntry(key.toString(), val));
      }
    }
    if (value is Map<String, dynamic>) {
      return value;
    }
    return {};
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }
}

