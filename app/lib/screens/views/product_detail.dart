import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:intl/intl.dart';

import '../../models/product.dart';
import '../../models/review.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/mysql_database_service.dart';
import '../../services/wishlist_service.dart';
import '../../widgets/toast.dart';
import '../../utils/model_path_helper.dart';
import 'ar_launcher.dart';
import 'sign_in.dart';
import '../checkout/order_summary_screen.dart';

/// =============================================================
/// ProductDetailScreen
///
/// Shows product imagery, specs, reviews, availability, and actions.
/// Currently placeholders wired to demonstrate the flow.
/// =============================================================
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});
  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final CartService _cart = CartService();
  final AuthService _auth = AuthService();
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  
  int _quantity = 1;
  final TextEditingController _quantityController = TextEditingController();
  late final WishlistService _wishlist;
  late bool _wishlisted;

  // Color constants matching catalog_home.dart
  static const Color _kBrown = Color(0xFF8D6E63); // Primary brown
  static const Color _kOrange = Color(0xFFFF9800); // Primary orange
  static const Color _kLight = Color(0xFFF4E6D4); // Light color
  
  // Reviews state
  List<Review> _reviews = [];
  bool _reviewsLoading = true;
  bool _hasPurchased = false;
  bool _purchaseCheckLoading = true;
  String? _reviewsError; // Track errors loading reviews

  void _openArView() {
    HapticFeedback.selectionClick();
    // Directly launch Google's ARCore Scene Viewer with real-world dimensions
    // This ensures furniture displays at accurate size in AR
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => ArLauncherScreen(
          modelSrc: ModelPathHelper.normalize(widget.product.modelPath),
          altText: widget.product.name,
          realWidthMeters: widget.product.realWidthMeters,
          realHeightMeters: widget.product.realHeightMeters,
          realDepthMeters: widget.product.realDepthMeters,
          modelBaseScale: widget.product.modelBaseScale,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _wishlist = WishlistService();
    _wishlisted = _wishlist.isWishlisted(widget.product.id);
    _quantityController.text = _quantity.toString();
    _loadReviews();
    _checkPurchaseStatus();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  /// Load all published reviews for this product from ALL users
  /// This ensures that any user viewing the product can see reviews from other users
  Future<void> _loadReviews() async {
    if (mounted) {
      setState(() {
        _reviewsLoading = true;
        _reviewsError = null; // Clear any previous errors
      });
    }
    
    try {
      final productId = widget.product.id;
      developer.log('🔄 Loading reviews for product: $productId');
      developer.log('📦 Product name: ${widget.product.name}');
      
      // Get ALL published reviews for this product, regardless of which user wrote them
      final reviews = await _db.getReviewsByProductId(productId);
      developer.log('📊 Received ${reviews.length} reviews from database for product $productId');
      
      // Log review details for debugging
      if (reviews.isNotEmpty) {
        developer.log('📝 Review details:');
        for (final review in reviews) {
          developer.log('  👤 Review ID: ${review.id}');
          developer.log('     User: ${review.userName} (userId: ${review.userId})');
          developer.log('     Product ID: ${review.productId} (matches: ${review.productId == productId})');
          developer.log('     Rating: ${review.rating} stars');
          developer.log('     Status: ${review.status}');
          developer.log('     Content: ${review.content.substring(0, review.content.length > 50 ? 50 : review.content.length)}...');
        }
      } else {
        developer.log('⚠️ No reviews returned from database');
        developer.log('💡 This could mean:');
        developer.log('   1. No reviews have been created for this product yet');
        developer.log('   2. All reviews have non-published status');
        developer.log('   3. Product ID mismatch (check database)');
      }
      
      if (mounted) {
        setState(() {
          // Store ALL reviews - no filtering by current user
          _reviews = reviews;
          _reviewsLoading = false;
          _reviewsError = null;
        });
        developer.log('✅ Displaying ${_reviews.length} reviews in UI');
        
        // Log if no reviews found
        if (reviews.isEmpty) {
          developer.log('⚠️ No reviews found for product $productId');
        }
      }
    } catch (e, stackTrace) {
      developer.log('❌ Error loading reviews: $e');
      developer.log('📚 Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _reviewsLoading = false;
          _reviewsError = 'Failed to load reviews. Please try again.';
          // Keep existing reviews if any, don't clear on error
        });
      }
    }
  }

  /// Check if the current user has purchased this product
  Future<void> _checkPurchaseStatus() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _hasPurchased = false;
        _purchaseCheckLoading = false;
      });
      return;
    }

    setState(() => _purchaseCheckLoading = true);
    try {
      final hasPurchased = await _db.hasUserPurchasedProduct(user.id, widget.product.id);
      if (mounted) {
        setState(() {
          _hasPurchased = hasPurchased;
          _purchaseCheckLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasPurchased = false;
          _purchaseCheckLoading = false;
        });
      }
    }
  }

  /// Handle writing a review for this product
  Future<void> _handleWriteReview() async {
    final user = _auth.currentUser;
    if (user == null) {
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (_) => const SignInScreen(),
          fullscreenDialog: true,
        ),
      );
      Toast.info(context, 'Please sign in to write a review');
      return;
    }

    if (!_hasPurchased) {
      Toast.info(context, 'You can only review products you have purchased');
      return;
    }

    // Check if user has already reviewed this product
    final existingReview = _reviews.firstWhere(
      (r) => r.userId == user.id,
      orElse: () => Review(
        id: '',
        productId: '',
        productName: '',
        userId: '',
        userName: '',
        rating: 0,
        content: '',
        status: '',
        createdAt: DateTime.now(),
      ),
    );
    if (existingReview.id.isNotEmpty) {
      Toast.info(context, 'You have already reviewed this product');
      return;
    }

    // Navigate to review composer
    final review = await Navigator.of(context, rootNavigator: true).push<Review>(
      CupertinoPageRoute(
        builder: (_) => _ProductReviewComposerPage(
          product: widget.product,
          user: user,
          db: _db,
        ),
        fullscreenDialog: true,
      ),
    );

    if (review != null && mounted) {
      // Reload reviews to show the new one
      await _loadReviews();
      if (!mounted) return;
      Toast.success(context, 'Review submitted!');
    }
  }

  void _inc() {
    setState(() {
      _quantity += 1;
      _quantityController.text = _quantity.toString();
      _quantityController.selection = TextSelection.fromPosition(
        TextPosition(offset: _quantityController.text.length),
      );
    });
    HapticFeedback.selectionClick();
  }

  void _dec() {
    if (_quantity > 1) {
      setState(() {
        _quantity -= 1;
        _quantityController.text = _quantity.toString();
        _quantityController.selection = TextSelection.fromPosition(
          TextPosition(offset: _quantityController.text.length),
        );
      });
      HapticFeedback.selectionClick();
    }
  }

  void _addToCart() {
    // Prevent adding to cart if out of stock
    if (!widget.product.inStock) {
      Toast.info(context, 'This product is currently out of stock');
      return;
    }

    final auth = AuthService();
    if (!auth.isAuthenticated) {
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
    
    _cart.add(widget.product, quantity: _quantity);
    HapticFeedback.mediumImpact();
    Toast.success(
      context,
      '${widget.product.name} added to cart',
    );
  }

  void _buyNow() {
    // Prevent buying if out of stock
    if (!widget.product.inStock) {
      Toast.info(context, 'This product is currently out of stock');
      return;
    }

    final auth = AuthService();
    if (!auth.isAuthenticated) {
      // Redirect to sign in screen as fullscreen dialog to hide navigation bar
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (_) => const SignInScreen(),
          fullscreenDialog: true,
        ),
      );
      Toast.info(context, 'Please sign in to checkout');
      return;
    }
    
    _cart.add(widget.product, quantity: _quantity);
    HapticFeedback.mediumImpact();
    // Use rootNavigator to hide tab bar when navigating to order summary
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => OrderSummaryScreen(productIds: [widget.product.id]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        middle: Text('Product', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ----------------------------
            // 3D Card with overlay actions
            // ----------------------------
            Stack(
              children: [
                // 3D AR-enabled model view with Google's AR button
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: ModelViewer(
                    key: ValueKey('${product.id}_detail'),
                    backgroundColor: const Color(0xFFF9F4EF),
                    src: ModelPathHelper.normalize(product.modelPath),
                    alt: '3D model of ${product.name}',
                    ar: true,
                    arModes: const ['scene-viewer'],
                    arPlacement: ArPlacement.floor,
                    arScale: ArScale.auto,
                    autoRotate: false,
                    cameraControls: true,
                    disableZoom: false,
                    interactionPrompt: InteractionPrompt.none,
                  ),
                ),
                // Review button at top-right of the product card
                // Only show if user has purchased the product
                if (_hasPurchased && !_purchaseCheckLoading)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _OverlayIconButton(
                      icon: CupertinoIcons.text_bubble,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _handleWriteReview();
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: Use AR inside the card. WebXR button lights up when browser-based AR is available.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 12),
            // ----------------------------
            // Title + Wishlist toggle on right
            // ----------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: const EdgeInsets.all(6),
                  minimumSize: Size.zero,
                  color: _wishlisted 
                      ? CupertinoColors.systemRed.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(18),
                  onPressed: () {
                    final wasWishlisted = _wishlisted;
                    setState(() {
                      _wishlist.toggle(product);
                      _wishlisted = _wishlist.isWishlisted(product.id);
                      HapticFeedback.selectionClick();
                    });
                    if (!wasWishlisted && _wishlisted) {
                      Toast.success(context, '${product.name} added to wishlist');
                    } else if (wasWishlisted && !_wishlisted) {
                      Toast.info(context, '${product.name} removed from wishlist');
                    }
                  },
                  child: Icon(
                    _wishlisted ? CupertinoIcons.heart_solid : CupertinoIcons.heart,
                    size: 18,
                    color: _wishlisted 
                        ? CupertinoColors.systemRed 
                        : const Color(0xFF8D6E63),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ----------------------------
            // Product Image Gallery
            // ----------------------------
            if (product.imageUrls.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Product Images',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: product.imageUrls.length > 10 ? 10 : product.imageUrls.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final imageUrl = product.imageUrls[index];
                        return GestureDetector(
                          onTap: () {
                            // Show full screen image viewer
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) => _FullScreenImageViewer(
                                  images: product.imageUrls,
                                  initialIndex: index,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: CupertinoColors.separator.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: CupertinoColors.systemGrey4,
                                  child: const Icon(
                                    CupertinoIcons.photo,
                                    color: CupertinoColors.systemGrey,
                                  ),
                                );
                              },
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  color: CupertinoColors.systemGrey4,
                                  child: const Center(
                                    child: CupertinoActivityIndicator(),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              '₱${product.price.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 12),
            // Quantity controls with input field matching catalog_home.dart styling
            Row(
              children: [
                Text(
                  'Quantity',
                  style: GoogleFonts.poppins(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(width: 12),
                // Minus button matching catalog_home.dart style
                _QtyButton(icon: CupertinoIcons.minus, onPressed: _dec),
                const SizedBox(width: 8),
                // Input field for quantity
                Container(
                  width: 80,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _kBrown.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: CupertinoTextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                    decoration: const BoxDecoration(),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    onChanged: (value) {
                      // Validate and update quantity
                      final newQuantity = int.tryParse(value);
                      if (newQuantity != null && newQuantity >= 1) {
                        setState(() {
                          _quantity = newQuantity;
                        });
                      } else if (value.isEmpty) {
                        // Allow empty temporarily while typing
                      } else {
                        // Invalid input, revert
                        _quantityController.text = _quantity.toString();
                        _quantityController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _quantityController.text.length),
                        );
                      }
                    },
                    onSubmitted: (value) {
                      // Ensure valid quantity on submit
                      final newQuantity = int.tryParse(value);
                      if (newQuantity == null || newQuantity < 1) {
                        _quantityController.text = _quantity.toString();
                      } else {
                        setState(() {
                          _quantity = newQuantity;
                          _quantityController.text = _quantity.toString();
                        });
                      }
                      _quantityController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _quantityController.text.length),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Plus button matching catalog_home.dart style
                _QtyButton(icon: CupertinoIcons.plus, onPressed: _inc),
              ],
            ),
            const SizedBox(height: 16),
            Text(
            '${product.description}\n\nSpecifications:\n- Category: ${product.category}\n- Style: ${product.style}\n- Material: ${product.material}\n- Color: ${product.color}',
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Colors.black,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '⭐ ${product.rating.toStringAsFixed(1)} (${product.reviewCount.toString()} reviews)',
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Colors.black,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 16),
            // Availability with stock quantity when out of stock
            Text(
              product.inStock 
                  ? 'Availability: In stock (${product.inventoryQty} available)\nDelivery estimate: 3-5 days'
                  : 'Availability: Out of stock (${product.inventoryQty} available)\nDelivery estimate: 3-5 days',
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: product.inStock ? Colors.black : Colors.red.shade700,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 20),
            // ----------------------------
            // Bottom action buttons (non-floating)
            // ----------------------------
            Row(
              children: [
                // "Add to Cart" button matching catalog_home.dart filter button style
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      // Use _kLight background matching catalog_home.dart filter button
                      color: product.inStock ? _kLight : CupertinoColors.systemGrey4,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: product.inStock 
                            ? _kBrown.withValues(alpha: 0.3) 
                            : Colors.grey.withValues(alpha: 0.3), 
                        width: 1,
                      ),
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: product.inStock ? _addToCart : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.cart, 
                            size: 20, 
                            color: product.inStock ? _kBrown : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Add to Cart',
                            style: GoogleFonts.poppins(
                              color: product.inStock ? _kBrown : Colors.grey,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // "Buy Now" button with gradient matching catalog_home.dart style
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      // Gradient matching catalog_home.dart button style
                      gradient: product.inStock
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_kBrown, _kOrange],
                            )
                          : null,
                      color: product.inStock ? null : CupertinoColors.systemGrey4,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: product.inStock
                          ? [
                              BoxShadow(
                                color: _kOrange.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                                spreadRadius: 0,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: product.inStock ? _buyNow : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.creditcard, 
                            size: 20, 
                            color: product.inStock ? CupertinoColors.white : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Buy Now',
                            style: GoogleFonts.poppins(
                              color: product.inStock ? CupertinoColors.white : Colors.grey,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // ----------------------------
            // Reviews Section (moved below buttons)
            // ----------------------------
            _buildReviewsSection(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Build the reviews section showing all published reviews for this product
  Widget _buildReviewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header row with Reviews title and Write Review button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Reviews title
            Expanded(
              child: Text(
                'Reviews (${_reviews.length})',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            // Write Review button - only show if user has purchased
            if (_hasPurchased && !_purchaseCheckLoading)
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _handleWriteReview,
                child: Text(
                  'Write Review',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF8D6E63),
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Reviews content area with proper width constraints
        if (_reviewsLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CupertinoActivityIndicator(),
            ),
          )
        else if (_reviewsError != null)
          // Error state with retry button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: CupertinoColors.systemRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: CupertinoColors.systemRed.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  size: 48,
                  color: CupertinoColors.systemRed,
                ),
                const SizedBox(height: 12),
                Text(
                  _reviewsError!,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.systemRed,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                CupertinoButton(
                  color: const Color(0xFF8D6E63),
                  onPressed: _loadReviews,
                  child: Text(
                    'Retry',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (_reviews.isEmpty)
          // Empty state with proper width
          SizedBox(
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.chat_bubble,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No reviews yet',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Be the first to review this product',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.black54,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          // Display all reviews with proper width constraints
          ..._reviews.map((review) => _buildReviewCard(review)),
      ],
    );
  }

  /// Build a single review card with proper width constraints
  Widget _buildReviewCard(Review review) {
    return Container(
      width: double.infinity, // Ensure full width
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row with user name and rating
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User name - takes available space
              Expanded(
                child: Text(
                  review.userName,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                    decoration: TextDecoration.none,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Star rating - fixed width to prevent overflow
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (index) => Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      index < review.rating ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      size: 16,
                      color: index < review.rating ? const Color(0xFFFFC107) : Colors.black26,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Review content - properly constrained width with text wrapping
          SizedBox(
            width: double.infinity, // Ensure full width
            child: Text(
              review.content,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.left,
              softWrap: true, // Enable text wrapping
              overflow: TextOverflow.visible, // Allow text to wrap instead of ellipsis
            ),
          ),
          const SizedBox(height: 8),
          // Review date
          Text(
            _dateFormat.format(review.createdAt),
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.black54,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  // Color constants matching catalog_home.dart
  static const Color _kBrown = Color(0xFF8D6E63); // Primary brown
  static const Color _kLight = Color(0xFFF4E6D4); // Light color

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: Size.zero,
      // Use _kLight background matching catalog_home.dart filter button style
      color: _kLight,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      child: Icon(icon, size: 18, color: _kBrown),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

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

/// Full-screen image viewer for product images
class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({
    required this.images,
    this.initialIndex = 0,
  });

  final List<String> images;
  final int initialIndex;

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Colors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.black,
        previousPageTitle: 'Back',
        middle: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      child: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.images.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          itemBuilder: (context, index) {
            return Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  widget.images[index],
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(
                        CupertinoIcons.photo,
                        color: Colors.white,
                        size: 64,
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CupertinoActivityIndicator(color: Colors.white),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Review composer page for writing a review on a specific product.
/// Only accessible from the product detail screen.
class _ProductReviewComposerPage extends StatefulWidget {
  const _ProductReviewComposerPage({
    required this.product,
    required this.user,
    required this.db,
  });

  final Product product;
  final User user;
  final MySQLDatabaseService db;

  @override
  State<_ProductReviewComposerPage> createState() => _ProductReviewComposerPageState();
}

class _ProductReviewComposerPageState extends State<_ProductReviewComposerPage> with SingleTickerProviderStateMixin {
  int _rating = 5;
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final FocusNode _focusNode = FocusNode();
  static const int _minReviewLength = 10;
  static const int _maxReviewLength = 500;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
    
    // Listen to text changes for real-time validation
    _controller.addListener(() {
      if (_error != null && _controller.text.trim().length >= _minReviewLength) {
        setState(() => _error = null);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// Get the current character count
  int get _characterCount => _controller.text.length;
  
  /// Check if review is valid
  bool get _isValid => _controller.text.trim().length >= _minReviewLength && _rating > 0;

  Future<void> _submit() async {
    // Validate minimum length
    if (_controller.text.trim().length < _minReviewLength) {
      HapticFeedback.mediumImpact();
      setState(() {
        _error = 'Please share at least $_minReviewLength characters.';
      });
      _focusNode.requestFocus();
      return;
    }

    // Validate maximum length
    if (_controller.text.length > _maxReviewLength) {
      HapticFeedback.mediumImpact();
      setState(() {
        _error = 'Review must be less than $_maxReviewLength characters.';
      });
      return;
    }

    // Validate rating
    if (_rating < 1 || _rating > 5) {
      HapticFeedback.mediumImpact();
      setState(() {
        _error = 'Please select a rating.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    HapticFeedback.mediumImpact();

    try {
      final review = await widget.db.createReview(
        productId: widget.product.id,
        productName: widget.product.name,
        userId: widget.user.id,
        userName: widget.user.fullName,
        rating: _rating,
        content: _controller.text.trim(),
      );
      if (!mounted) return;
      
      // Success haptic feedback
      HapticFeedback.mediumImpact();
      
      // Small delay for better UX
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (!mounted) return;
      Navigator.of(context).pop(review);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final errorMessage = e.toString();
      setState(() {
        if (errorMessage.contains('purchased')) {
          _error = 'You can only review products you have purchased';
        } else if (errorMessage.contains('already reviewed')) {
          _error = 'You have already reviewed this product';
        } else if (errorMessage.contains('API request failed')) {
          // Extract the actual error message from API response
          final match = RegExp(r'API request failed.*?:\s*(.+)').firstMatch(errorMessage);
          _error = match != null 
              ? match.group(1) ?? 'Failed to submit review. Please try again.'
              : 'Failed to submit review. Please check your connection and try again.';
        } else {
          _error = 'Failed to submit review. Please try again.';
        }
        _submitting = false;
      });
    }
  }

  void _updateRating(int newRating) {
    if (_submitting) return;
    HapticFeedback.selectionClick();
    setState(() {
      _rating = newRating;
      if (_error != null && _isValid) {
        _error = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF9F4EF),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFFF9F4EF),
        middle: Text(
          'Write a review',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: Colors.black,
          ),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _submitting ? null : () {
            HapticFeedback.selectionClick();
            Navigator.of(context).maybePop();
          },
          child: const Icon(
            CupertinoIcons.back,
            color: Color(0xFF8D6E63),
            size: 28,
          ),
        ),
      ),
      child: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 8),
              // Product info card with elegant design
              _buildProductCard(),
              const SizedBox(height: 32),
              // Rating section with improved UI
              _buildRatingSection(),
              const SizedBox(height: 32),
              // Review text area with character count
              _buildReviewTextArea(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _buildErrorBanner(),
              ],
              const SizedBox(height: 32),
              // Submit button with improved design
              _buildSubmitButton(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the product info card
  Widget _buildProductCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Product icon placeholder
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.cube_box,
              color: Color(0xFF8D6E63),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reviewing',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.product.name,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                    decoration: TextDecoration.none,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the rating section with animated stars
  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rating',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 16),
        // Star rating with spring animation
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (index) => GestureDetector(
              onTap: _submitting ? null : () => _updateRating(index + 1),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0.0,
                  end: index < _rating ? 1.0 : 0.0,
                ),
                duration: Duration(milliseconds: 200 + (index * 50)),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: index < _rating ? 1.0 + (value * 0.1) : 1.0,
                    child: Icon(
                      index < _rating ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      size: 44,
                      color: index < _rating 
                          ? const Color(0xFFFFC107) 
                          : Colors.black26,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Rating label
        Center(
          child: Text(
            _rating == 0 
                ? 'Tap to rate'
                : _rating == 5 
                    ? 'Excellent! ⭐'
                    : _rating == 4 
                        ? 'Great! 👍'
                        : _rating == 3 
                            ? 'Good 👍'
                            : _rating == 2 
                                ? 'Fair'
                                : 'Poor',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: _rating == 0 
                  ? Colors.black54 
                  : const Color(0xFF8D6E63),
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }

  /// Build the review text area with character count
  Widget _buildReviewTextArea() {
    final bool isNearLimit = _characterCount > _maxReviewLength * 0.9;
    final bool isOverLimit = _characterCount > _maxReviewLength;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Your review',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            ),
            // Character count
            Text(
              '$_characterCount / $_maxReviewLength',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: isOverLimit 
                    ? CupertinoColors.systemRed 
                    : isNearLimit 
                        ? const Color(0xFFFF9800) 
                        : Colors.black54,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Text field with improved styling
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _error != null 
                  ? CupertinoColors.systemRed 
                  : _focusNode.hasFocus 
                      ? const Color(0xFF8D6E63) 
                      : CupertinoColors.systemGrey4,
              width: _focusNode.hasFocus ? 2 : 1,
            ),
            boxShadow: _focusNode.hasFocus
                ? [
                    BoxShadow(
                      color: const Color(0xFF8D6E63).withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: CupertinoTextField(
            controller: _controller,
            focusNode: _focusNode,
            placeholder: 'Share your thoughts about the product...\n\nWhat did you like? What could be improved?',
            minLines: 6,
            maxLines: 8,
            maxLength: _maxReviewLength,
            style: GoogleFonts.poppins(
              color: Colors.black,
              fontSize: 15,
              height: 1.5,
            ),
            placeholderStyle: GoogleFonts.poppins(
              color: Colors.black45,
              fontSize: 15,
              height: 1.5,
            ),
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(),
          ),
        ),
        const SizedBox(height: 8),
        // Helper text
        Text(
          'Minimum $_minReviewLength characters required',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: _controller.text.trim().length < _minReviewLength 
                ? Colors.black54 
                : const Color(0xFF2E7D32),
            fontWeight: FontWeight.w400,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  /// Build error banner with animation
  Widget _buildErrorBanner() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: CupertinoColors.systemRed.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_circle_fill,
                    color: CupertinoColors.systemRed,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: GoogleFonts.poppins(
                        color: CupertinoColors.systemRed,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build submit button with improved design and animations
  Widget _buildSubmitButton() {
    final bool canSubmit = _isValid && !_submitting && _characterCount <= _maxReviewLength;
    
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: canSubmit ? 1.0 : 0.6),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: canSubmit
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF8D6E63), Color(0xFFFF9800)],
                    )
                  : null,
              color: canSubmit ? null : CupertinoColors.systemGrey4,
              borderRadius: BorderRadius.circular(28),
              boxShadow: canSubmit
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: canSubmit ? _submit : null,
              child: _submitting
                  ? const CupertinoActivityIndicator(
                      color: Colors.white,
                      radius: 12,
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          CupertinoIcons.check_mark_circled_solid,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Submit Review',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 0.5,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

