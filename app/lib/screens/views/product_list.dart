import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../widgets/filters_sheet.dart';
import '../../models/product.dart';
import 'product_detail.dart';
import '../../services/wishlist_service.dart';

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

  @override
  void initState() {
    super.initState();
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
        
        // Size filter
        if (_activeFilters!.size != 'M' && product.size != _activeFilters!.size) {
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

  @override
  Widget build(BuildContext context) {
    final items = _filteredProducts;

    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        middle: Text(widget.title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: CupertinoColors.separator.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.search,
                        color: const Color(0xFF6D4C41).withValues(alpha: 0.5),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CupertinoTextField(
                          controller: _searchController,
                          placeholder: 'Search products',
                          placeholderStyle: GoogleFonts.poppins(color: CupertinoColors.placeholderText),
                          decoration: null,
                          padding: const EdgeInsets.symmetric(vertical: 4),
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
                                    color: const Color(0xFF6D4C41).withValues(alpha: 0.5),
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
                            padding: const EdgeInsets.all(6),
                            minimumSize: Size.zero,
                            borderRadius: BorderRadius.circular(20),
                            color: _activeFilters?.hasActiveFilters == true
                                ? const Color(0xFFFF9800)
                                : const Color(0xFFBCAAA4),
                            onPressed: _openFilters,
                            child: Icon(
                              CupertinoIcons.slider_horizontal_3,
                              color: _activeFilters?.hasActiveFilters == true
                                  ? Colors.white
                                  : const Color(0xFF8D6E63),
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
                      return CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          // Use rootNavigator to hide tab bar when navigating to product detail
                          Navigator.of(context, rootNavigator: true).push(
                            CupertinoPageRoute(
                              builder: (_) => ProductDetailScreen(product: product),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: CupertinoColors.secondarySystemGroupedBackground,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  // 3D preview of the product's GLB model
                                  Container(
                                    height: 140,
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemGrey4,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    ),
                                    clipBehavior: Clip.hardEdge,
                                    child: ModelViewer(
                                      backgroundColor: const Color(0xFFEFEFEF),
                                      src: product.modelPath,
                                      alt: '3D preview of ${product.name}',
                                      ar: false,
                                      autoRotate: false,
                                      cameraControls: false,
                                      disableZoom: true,
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: _OverlayIconButton(
                                      icon: CupertinoIcons.cube_box,
                                      onPressed: () {},
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: _OverlayIconButton(
                                      icon: _wishlist.isWishlisted(product.id) ? CupertinoIcons.heart_solid : CupertinoIcons.heart,
                                      onPressed: () {
                                        _wishlist.toggle(product);
                                        HapticFeedback.selectionClick();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  product.name,
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  '₱${product.price.toStringAsFixed(0)}',
                                  style: GoogleFonts.poppins(color: const Color(0xFF6D4C41)),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: items.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.all(6),
      minimumSize: Size.zero,
      color: const Color(0xFFBCAAA4),
      borderRadius: BorderRadius.circular(18),
      onPressed: onPressed,
      child: Icon(icon, size: 18, color: const Color(0xFF8D6E63)),
    );
  }
}


