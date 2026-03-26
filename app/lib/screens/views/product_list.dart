import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../widgets/filters_sheet.dart';
import '../../models/product.dart';
import '../../utils/model_path_helper.dart';
import '../../widgets/underline_filter_bar.dart';
import 'product_detail.dart';
import '../../services/wishlist_service.dart';
import '../../services/cart_service.dart';
import '../../services/auth_service.dart';
import '../views/sign_in.dart';
import '../../widgets/toast.dart';
import '../../services/native_ar_editor_service.dart';

/// Product list screen with search and filter functionality.
/// Follows Apple HIG principles with clean layouts and smooth interactions.
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, required this.title, this.products});
  final String title;
  final List<Product>? products;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final WishlistService _wishlist = WishlistService();
  
  // Search and filter state
  String _searchQuery = '';
  FilterData? _activeFilters;

  // Category underline filter state (matches Likes screen UX).
  String _selectedCategory = 'All';

  // Color constants matching catalog_home.dart
  static const Color _kWalnut = Color(0xFF5C4033);
  static const Color _kTextPrimary = Color(0xFF6D4C41); // Medium brown for text
  static const Color _kBrown = Color(0xFF8D6E63); // Primary brown
  static const Color _kOrange = Color(0xFFFF9800); // Primary orange
  static const Color _kLight = Color(0xFFF4E6D4);

  // -------------------------------------------------------------
  // Lightweight in-memory search suggestions for this list view
  // -------------------------------------------------------------
  //
  // We derive suggestions from the same `products` collection that
  // powers the grid, so search behavior and results stay aligned.
  //
  // This only *previews* likely matches; the main grid is still
  // driven by `_filteredProducts`, so existing functionality remains
  // unchanged.
  // -------------------------------------------------------------
  List<Product> get _searchSuggestions {
    if (_searchQuery.isEmpty) return const [];

    final items = widget.products ?? const <Product>[];
    final query = _searchQuery;

    final matches = items.where((product) {
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

    const maxSuggestions = 6;
    if (matches.length <= maxSuggestions) {
      return matches;
    }
    return matches.sublist(0, maxSuggestions);
  }

  @override
  void initState() {
    super.initState();
    // Listen to search text changes for real-time filtering
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    // Listen to wishlist changes to update UI
    _wishlist.addListener(_onWishlistChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _wishlist.removeListener(_onWishlistChanged);
    super.dispose();
  }

  void _onWishlistChanged() {
    if (mounted) setState(() {});
  }

  /// Opens the filters sheet and applies the returned filter data
  Future<void> _openFilters() async {
    final result = await FiltersSheet.show(context, initialFilters: _activeFilters);
    if (result != null && mounted) {
      setState(() {
        _activeFilters = result;
      });
    }
  }

  /// Applies search query and filters to the product list
  List<Product> get _filteredProducts {
    var items = widget.products ?? const <Product>[];
    
    // Apply search query if present
    if (_searchQuery.isNotEmpty) {
      items = items.where((product) {
        return product.name.toLowerCase().contains(_searchQuery) ||
               product.description.toLowerCase().contains(_searchQuery) ||
               product.category.toLowerCase().contains(_searchQuery) ||
               product.style.toLowerCase().contains(_searchQuery) ||
               product.material.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    // Apply category filter (underline bar).
    if (_selectedCategory != 'All') {
      items = items.where((product) => product.category == _selectedCategory).toList();
    }
    
    // Apply filters if active
    if (_activeFilters != null && _activeFilters!.hasActiveFilters) {
      items = items.where((product) {
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
        
        // Color filter - check if product color matches any selected color
        // This is a simplified check - you may need to adjust based on your color matching logic
        if (_activeFilters!.colors.isNotEmpty) {
          // For now, we'll skip color filtering as it requires more complex matching
          // You can implement color matching logic here if needed
        }
        
        return true;
      }).toList();
    }
    
    return items;
  }

  List<String> _categoriesFor(List<Product> items) {
    final cats = items
        .map((p) => p.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...cats];
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredProducts;

    return CupertinoPageScaffold(
      // Enhanced background matching catalog_home.dart
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        previousPageTitle: 'Back',
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: _kWalnut,
        ),
        // Modern navigation bar with improved styling matching catalog_home.dart
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        middle: Text(
          widget.title,
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
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // -------------------------------------------------------
                    // Search bar with catalog_home.dart styling
                    // -------------------------------------------------------
                    //
                    // Search bar styling (copied from Likes screen):
                    // white field, walnut border, subtle shadow, clean icons.
                    // -------------------------------------------------------
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _kWalnut.withValues(alpha: 0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.search,
                            color: _kWalnut.withValues(alpha: 0.75),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CupertinoTextField(
                              controller: _searchController,
                              placeholder: 'Search furniture or keywords',
                              placeholderStyle: GoogleFonts.poppins(
                                fontSize: 14,
                                color: _kWalnut.withValues(alpha: 0.45),
                              ),
                              decoration: null,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: const Color(0xFF5F5B56),
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
                                        color: _kWalnut.withValues(alpha: 0.75),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Filter button with indicator matching catalog_home.dart style
                          Stack(
                            children: [
                              CupertinoButton(
                                padding: const EdgeInsets.all(8),
                                minimumSize: Size.zero,
                                borderRadius: BorderRadius.circular(10),
                                color: _activeFilters?.hasActiveFilters == true
                                    ? _kOrange
                                    : _kLight,
                                onPressed: _openFilters,
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
                    // -------------------------------------------------------
                    // Suggestions preview panel
                    // -------------------------------------------------------
                    //
                    // This panel animates in/out under the search bar, giving
                    // the user a quick peek at matching products. Tapping a
                    // suggestion:
                    // - Syncs the text field with the product name
                    // - Navigates using the existing detail screen
                    //
                    // The main grid remains driven by `_filteredProducts`.
                    // -------------------------------------------------------
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _searchSuggestions.isEmpty
                          ? const SizedBox.shrink()
                          : Container(
                              key: const ValueKey('product_list_search_suggestions'),
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
                                      // Align the query with the tapped suggestion
                                      // and open the existing detail flow.
                                      _searchController.text = product.name;
                                      Navigator.of(context, rootNavigator: true).push(
                                        CupertinoPageRoute(
                                          builder: (_) => ProductDetailScreen(product: product),
                                        ),
                                      );
                                    },
                                    child: Row(
                                      children: [
                                        // Small circular thumb-style preview matching catalog_home.dart
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
                                            environmentImage: 'neutral',
                                            exposure: 1.35,
                                            shadowIntensity: 0.18,
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
                                                '${product.category} • ₱${product.price.toStringAsFixed(0)}',
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
                    const SizedBox(height: 12),
                    if ((widget.products ?? const <Product>[]).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: UnderlineFilterBar(
                          entries: _categoriesFor(widget.products ?? const <Product>[]).map(
                            (c) => UnderlineFilterEntry(key: c, label: c),
                          ).toList(),
                          selectedKey: _selectedCategory,
                          onSelect: (key) => setState(() => _selectedCategory = key),
                          walnut: _kWalnut,
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No products found',
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = items[index];
                      return _ProductGridCard(
                        product: product,
                        wishlist: _wishlist,
                        onTap: () {
                          // Navigate to product detail screen
                          Navigator.of(context, rootNavigator: true).push(
                            CupertinoPageRoute(
                              builder: (_) => ProductDetailScreen(product: product),
                            ),
                          );
                        },
                      );
                    },
                    childCount: items.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72, // Slightly reduced to prevent overflow
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Product grid card matching catalog_home.dart _HorizontalProductCard styling
/// Adapted for grid layout with enhanced shadows and modern design
class _ProductGridCard extends StatefulWidget {
  const _ProductGridCard({
    required this.product,
    required this.wishlist,
    required this.onTap,
  });
  final Product product;
  final WishlistService wishlist;
  final VoidCallback onTap;

  // Color constants matching catalog_home.dart
  static const Color _kTextPrimary = Color(0xFF6D4C41); // Medium brown for text
  static const Color _kBrown = Color(0xFF8D6E63); // Primary brown

  @override
  State<_ProductGridCard> createState() => _ProductGridCardState();
}

class _ProductGridCardState extends State<_ProductGridCard> {
  final CartService _cart = CartService();
  final AuthService _auth = AuthService();

  /// Launches the native Kotlin AR editor for this product.
  ///
  /// This bypasses the web/Scene Viewer pipeline and hands control directly to
  /// the native AR editor, which is where SceneView / ARCore will live.
  /// Keeping the call here lets the card stay focused on UI concerns only.
  Future<void> _openNativeArEditor() {
    return NativeArEditorService.openForProduct(widget.product);
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
    widget.wishlist.toggle(widget.product);
    HapticFeedback.selectionClick();
    final isWishlisted = widget.wishlist.isWishlisted(widget.product.id);
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
    final isWishlisted = widget.wishlist.isWishlisted(widget.product.id);
    
    // Enhanced card design matching catalog_home.dart _HorizontalProductCard
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: widget.onTap,
      child: Container(
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
            // Product image with overlay buttons matching catalog_home.dart style
            // Wrap entire Stack in GestureDetector to make image area clickable
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
                      color: isWishlisted ? CupertinoColors.systemRed : const Color(0xFF8D6E63),
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
                      color: const Color(0xFF8D6E63),
                    ),
                  ),
                ),
                // AR Editor button at bottom right (per request)
                //
                // Placement rationale (Apple HIG):
                // - Bottom-right is a natural "next action" corner in a card.
                // - Keeps AR separate from Wishlist/Cart (top corners).
                // - Overlay affordance stays within the image so the card body
                //   remains clean and scannable.
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
            const SizedBox(height: 4),
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
                    color: _ProductGridCard._kTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Price and quantity - also clickable
            GestureDetector(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '₱${widget.product.price.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                        color: _ProductGridCard._kBrown,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Qty: ${widget.product.inventoryQty}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: _ProductGridCard._kTextPrimary.withValues(alpha: 0.6),
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


