import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../views/product_detail.dart';
import '../views/product_list.dart';
import '../views/sign_in.dart';
import '../../widgets/filters_sheet.dart';
import '../../services/mysql_database_service.dart';
import '../../services/cart_service.dart';
import '../../services/wishlist_service.dart';
import '../../services/auth_service.dart';
import '../../models/product.dart';
import '../../widgets/toast.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;

/// =============================================================
/// CatalogHome
///
/// Home screen with categories, search, filters, and personalized
/// recommendations. Now displays products from database.
/// =============================================================
class CatalogHome extends StatefulWidget {
  const CatalogHome({super.key});

  @override
  State<CatalogHome> createState() => _CatalogHomeState();
}

class _CatalogHomeState extends State<CatalogHome> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  List<Product> _allProducts = [];
  List<Product> _newArrivals = [];
  List<Product> _popularProducts = [];
  bool _loading = true;
  String? _error;

  // Search and filter state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  FilterData? _activeFilters;

  // Updated color palette: removed dark brown, using medium brown and orange
  static const Color _kTextPrimary = Color(0xFF6D4C41); // Medium brown for text
  static const Color _kBrown = Color(0xFF8D6E63); // Primary brown
  static const Color _kOrange = Color(0xFFFF9800); // Primary orange
  static const Color _kLight = Color(0xFFF4E6D4);

  @override
  void initState() {
    super.initState();
    _loadProducts();
    // Listen to search text changes for real-time filtering
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      developer.log('📡 Loading products from database...');
      final results = await Future.wait([
        _db.getAllProducts(),
        _db.getNewArrivalProducts(),
        _db.getPopularProducts(),
      ]);
      if (!mounted) return;
      setState(() {
        _allProducts = results[0];
        _newArrivals = results[1];
        _popularProducts = results[2];
        developer.log('✅ Loaded ${_allProducts.length} products from database');
      });
    } catch (e) {
      developer.log('❌ Failed to load products: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load products. Please check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openProduct(BuildContext context, Product product) {
    // Use rootNavigator to hide tab bar when navigating to product detail
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  /// Opens the filters sheet and applies the returned filter data
  Future<void> _openFilters(BuildContext context) async {
    final result = await FiltersSheet.show(context, initialFilters: _activeFilters);
    if (result != null && mounted) {
      setState(() {
        _activeFilters = result;
      });
    }
  }

  /// Applies search query and filters to a product list
  List<Product> _applyFilters(List<Product> products) {
    var filtered = List<Product>.from(products);
    
    // Apply search query if present
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((product) {
        return product.name.toLowerCase().contains(_searchQuery) ||
               product.description.toLowerCase().contains(_searchQuery) ||
               product.category.toLowerCase().contains(_searchQuery) ||
               product.style.toLowerCase().contains(_searchQuery) ||
               product.material.toLowerCase().contains(_searchQuery);
      }).toList();
    }
    
    // Apply filters if active
    if (_activeFilters != null && _activeFilters!.hasActiveFilters) {
      filtered = filtered.where((product) {
        // Price range filter
        if (product.price < _activeFilters!.minPrice || 
            product.price > _activeFilters!.maxPrice) {
          return false;
        }
        
        // Style filter
        if (_activeFilters!.styles.isNotEmpty && 
            !_activeFilters!.styles.contains(product.style)) {
          return false;
        }
        
        // Material filter
        if (_activeFilters!.materials.isNotEmpty && 
            !_activeFilters!.materials.contains(product.material)) {
          return false;
        }
        
        // Size filter
        if (_activeFilters!.size != 'M' && product.size != _activeFilters!.size) {
          return false;
        }
        
        return true;
      }).toList();
    }
    
    return filtered;
  }

  /// Gets filtered products for display
  List<Product> get _filteredNewArrivals => _applyFilters(_newArrivals);
  List<Product> get _filteredPopularProducts => _applyFilters(_popularProducts);
  
  /// Checks if search or filters are active
  bool get _hasActiveSearchOrFilters => 
      _searchQuery.isNotEmpty || 
      (_activeFilters != null && _activeFilters!.hasActiveFilters);

  @override
  Widget build(BuildContext context) {
    const categories = [
      'Living Room', 'Dining', 'Bedroom', 'Office', 'Outdoor', 'Kids'
    ];

    return CupertinoPageScaffold(
      // Enhanced background with subtle gradient following Apple HIG
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        // Modern navigation bar with improved styling
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        middle: Text(
          'SmartSpace',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _kTextPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.exclamationmark_triangle,
                            size: 64,
                            color: CupertinoColors.systemRed.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _error!,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: CupertinoColors.systemRed,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF8D6E63), Color(0xFFFF9800)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: _loadProducts,
                              child: Text(
                                'Retry',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Enhanced search bar with improved styling
                    Container(
                      decoration: BoxDecoration(
                        // Subtle gradient background for depth
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFFFBF7),
                            const Color(0xFFF4E6D4).withValues(alpha: 0.3),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFBCAAA4).withValues(alpha: 0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8D6E63).withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.search,
                            color: _kTextPrimary.withValues(alpha: 0.5),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CupertinoTextField(
                              controller: _searchController,
                              placeholder: 'Search furniture or keywords',
                              placeholderStyle: GoogleFonts.poppins(
                                fontSize: 15,
                                color: _kTextPrimary.withValues(alpha: 0.5),
                              ),
                              decoration: null,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                color: _kTextPrimary,
                                decoration: TextDecoration.none,
                              ),
                              suffix: _searchQuery.isNotEmpty
                                  ? CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      onPressed: () {
                                        _searchController.clear();
                                      },
                                      child: Icon(
                                        CupertinoIcons.clear_circled_solid,
                                        size: 18,
                                        color: _kTextPrimary.withValues(alpha: 0.5),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Filter button with indicator if filters are active
                          Stack(
                            children: [
                              CupertinoButton(
                                padding: const EdgeInsets.all(8),
                                minimumSize: Size.zero,
                                borderRadius: BorderRadius.circular(10),
                                color: _activeFilters?.hasActiveFilters == true
                                    ? _kOrange
                                    : _kLight,
                                onPressed: () => _openFilters(context),
                                child: Icon(
                                  CupertinoIcons.slider_horizontal_3,
                                  color: _activeFilters?.hasActiveFilters == true
                                      ? Colors.white
                                      : _kBrown,
                                  size: 18,
                                ),
                              ),
                              // Badge indicator when filters are active
                              if (_activeFilters?.hasActiveFilters == true)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: CupertinoColors.systemRed,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Categories',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 120,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  itemBuilder: (context, i) {
                    return SizedBox(
                      width: 100,
                      child: _CategoryTile(label: categories[i]),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                ),
              ),
            ),
            // New Arrival section
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'New Arrival',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        // Use rootNavigator to hide tab bar when navigating to product list
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (_) => ProductListScreen(title: 'New Arrival Products', products: _newArrivals),
                          ),
                        );
                      },
                      child: Text(
                        'See all',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _kBrown,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: _hasActiveSearchOrFilters
                    ? _filteredNewArrivals.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                'No products found',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: _kTextPrimary.withValues(alpha: 0.6),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemBuilder: (context, index) {
                              final product = _filteredNewArrivals[index];
                              return _HorizontalProductCard(
                                product: product,
                                onTap: () => _openProduct(context, product),
                              );
                            },
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemCount: _filteredNewArrivals.length,
                          )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (context, index) {
                          final product = index < _newArrivals.length 
                              ? _newArrivals[index] 
                              : _allProducts[index % _allProducts.length];
                          return _HorizontalProductCard(
                            product: product,
                            onTap: () => _openProduct(context, product),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemCount: _newArrivals.isNotEmpty ? _newArrivals.length : _allProducts.length,
                      ),
              ),
            ),
            // Popular section
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Popular',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: Colors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        // Use rootNavigator to hide tab bar when navigating to product list
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (_) => ProductListScreen(title: 'Popular Products', products: _popularProducts),
                          ),
                        );
                      },
                      child: Text(
                        'See all',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _kBrown,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: _hasActiveSearchOrFilters
                    ? _filteredPopularProducts.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                'No products found',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: _kTextPrimary.withValues(alpha: 0.6),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemBuilder: (context, index) {
                              final product = _filteredPopularProducts[index];
                              return _HorizontalProductCard(
                                product: product,
                                onTap: () => _openProduct(context, product),
                              );
                            },
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemCount: _filteredPopularProducts.length,
                          )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (context, index) {
                          final product = index < _popularProducts.length 
                              ? _popularProducts[index] 
                              : _allProducts[index % _allProducts.length];
                          return _HorizontalProductCard(
                            product: product,
                            onTap: () => _openProduct(context, product),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemCount: _popularProducts.isNotEmpty ? _popularProducts.length : _allProducts.length,
                      ),
              ),
            ),
            // Add bottom padding to prevent content from being blocked by tab bar
            // Tab bar height is 70px, so we add extra padding for comfortable spacing
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label});
  final String label;

  IconData _iconForLabel() {
    switch (label) {
      case 'Living Room':
        return CupertinoIcons.house_fill;
      case 'Dining':
        return CupertinoIcons.table;
      case 'Bedroom':
        return CupertinoIcons.bed_double_fill;
      case 'Office':
        return CupertinoIcons.briefcase_fill;
      case 'Outdoor':
        return CupertinoIcons.tree;
      case 'Kids':
        return CupertinoIcons.person_2_fill;
      default:
        return CupertinoIcons.square_grid_2x2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {},
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          // Enhanced category tile with gradient background
          gradient: LinearGradient(
            colors: [
              _CatalogHomeState._kLight.withValues(alpha: 0.6),
              const Color(0xFFF4E6D4).withValues(alpha: 0.4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFBCAAA4).withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8D6E63).withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // Enhanced icon background with gradient
                gradient: LinearGradient(
                  colors: [
                    _CatalogHomeState._kBrown.withValues(alpha: 0.15),
                    const Color(0xFFFF9800).withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _CatalogHomeState._kBrown.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                _iconForLabel(),
                color: _CatalogHomeState._kBrown,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontWeight: FontWeight.w500,
                fontSize: 12,
                decoration: TextDecoration.none,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _HorizontalProductCard extends StatefulWidget {
  const _HorizontalProductCard({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  State<_HorizontalProductCard> createState() => _HorizontalProductCardState();
}

class _HorizontalProductCardState extends State<_HorizontalProductCard> {
  final WishlistService _wishlist = WishlistService();
  final CartService _cart = CartService();
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _wishlist.addListener(_onWishlistChanged);
  }

  @override
  void dispose() {
    _wishlist.removeListener(_onWishlistChanged);
    super.dispose();
  }

  void _onWishlistChanged() {
    if (mounted) setState(() {});
  }

  void _handleWishlistTap() {
    _wishlist.toggle(widget.product);
    HapticFeedback.selectionClick();
    final isWishlisted = _wishlist.isWishlisted(widget.product.id);
    Toast.info(
      context,
      isWishlisted
          ? '${widget.product.name} added to wishlist'
          : '${widget.product.name} removed from wishlist',
    );
  }

  void _handleCartTap() {
    // Check if user is authenticated before adding to cart
    if (!_auth.isAuthenticated) {
      // Redirect to sign in screen as fullscreen dialog to hide navigation bar
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (_) => const SignInScreen(),
          fullscreenDialog: true,
        ),
      );
      Toast.info(context, 'Please sign in to add items to cart');
      return;
    }
    
    _cart.add(widget.product);
    HapticFeedback.selectionClick();
    Toast.success(context, '${widget.product.name} added to cart');
  }

  @override
  Widget build(BuildContext context) {
    final isWishlisted = _wishlist.isWishlisted(widget.product.id);
    
    // Wrap entire card in CupertinoButton so the whole card is clickable
    // The overlay buttons will naturally prevent tap propagation
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: widget.onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          // Enhanced card design with improved shadows and subtle gradient
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFBCAAA4).withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8D6E63).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product image with overlay buttons
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: ModelViewer(
                      key: ValueKey('${widget.product.id}_preview'),
                      backgroundColor: const Color(0xFFF9F4EF),
                      src: widget.product.modelPath,
                      alt: 'Preview of ${widget.product.name}',
                      ar: false,
                      autoRotate: false,
                      cameraControls: false,
                      disableZoom: true,
                      interactionPrompt: InteractionPrompt.none,
                    ),
                  ),
                ),
                // Wishlist button at top left
                Positioned(
                  top: 8,
                  left: 8,
                  child: CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    onPressed: _handleWishlistTap,
                    child: Icon(
                      isWishlisted ? CupertinoIcons.heart_solid : CupertinoIcons.heart,
                      size: 18,
                      color: isWishlisted ? CupertinoColors.systemRed : _CatalogHomeState._kBrown,
                    ),
                  ),
                ),
                // Add to cart button at top right
                Positioned(
                  top: 8,
                  right: 8,
                  child: CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    onPressed: _handleCartTap,
                    child: Icon(
                      CupertinoIcons.cart_badge_plus,
                      size: 18,
                      color: _CatalogHomeState._kBrown,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                widget.product.name,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _CatalogHomeState._kTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₱${widget.product.price.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(
                      color: _CatalogHomeState._kBrown,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Qty: ${widget.product.inventoryQty}',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: _CatalogHomeState._kTextPrimary.withValues(alpha: 0.6),
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
