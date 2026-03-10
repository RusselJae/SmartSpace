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

    final query = _searchQuery;

    // Simple scoring: we reuse the same fields as `_applyFilters`,
    // so search behavior stays consistent with the main list.
    final matches = _allProducts.where((product) {
      final name = product.name.toLowerCase();
      final description = product.description.toLowerCase();
      final category = product.category.toLowerCase();
      final style = product.style.toLowerCase();
      final material = product.material.toLowerCase();

      return name.contains(query) ||
          description.contains(query) ||
          category.contains(query) ||
          style.contains(query) ||
          material.contains(query);
    }).toList();

    // To keep the UI lightweight and very "Apple-style", we only
    // surface a small handful of top matches here.
    const maxSuggestions = 6;
    if (matches.length <= maxSuggestions) {
      return matches;
    }
    return matches.sublist(0, maxSuggestions);
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
        _allProducts = results[0];
        _newArrivals = results[1];
        _topRatedProducts = results[2];
        _bestSellerProducts = results[3];
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
    final categoryProducts = _allProducts
        .where((product) => product.category.toLowerCase() == category.toLowerCase())
        .toList();
    
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => ProductListScreen(
          title: category,
          products: categoryProducts,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Remove 'Kids' category as requested
    const categories = [
      'Living Room', 'Dining', 'Bedroom', 'Office', 'Outdoor'
    ];

    return CupertinoPageScaffold(
      // Enhanced background with subtle gradient following Apple HIG
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        // Solid walnut navigation bar with white title
        backgroundColor: const Color(0xFF5C4033), // Walnut
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF4A3329).withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        middle: Text(
          'Wood Home Furniture Trading',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
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
                    // -------------------------------------------------------
                    // Search bar + live suggestions
                    // -------------------------------------------------------
                    //
                    // We keep the existing search bar behavior exactly the
                    // same, and simply *layer* a lightweight suggestion
                    // preview underneath it. This follows Apple HIG by:
                    // - Keeping the field visually anchored at the top
                    // - Using a soft card with subtle depth for suggestions
                    // - Making the suggestions fully tappable rows
                    // -------------------------------------------------------
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Primary search input
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
                        const SizedBox(height: 8),
                        // Animated suggestion preview panel.
                        // This collapses completely when there is no query or
                        // when there are no matches, so the rest of the layout
                        // (categories, sections, etc.) stays untouched.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _searchSuggestions.isEmpty
                              ? const SizedBox.shrink()
                              : Container(
                                  key: const ValueKey('catalog_search_suggestions'),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFBCAAA4).withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: _searchSuggestions.map((product) {
                                      return CupertinoButton(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        borderRadius: BorderRadius.zero,
                                        onPressed: () {
                                          // Keep the text field in sync with the tapped suggestion
                                          // and open the existing product detail screen.
                                          _searchController.text = product.name;
                                          _openProduct(context, product);
                                        },
                                        child: Row(
                                          children: [
                                            // Small circular thumb-style preview using the same model
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF9F4EF),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              clipBehavior: Clip.hardEdge,
                                              child: ModelViewer(
                                                key: ValueKey('${product.id}_suggestion'),
                                                backgroundColor: const Color(0xFFF9F4EF),
                                                src: ModelPathHelper.normalize(product.modelPath),
                                                alt: 'Preview of ${product.name}',
                                                ar: false,
                                                autoRotate: false,
                                                cameraControls: false,
                                                disableZoom: true,
                                                interactionPrompt: InteractionPrompt.none,
                                              ),
                                            ),
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
                                                      color: _kTextPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${product.category} • ₱${_CatalogHomeState.formatPrice(product.price)}',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 11,
                                                      color: _kTextPrimary.withValues(alpha: 0.6),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    // Categories section (only shown when not searching)
                    if (_searchQuery.isEmpty) ...[
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
                  ],
                ),
              ),
            ),
            // Categories horizontal list (only shown when not searching)
            if (_searchQuery.isEmpty)
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
                        child: _CategoryTile(
                          label: categories[i],
                          onTap: () => _navigateToCategory(categories[i]),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                  ),
                ),
              ),
            // Search Results section (shown when searching)
            if (_searchQuery.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Search Results',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _kTextPrimary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      Text(
                        '${_searchResults.length} ${_searchResults.length == 1 ? 'result' : 'results'}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: _kTextPrimary.withValues(alpha: 0.6),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 220,
                  child: _searchResults.isEmpty
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
                            final product = _searchResults[index];
                            return _HorizontalProductCard(
                              product: product,
                              onTap: () => _openProduct(context, product),
                            );
                          },
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemCount: _searchResults.length,
                        ),
                ),
              ),
            ],
            // New Arrival section (always shows all products, not filtered by search)
            if (_searchQuery.isEmpty) ...[
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
            // Top Rated section (only shown when not searching)
            if (_searchQuery.isEmpty) ...[
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
            // Best Seller section (only shown when not searching)
            if (_searchQuery.isEmpty) ...[
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
            // Product image with overlay buttons - make image area clickable
            Stack(
              children: [
                // Make the image area clickable by wrapping ModelViewer in GestureDetector
                GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque, // Make entire area tappable
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: ModelViewer(
                        key: ValueKey('${widget.product.id}_preview'),
                        backgroundColor: const Color(0xFFF9F4EF),
                        src: ModelPathHelper.normalize(widget.product.modelPath),
                        alt: 'Preview of ${widget.product.name}',
                        ar: false,
                        autoRotate: false,
                        cameraControls: false,
                        disableZoom: true,
                        interactionPrompt: InteractionPrompt.none,
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
            // Product name - also clickable
            GestureDetector(
              onTap: widget.onTap,
              child: Padding(
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
            ),
            const SizedBox(height: 3),
            // Price and quantity - also clickable
            GestureDetector(
              onTap: widget.onTap,
              child: Padding(
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
            ),
          ],
        ),
      ),
    );
  }
}
