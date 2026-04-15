import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../views/product_detail.dart';
import '../views/product_list.dart';
import '../views/made_to_order_request_screen.dart';
import '../views/sign_in.dart';
import '../../widgets/cached_model_src_loader.dart';
import '../../widgets/filters_sheet.dart';
import '../../services/mysql_database_service.dart';
import '../../services/cart_service.dart';
import '../../services/wishlist_service.dart';
import '../../services/auth_service.dart';
import '../../models/product.dart';
import '../../widgets/toast.dart';
import '../../utils/model_path_helper.dart';
import '../../services/native_ar_editor_service.dart';
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
  final AuthService _auth = AuthService();
  List<Product> _allProducts = [];
  List<Product> _newArrivals = [];
  List<Product> _topRatedProducts = [];
  List<Product> _bestSellerProducts = [];
  bool _loading = true;
  String? _error;

  // Search and filter state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  FilterData? _activeFilters;

  // -------------------------------------------------------------
  // Lightweight in-memory search suggestions
  // -------------------------------------------------------------
  //
  // We derive "typeahead" style suggestions directly from the full
  // `_allProducts` list. This means:
  // - No extra network calls
  // - Suggestions always reflect the same data set used elsewhere
  // - We keep behavior consistent with the existing search filter
  //
  // The intent is to *preview* likely matches while typing, without
  // changing the existing filtering behavior of the main sections.
  // -------------------------------------------------------------
  List<Product> get _searchSuggestions {
    // If there is no query, we do not show any suggestion UI at all.
    if (_searchQuery.isEmpty) return const [];

    // Base results share logic with the dedicated search results list so
    // behavior stays consistent across the app.
    final base = _searchResults;

    // Only surface a very small preview here – up to 3 products – so the
    // home layout stays focused while typing. The full list lives on the
    // dedicated search results screen.
    const maxSuggestions = 3;
    if (base.length <= maxSuggestions) {
      return base;
    }
    return base.sublist(0, maxSuggestions);
  }

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
        _db.getTopRatedProducts(),
        _db.getBestSellerProducts(),
      ]);
      if (!mounted) return;
      setState(() {
        // Customers should never see archived products in the storefront.
        // (Admin still has an "Archived" segment inside the admin console.)
        _allProducts = (results[0] as List<Product>).where((p) => !p.isArchived).toList();
        _newArrivals = (results[1] as List<Product>).where((p) => !p.isArchived).toList();
        _topRatedProducts = (results[2] as List<Product>).where((p) => !p.isArchived).toList();
        _bestSellerProducts = (results[3] as List<Product>).where((p) => !p.isArchived).toList();
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

  /// Applies filters to a product list (excluding search query)
  /// Search results are shown separately, not filtering existing sections
  List<Product> _applyFilters(List<Product> products) {
    var filtered = List<Product>.from(products);
    
    // Note: Search query is NOT applied here - search results are shown separately
    // This ensures existing sections (New Arrival, Top Rated, etc.) remain visible
    
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
        
        return true;
      }).toList();
    }
    
    return filtered;
  }

  /// Gets search results (separate from filtered sections)
  List<Product> get _searchResults {
    if (_searchQuery.isEmpty) return [];
    
    var results = _allProducts.where((product) {
      return product.name.toLowerCase().contains(_searchQuery) ||
             product.description.toLowerCase().contains(_searchQuery) ||
             product.category.toLowerCase().contains(_searchQuery) ||
             product.style.toLowerCase().contains(_searchQuery) ||
             product.material.toLowerCase().contains(_searchQuery);
    }).toList();
    
    // Apply filters to search results if active
    if (_activeFilters != null && _activeFilters!.hasActiveFilters) {
      results = _applyFilters(results);
    }
    
    return results;
  }

  /// Gets filtered products for display (without search filtering)
  List<Product> get _filteredNewArrivals => _applyFilters(_newArrivals);
  List<Product> get _filteredTopRatedProducts => _applyFilters(_topRatedProducts);
  List<Product> get _filteredBestSellerProducts => _applyFilters(_bestSellerProducts);
  
  /// Checks if filters are active (search is handled separately)
  bool get _hasActiveFilters => 
      _activeFilters != null && _activeFilters!.hasActiveFilters;

  /// Format price with commas (e.g., 25000 -> 25,000)
  static String formatPrice(double price) {
    final parts = price.toStringAsFixed(0).split('.');
    final integerPart = parts[0];
    
    // Add commas to integer part
    final buffer = StringBuffer();
    for (int i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(integerPart[i]);
    }
    
    return buffer.toString();
  }

  /// Navigate to product list filtered by category
  void _navigateToCategory(String category) {
    final bool showAll = category.toLowerCase() == 'all';
    final categoryProducts = showAll
        ? List<Product>.from(_allProducts)
        : _allProducts
            .where((product) => product.category.toLowerCase() == category.toLowerCase())
            .toList();
    
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => ProductListScreen(
          title: showAll ? 'All Products' : category,
          products: categoryProducts,
        ),
      ),
    );
  }

  void _openMadeToOrderRequest() {
    if (!_auth.isAuthenticated) {
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (_) => const SignInScreen(),
          fullscreenDialog: true,
        ),
      );
      Toast.info(context, 'Please sign in first');
      return;
    }
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => const MadeToOrderRequestScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const walnut = Color(0xFF5C4033);
    // Category labels used for the inline category links just under
    // the navigation bar.
    const categories = [
      'Living Room',
      'Dining',
      'Bedroom',
      'Office',
      'Kitchen',
      'All',
    ];

    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        // Navigation bar with logo (left), search (center), filter (right).
        // Now using a pure white background; walnut is kept for text/icons.
        backgroundColor: Colors.white,
        padding: const EdgeInsetsDirectional.only(
          start: 12,
          end: 12,
          top: 4,
          bottom: 6,
        ),
        border: const Border(
          bottom: BorderSide(
            color: CupertinoColors.separator,
            width: 0.5,
          ),
        ),
        leading: ClipOval(
          child: Image.asset(
            'assets/images/logo.jpg',
            width: 34,
            height: 34,
            fit: BoxFit.cover,
          ),
        ),
        middle: Container(
          // Pure white rectangular search field with walnut accents.
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.search,
                color: walnut.withValues(alpha: 0.7),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoTextField(
                  controller: _searchController,
                  placeholder: 'Search furniture or keywords',
                  placeholderStyle: GoogleFonts.poppins(
                    fontSize: 14,
                    color: walnut.withValues(alpha: 0.45),
                  ),
                  decoration: null,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: walnut,
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
                            size: 16,
                            color: walnut.withValues(alpha: 0.55),
                          ),
                        )
                      : null,
                  onSubmitted: (_) {
                    final query = _searchQuery.trim();
                    if (query.isEmpty) return;
                    final results = _searchResults;
                    if (results.isEmpty) return;
                    Navigator.of(context, rootNavigator: true).push(
                      CupertinoPageRoute(
                        builder: (_) => ProductListScreen(
                          title: 'Results for "$query"',
                          products: results,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        trailing: Stack(
          alignment: Alignment.center,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: Size.zero,
              borderRadius: BorderRadius.circular(6),
              color: Colors.white,
              onPressed: () => _openFilters(context),
              child: Icon(
                CupertinoIcons.slider_horizontal_3,
                color: walnut,
                size: 20,
              ),
            ),
            if (_activeFilters?.hasActiveFilters == true)
              Positioned(
                right: 4,
                top: 4,
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
                : Stack(
                    children: [
                      Positioned.fill(
                        child: CustomScrollView(
          slivers: [
            // Sticky keyword bar that sits directly under the navigation bar,
            // and directly above the floating search results panel.
            SliverPersistentHeader(
              pinned: true,
              floating: false,
              delegate: _CatalogKeywordHeaderDelegate(
                categories: categories,
                onTapCategory: _navigateToCategory,
              ),
            ),
            // Sticky, floating search-results block that sits directly
            // under the navigation bar. When there are no suggestions,
            // it collapses to zero height so the catalog content moves up.
            SliverPersistentHeader(
              pinned: true,
              floating: false,
              delegate: _CatalogSearchResultsHeaderDelegate(
                suggestions: _searchSuggestions,
                totalResults: _searchResults.length,
                onTapProduct: (product) => _openProduct(context, product),
                onTapViewAll: () {
                  final query = _searchQuery.trim();
                  if (query.isEmpty) return;
                  final results = _searchResults;
                  if (results.isEmpty) return;
                  Navigator.of(context, rootNavigator: true).push(
                    CupertinoPageRoute(
                      builder: (_) => ProductListScreen(
                        title: 'Results for "$query"',
                        products: results,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Full-width image strip that sits immediately above "New Arrival".
            // No horizontal padding; only vertical breathing space.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: Image.asset(
                    'assets/images/home_banner.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _openMadeToOrderRequest,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: walnut.withValues(alpha: 0.25), width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.sparkles, color: walnut, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Made to Order',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: walnut,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        Text(
                          'Request now',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: walnut.withValues(alpha: 0.85),
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.chevron_forward, color: walnut, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // New Arrival section (search does not hide or filter this section)
            ...[
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
                  child: _hasActiveFilters
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
            ],
            // Top Rated section (always visible; filters only)
            ...[
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Top Rated',
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
                              builder: (_) => ProductListScreen(title: 'Top Rated Products', products: _topRatedProducts),
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
                  child: _hasActiveFilters
                      ? _filteredTopRatedProducts.isEmpty
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
                                final product = _filteredTopRatedProducts[index];
                                return _HorizontalProductCard(
                                  product: product,
                                  onTap: () => _openProduct(context, product),
                                );
                              },
                              separatorBuilder: (_, __) => const SizedBox(width: 12),
                              itemCount: _filteredTopRatedProducts.length,
                            )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final product = index < _topRatedProducts.length 
                                ? _topRatedProducts[index] 
                                : _allProducts[index % _allProducts.length];
                            return _HorizontalProductCard(
                              product: product,
                              onTap: () => _openProduct(context, product),
                            );
                          },
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemCount: _topRatedProducts.isNotEmpty ? _topRatedProducts.length : _allProducts.length,
                        ),
                ),
              ),
            ],
            // Best Seller section (always visible; filters only)
            ...[
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Best Seller',
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
                              builder: (_) => ProductListScreen(title: 'Best Seller Products', products: _bestSellerProducts),
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
                  child: _hasActiveFilters
                      ? _filteredBestSellerProducts.isEmpty
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
                                final product = _filteredBestSellerProducts[index];
                                return _HorizontalProductCard(
                                  product: product,
                                  onTap: () => _openProduct(context, product),
                                );
                              },
                              separatorBuilder: (_, __) => const SizedBox(width: 12),
                              itemCount: _filteredBestSellerProducts.length,
                            )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final product = index < _bestSellerProducts.length 
                                ? _bestSellerProducts[index] 
                                : _allProducts[index % _allProducts.length];
                            return _HorizontalProductCard(
                              product: product,
                              onTap: () => _openProduct(context, product),
                            );
                          },
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemCount: _bestSellerProducts.isNotEmpty ? _bestSellerProducts.length : _allProducts.length,
                        ),
                ),
              ),
            ],
            // Bottom padding for tab bar clearance (reduced 90% from 90px).
            const SliverToBoxAdapter(child: SizedBox(height: 9)),
          ],
        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}


class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

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
      default:
        return CupertinoIcons.square_grid_2x2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
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
                fontSize: 13,
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

class _HorizontalProductCardState extends State<_HorizontalProductCard>
    with AutomaticKeepAliveClientMixin<_HorizontalProductCard> {
  final WishlistService _wishlist = WishlistService();
  final CartService _cart = CartService();
  final AuthService _auth = AuthService();

  /// Launches the native Kotlin AR editor for this product.
  ///
  /// This matches the grid card behavior so all product AR buttons feel
  /// consistent across the app.
  Future<void> _openNativeArEditor() {
    return NativeArEditorService.openForProduct(widget.product);
  }

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
    if (!_auth.isAuthenticated) {
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (_) => const SignInScreen(),
          fullscreenDialog: true,
        ),
      );
      Toast.info(context, 'Please sign in to like products');
      return;
    }
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
    super.build(context);
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
            // Product image with overlay buttons - make image area clickable
            Stack(
              children: [
                // WebView would steal taps from the card; ignore pointer so the outer
                // [CupertinoButton] receives the press and opens product detail.
                IgnorePointer(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: CachedModelSrcLoader(
                        sourceUrl: ModelPathHelper.normalize(widget.product.modelPath),
                        builder: (context, resolvedSrc) => ModelViewer(
                          key: ValueKey('${widget.product.id}_preview'),
                          backgroundColor: const Color(0xFFF9F4EF),
                          src: resolvedSrc,
                          alt: 'Preview of ${widget.product.name}',
                          ar: false,
                          environmentImage: 'neutral',
                          exposure: 1.35,
                          shadowIntensity: 0.18,
                          autoRotate: false,
                          cameraControls: false,
                          disableZoom: true,
                          interactionPrompt: InteractionPrompt.none,
                        ),
                      ),
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
                // AR Editor button at bottom right (per request)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    onPressed: _openNativeArEditor,
                    child: const Icon(
                      CupertinoIcons.cube_box,
                      size: 18,
                      color: Color(0xFF8D6E63),
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
                    '₱${_CatalogHomeState.formatPrice(widget.product.price)}',
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

  @override
  bool get wantKeepAlive => true;
}

/// Sliver header that renders the floating search-results panel for
/// `CatalogHome`. When there are no suggestions, it collapses to zero
/// height so normal content fills the space.
class _CatalogSearchResultsHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CatalogSearchResultsHeaderDelegate({
    required this.suggestions,
    required this.totalResults,
    required this.onTapProduct,
    required this.onTapViewAll,
  });

  final List<Product> suggestions;
  final int totalResults;
  final void Function(Product) onTapProduct;
  final VoidCallback onTapViewAll;

  double _baseHeight() {
    if (suggestions.isEmpty) return 0;
    const row = 50.0;
    const footer = 40.0;
    final rowsHeight = row * suggestions.length;
    final extraFooter = totalResults > suggestions.length ? footer : 0;
    return rowsHeight + extraFooter + 4;
  }

  @override
  double get minExtent => _baseHeight();

  @override
  double get maxExtent => _baseHeight();

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      // No vertical gap between navigation bar and the floating panel.
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFBCAAA4).withValues(alpha: 0.25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final product in suggestions)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                borderRadius: BorderRadius.zero,
                onPressed: () => onTapProduct(product),
                child: Row(
                  children: [
                    _SearchSuggestionThumb(product: product),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _CatalogHomeState._kTextPrimary,
                            ),
                          ),
                          Text(
                            '${product.category} • ₱${_CatalogHomeState.formatPrice(product.price)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color:
                                  _CatalogHomeState._kTextPrimary.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (totalResults > suggestions.length)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                borderRadius: BorderRadius.zero,
                onPressed: onTapViewAll,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'More search results ($totalResults)',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _CatalogHomeState._kBrown,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      size: 12,
                      color: _CatalogHomeState._kBrown,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CatalogSearchResultsHeaderDelegate oldDelegate) {
    return oldDelegate.suggestions != suggestions ||
        oldDelegate.totalResults != totalResults;
  }
}

/// Sticky category-links bar shown between the navigation bar and the
/// floating search results panel.
class _CatalogKeywordHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CatalogKeywordHeaderDelegate({
    required this.categories,
    required this.onTapCategory,
  });

  final List<String> categories;
  final void Function(String) onTapCategory;

  @override
  double get minExtent => categories.isEmpty ? 0 : 30;

  @override
  double get maxExtent => categories.isEmpty ? 0 : 30;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    if (categories.isEmpty) return const SizedBox.shrink();

    const walnut = Color(0xFF5C4033);

    return Container(
      width: double.infinity,
      color: Colors.white,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final category in categories) ...[
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                minSize: 0,
                onPressed: () => onTapCategory(category),
                child: Text(
                  category,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: walnut,
                    decoration: TextDecoration.none,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CatalogKeywordHeaderDelegate oldDelegate) {
    return oldDelegate.categories != categories;
  }
}

class _SearchSuggestionThumb extends StatelessWidget {
  const _SearchSuggestionThumb({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.imageUrls.isNotEmpty ? product.imageUrls.first : '';
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFF9F4EF),
        borderRadius: BorderRadius.circular(999),
      ),
      clipBehavior: Clip.hardEdge,
      child: imageUrl.isNotEmpty
          ? Image.network(
              ModelPathHelper.normalize(imageUrl),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                CupertinoIcons.photo,
                size: 14,
                color: CupertinoColors.systemGrey,
              ),
            )
          : const Icon(
              CupertinoIcons.photo,
              size: 14,
              color: CupertinoColors.systemGrey,
            ),
    );
  }
}
