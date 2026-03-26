import '../models/product.dart';
import '../models/user.dart';

/// Mock database service for products and users
/// In production, this would connect to MySQL/Firebase/etc.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  // Mock data storage
  final List<Product> _products = [];
  final List<User> _users = [];
  User? _currentUser;

  // Initialize with sample data
  void initialize() {
    if (_products.isEmpty) {
      _loadSampleProducts();
    }
    if (_users.isEmpty) {
      _loadSampleUsers();
    }
  }

  void _loadSampleProducts() {
    final now = DateTime.now();
    
    _products.addAll([
      Product(
        id: 'p1',
        name: 'Modern Dining Chair',
        description: 'Elegant wooden dining chair with comfortable cushioning',
        price: 299.99,
        category: 'Dining',
        style: 'Modern',
        material: 'Wood',
        color: 'Brown',
        modelPath: '',
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
        modelPath: '',
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
      Product(
        id: 'p3',
        name: 'Minimalist Lounge Chair',
        description: 'Simple yet elegant chair perfect for living rooms',
        price: 449.99,
        category: 'Living Room',
        style: 'Minimal',
        material: 'Fabric',
        color: 'Light Brown',
        modelPath: '',
        realWidthMeters: 0.7,
        realHeightMeters: 0.85,
        realDepthMeters: 0.75,
        modelBaseScale: 1.0,
        imageUrls: const [],
        rating: 4.3,
        reviewCount: 67,
        isPopular: false,
        isNewArrival: true,
        inStock: true,
        inventoryQty: 12,
        createdAt: now.subtract(const Duration(days: 8)),
      ),
      Product(
        id: 'p4',
        name: 'Industrial Bar Stool',
        description: 'Sturdy metal and wood bar stool with industrial design',
        price: 189.99,
        category: 'Dining',
        style: 'Industrial',
        material: 'Metal',
        color: 'Dark Brown',
        modelPath: '',
        realWidthMeters: 0.4,
        realHeightMeters: 0.75,
        realDepthMeters: 0.4,
        modelBaseScale: 1.0,
        imageUrls: const [],
        rating: 4.1,
        reviewCount: 45,
        isPopular: false,
        isNewArrival: false,
        inStock: true,
        inventoryQty: 20,
        createdAt: now.subtract(const Duration(days: 60)),
      ),
      Product(
        id: 'p5',
        name: 'Kids Study Chair',
        description: 'Colorful and comfortable chair designed for children',
        price: 129.99,
        category: 'Kids',
        style: 'Modern',
        material: 'Fabric',
        color: 'Blue',
        modelPath: '',
        realWidthMeters: 0.4,
        realHeightMeters: 0.8,
        realDepthMeters: 0.4,
        modelBaseScale: 1.0,
        imageUrls: const [],
        rating: 4.6,
        reviewCount: 156,
        isPopular: true,
        isNewArrival: false,
        inStock: true,
        inventoryQty: 25,
        createdAt: now.subtract(const Duration(days: 45)),
      ),
      Product(
        id: 'p6',
        name: 'Outdoor Patio Chair',
        description: 'Weather-resistant chair perfect for outdoor spaces',
        price: 249.99,
        category: 'Outdoor',
        style: 'Modern',
        material: 'Metal',
        color: 'White',
        modelPath: '',
        realWidthMeters: 0.5,
        realHeightMeters: 0.9,
        realDepthMeters: 0.55,
        modelBaseScale: 1.0,
        imageUrls: const [],
        rating: 4.4,
        reviewCount: 78,
        isPopular: false,
        isNewArrival: true,
        inStock: true,
        inventoryQty: 10,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      Product(
        id: 'p7',
        name: 'Vintage Armchair',
        description: 'Classic vintage-style armchair with rich leather upholstery',
        price: 799.99,
        category: 'Living Room',
        style: 'Classic',
        material: 'Leather',
        color: 'Brown',
        modelPath: '',
        realWidthMeters: 0.8,
        realHeightMeters: 1.0,
        realDepthMeters: 0.8,
        modelBaseScale: 1.0,
        imageUrls: const [],
        rating: 4.7,
        reviewCount: 92,
        isPopular: true,
        isNewArrival: false,
        inStock: true,
        inventoryQty: 5,
        createdAt: now.subtract(const Duration(days: 90)),
      ),
      Product(
        id: 'p8',
        name: 'Bedroom Accent Chair',
        description: 'Soft and cozy chair perfect for bedroom corners',
        price: 349.99,
        category: 'Bedroom',
        style: 'Minimal',
        material: 'Fabric',
        color: 'Light Brown',
        modelPath: '',
        realWidthMeters: 0.7,
        realHeightMeters: 0.85,
        realDepthMeters: 0.7,
        modelBaseScale: 1.0,
        imageUrls: const [],
        rating: 4.2,
        reviewCount: 54,
        isPopular: false,
        isNewArrival: true,
        inStock: true,
        inventoryQty: 18,
        createdAt: now.subtract(const Duration(days: 12)),
      ),
      Product(
        id: 'p9',
        name: 'Gaming Chair Pro',
        description: 'High-performance gaming chair with RGB lighting',
        price: 699.99,
        category: 'Office',
        style: 'Modern',
        material: 'Fabric',
        color: 'Black',
        modelPath: '',
        realWidthMeters: 0.7,
        realHeightMeters: 1.2,
        realDepthMeters: 0.7,
        modelBaseScale: 1.0,
        imageUrls: const [],
        rating: 4.9,
        reviewCount: 203,
        isPopular: true,
        isNewArrival: true,
        inStock: true,
        inventoryQty: 30,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      Product(
        id: 'p10',
        name: 'Scandinavian Dining Chair',
        description: 'Clean lines and natural wood in Scandinavian style',
        price: 199.99,
        category: 'Dining',
        style: 'Minimal',
        material: 'Wood',
        color: 'Natural',
        modelPath: '',
        realWidthMeters: 0.45,
        realHeightMeters: 0.85,
        realDepthMeters: 0.5,
        modelBaseScale: 1.0,
        imageUrls: const [],
        rating: 4.4,
        reviewCount: 87,
        isPopular: false,
        isNewArrival: false,
        inStock: true,
        inventoryQty: 14,
        createdAt: now.subtract(const Duration(days: 75)),
      ),
    ]);
  }

  void _loadSampleUsers() {
    final now = DateTime.now();
    
    _users.addAll([
      User(
        id: 'u1',
        email: 'john.doe@example.com',
        fullName: 'John Doe',
        username: 'john_doe',
        phoneNumber: '+1234567890',
        addresses: ['123 Main St, City, State 12345'],
        wishlistProductIds: ['p1', 'p3', 'p7'],
        orderIds: [],
        preferredStyle: 'Modern',
        minBudget: 100,
        maxBudget: 1000,
        createdAt: now.subtract(const Duration(days: 30)),
        lastLoginAt: now.subtract(const Duration(hours: 2)),
      ),
    ]);
  }

  // Product methods
  List<Product> getAllProducts() {
    initialize();
    return List.unmodifiable(_products);
  }

  List<Product> getPopularProducts() {
    initialize();
    return _products.where((p) => p.isPopular).toList();
  }

  List<Product> getNewArrivalProducts() {
    initialize();
    return _products.where((p) => p.isNewArrival).toList();
  }

  List<Product> getProductsByCategory(String category) {
    initialize();
    return _products.where((p) => p.category == category).toList();
  }

  Product? getProductById(String id) {
    initialize();
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  // User methods
  User? getCurrentUser() => _currentUser;

  void setCurrentUser(User user) {
    _currentUser = user;
  }

  void signOut() {
    _currentUser = null;
  }

  List<User> getAllUsers() {
    initialize();
    return List.unmodifiable(_users);
  }

  User? getUserById(String id) {
    initialize();
    try {
      return _users.firstWhere((u) => u.id == id);
    } catch (e) {
      return null;
    }
  }

  User? getUserByEmail(String email) {
    initialize();
    try {
      return _users.firstWhere((u) => u.email == email);
    } catch (e) {
      return null;
    }
  }

  // Wishlist methods
  List<Product> getUserWishlist(String userId) {
    initialize();
    final user = getUserById(userId);
    if (user == null) return [];
    
    return _products.where((p) => user.wishlistProductIds.contains(p.id)).toList();
  }

  void addToWishlist(String userId, String productId) {
    final userIndex = _users.indexWhere((u) => u.id == userId);
    if (userIndex != -1) {
      final user = _users[userIndex];
      if (!user.wishlistProductIds.contains(productId)) {
        _users[userIndex] = user.copyWith(
          wishlistProductIds: [...user.wishlistProductIds, productId],
        );
      }
    }
  }

  void removeFromWishlist(String userId, String productId) {
    final userIndex = _users.indexWhere((u) => u.id == userId);
    if (userIndex != -1) {
      final user = _users[userIndex];
      _users[userIndex] = user.copyWith(
        wishlistProductIds: user.wishlistProductIds.where((id) => id != productId).toList(),
      );
    }
  }
}













