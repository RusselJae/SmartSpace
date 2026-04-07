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
import '../../services/native_ar_editor_service.dart';
import '../../services/wishlist_service.dart';
import '../../widgets/cached_model_src_loader.dart';
import '../../widgets/toast.dart';
import '../../utils/model_path_helper.dart';
import 'made_to_order_request_screen.dart';
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

  // Brand / walnut palette (detail screen actions & accents).
  /// Solid walnut for primary actions (no gradient).
  static const Color _kWalnut = Color(0xFF5D4037);
  /// Muted label for secondary lines (category, captions).
  static const Color _kMuted = Color(0xFF757575);

  /// Insets around the bottom purchase actions (breathing room).
  static const double _kPurchaseBarVerticalPad = 12;
  static const double _kPurchaseBarHorizontalPad = 12;
  static const double _kPurchaseBarButtonHeight = 48;
  /// Button fills: 80% transparent (20% opacity).
  static const double _kPurchaseButtonFillOpacity = 0.2;
  /// Scroll padding below reviews (reduced 90% from prior 4px).
  static const double _kListScrollBottomGap = 0;

  static final NumberFormat _pesoPriceFormat = NumberFormat('#,##0.00', 'en_US');

  // Reviews state
  List<Review> _reviews = [];
  bool _reviewsLoading = true;
  bool _hasPurchased = false;
  bool _purchaseCheckLoading = true;
  String? _reviewsError; // Track errors loading reviews
  bool _hasReviewed = false; // Current user has already reviewed this product

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

  /// Same native AR entry point as catalog / product list cards (SceneView / ARCore).
  Future<void> _openNativeArEditor() {
    return NativeArEditorService.openForProduct(widget.product);
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
        // includePending=true so we also show reviews that are not explicitly 'published'
        // (e.g., legacy rows or reviews pending at the time of migration).
        final reviewsByProductId = await _db.getReviewsByProductId(
        productId,
        includePending: true,
      );

        developer.log('📊 Received ${reviewsByProductId.length} reviews from database for product $productId');

        // Fallback: if the productId-filtered query returns nothing but the user claims
        // they've reviewed, attempt a broader fetch and filter on the client.
        // This makes the UI robust against any backend query/filter mismatch.
        List<Review> reviews = reviewsByProductId;
        if (reviews.isEmpty) {
          developer.log(
            '⚠️ No reviews returned for productId=$productId. Falling back to getAllReviews() filter.',
          );
          final allReviews = await _db.getAllReviews();
          reviews = allReviews.where((r) => r.productId == productId).toList();
          developer.log(
            '✅ Fallback found ${reviews.length} reviews for productId=$productId',
          );
        }
      
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
          final user = _auth.currentUser;
          _hasReviewed = user != null && reviews.any((r) => r.userId == user.id);
        });
        developer.log(
          '🧾 Reviews state: productId=$productId reviews=${_reviews.length} currentUser=${_auth.currentUser?.id} hasReviewed=$_hasReviewed',
        );
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

    // If the user already reviewed this product, do not open the composer again.
    // The backend enforces the same rule; this is purely UX.
    if (_hasReviewed) {
      Toast.info(context, 'You already submitted a review for this product');
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
      // Reload reviews to show the new one.
      // If the refresh comes back empty (e.g., backend query/filter mismatch),
      // still inject the returned review so the UI reflects the submission.
      await _loadReviews();
      if (!mounted) return;

      setState(() {
        final alreadyExists = _reviews.any((r) => r.id == review.id);
        if (_reviews.isEmpty || !alreadyExists) {
          _reviews.insert(0, review);
        }
        _hasReviewed = true;
      });
      Toast.success(context, 'Review submitted!');
    }
  }

  void _inc() {
    final maxQty = widget.product.inStock
        ? widget.product.inventoryQty.clamp(1, 999999)
        : 1;
    if (_quantity >= maxQty) {
      HapticFeedback.selectionClick();
      return;
    }
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
    
    final maxQty = widget.product.inventoryQty.clamp(1, 999999);
    final q = _quantity.clamp(1, maxQty);
    if (q != _quantity) {
      setState(() {
        _quantity = q;
        _quantityController.text = _quantity.toString();
      });
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
    
    final maxQty = widget.product.inventoryQty.clamp(1, 999999);
    final q = _quantity.clamp(1, maxQty);
    if (q != _quantity) {
      setState(() {
        _quantity = q;
        _quantityController.text = _quantity.toString();
      });
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
        previousPageTitle: 'Back',
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: _kWalnut,
        ),
        middle: Text('Product', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  // Clears floating bar: vertical inset + button row + small tail gap.
                  _kListScrollBottomGap +
                      MediaQuery.paddingOf(context).bottom +
                      _kPurchaseBarVerticalPad +
                      _kPurchaseBarButtonHeight,
                ),
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey4,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: CachedModelSrcLoader(
                          sourceUrl: ModelPathHelper.normalize(product.modelPath),
                          builder: (context, resolvedSrc) => ModelViewer(
                            key: ValueKey('${product.id}_detail'),
                            backgroundColor: const Color(0xFFF9F4EF),
                            src: resolvedSrc,
                            alt: '3D model of ${product.name}',
                            // Match catalog cards: in-viewer AR off; use overlay cube → native editor.
                            ar: false,
                            environmentImage: 'neutral',
                            exposure: 1.35,
                            shadowIntensity: 0.18,
                            autoRotate: false,
                            cameraControls: true,
                            disableZoom: false,
                            interactionPrompt: InteractionPrompt.none,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          minimumSize: Size.zero,
                          color: Colors.transparent,
                          borderRadius: BorderRadius.zero,
                          onPressed: () {
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
                            size: 22,
                            color: _wishlisted ? CupertinoColors.systemRed : _kWalnut,
                          ),
                        ),
                      ),
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
            const SizedBox(height: 8),
            Text(
              'Tip: Tap the cube to open AR with true-to-scale editing (same as the shop).',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatPesoPrice(product.price),
                        style: GoogleFonts.poppins(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.category,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: _kMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
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
                          builder: (_) => MadeToOrderRequestScreen(
                            prefilledProductName: product.name,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _kWalnut.withValues(alpha: 0.55), width: 1.3),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.wand_stars, color: _kWalnut, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Customize / Made to Order',
                            style: GoogleFonts.poppins(
                              color: _kWalnut,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStockQuantityBlock(product),
                  const SizedBox(height: 20),
                  Text(
                    'Description',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.description,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: Colors.black87,
                      fontWeight: FontWeight.normal,
                      height: 1.45,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSpecificationsSection(product),
                  const SizedBox(height: 16),
                  _buildDeliveryEstimateAboveGallery(),
                  if (product.imageUrls.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildProductImageGallery(product),
                  ],
                  const SizedBox(height: 20),
                  _buildReviewsSection(product),
                  const SizedBox(height: 0),
                ],
              ),
            ),
            _buildPurchaseBar(context, product),
          ],
        ),
      ),
    );
  }

  /// Specs: category removed; height / length / depth merged into this list (no dimensions card).
  Widget _buildSpecificationsSection(Product product) {
    final h = _formatMetersAsCm(product.realHeightMeters);
    final len = _formatMetersAsCm(product.realDepthMeters);
    final depth = _formatMetersAsCm(product.realWidthMeters);
    final hasComponents = product.components.isNotEmpty;
    final lines = <String>[
      if (!hasComponents && h != '-') '- Height: $h',
      if (!hasComponents && len != '-') '- Length: $len',
      if (!hasComponents && depth != '-') '- Depth: $depth',
      if (hasComponents) '- Set includes:',
      if (hasComponents) ...product.components.map((component) {
        final widthCm = _formatMetersAsCm(component.widthMeters);
        final heightCm = _formatMetersAsCm(component.heightMeters);
        final depthCm = _formatMetersAsCm(component.depthMeters);
        return '  - ${component.name} (x${component.quantity})'
            ' - W: $widthCm, H: $heightCm, D: $depthCm';
      }),
      '- Style: ${product.style}',
      '- Material: ${product.material}',
      '- Color: ${product.color}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Specifications',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          lines.join('\n'),
          style: GoogleFonts.poppins(
            fontSize: 15,
            color: Colors.black,
            fontWeight: FontWeight.normal,
            height: 1.5,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  /// Shown directly above the product photo strip (bold label + days on the next line).
  Widget _buildDeliveryEstimateAboveGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery Estimate',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '3-5 days',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.normal,
            color: Colors.black87,
            height: 1.5,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  Widget _buildProductImageGallery(Product product) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: product.imageUrls.length > 10 ? 10 : product.imageUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final imageUrl = product.imageUrls[index];
          return GestureDetector(
            onTap: () {
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
    );
  }

  /// Left: bold "Available Stock" + count. Right: quantity stepper (same row).
  Widget _buildStockQuantityBlock(Product product) {
    final maxQty = product.inStock ? product.inventoryQty.clamp(1, 999999) : 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Stock',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${product.inventoryQty}',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: product.inStock ? _kWalnut : Colors.red.shade700,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _QtyButton(
              icon: CupertinoIcons.minus,
              onPressed: product.inStock ? _dec : null,
              walnutStyle: true,
            ),
            const SizedBox(width: 6),
            Container(
              width: 44,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: _kWalnut.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: CupertinoTextField(
                controller: _quantityController,
                enabled: product.inStock,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
                decoration: const BoxDecoration(),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                onChanged: (value) {
                  final newQuantity = int.tryParse(value);
                  if (newQuantity != null && newQuantity >= 1) {
                    final capped = newQuantity > maxQty ? maxQty : newQuantity;
                    setState(() {
                      _quantity = capped;
                      if (capped != newQuantity) {
                        _quantityController.text = _quantity.toString();
                        _quantityController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _quantityController.text.length),
                        );
                      }
                    });
                  } else if (value.isEmpty) {
                  } else {
                    _quantityController.text = _quantity.toString();
                    _quantityController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _quantityController.text.length),
                    );
                  }
                },
                onSubmitted: (value) {
                  final newQuantity = int.tryParse(value);
                  if (newQuantity == null || newQuantity < 1) {
                    _quantityController.text = _quantity.toString();
                  } else {
                    final capped = newQuantity > maxQty ? maxQty : newQuantity;
                    setState(() {
                      _quantity = capped;
                      _quantityController.text = _quantity.toString();
                    });
                  }
                  _quantityController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _quantityController.text.length),
                  );
                },
              ),
            ),
            const SizedBox(width: 6),
            _QtyButton(
              icon: CupertinoIcons.plus,
              onPressed: product.inStock ? _inc : null,
              walnutStyle: true,
            ),
          ],
        ),
      ],
    );
  }

  /// Full-width bar pinned to the bottom; square buttons, solid walnut Buy Now.
  Widget _buildPurchaseBar(BuildContext context, Product product) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: CupertinoColors.separator.resolveFrom(context)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        _kPurchaseBarHorizontalPad,
        _kPurchaseBarVerticalPad,
        _kPurchaseBarHorizontalPad,
        bottomInset + _kPurchaseBarVerticalPad,
      ),
      child: SizedBox(
        height: _kPurchaseBarButtonHeight,
        child: Row(
          children: [
            Expanded(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.zero,
                onPressed: product.inStock ? _addToCart : null,
                color: Colors.transparent,
                child: Container(
                  height: _kPurchaseBarButtonHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: product.inStock
                        ? Colors.white.withValues(alpha: _kPurchaseButtonFillOpacity)
                        : CupertinoColors.systemGrey5
                            .withValues(alpha: _kPurchaseButtonFillOpacity),
                    border: Border.all(
                      color: product.inStock ? _kWalnut : Colors.grey.shade400,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.cart,
                        size: 20,
                        color: product.inStock ? _kWalnut : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Add to Cart',
                        style: GoogleFonts.poppins(
                          color: product.inStock ? _kWalnut : Colors.grey,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.zero,
                onPressed: product.inStock ? _buyNow : null,
                color: Colors.transparent,
                child: Container(
                  height: _kPurchaseBarButtonHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: product.inStock
                        ? _kWalnut
                        : CupertinoColors.systemGrey4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.creditcard,
                        size: 20,
                        color: product.inStock ? Colors.white : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Buy Now',
                        style: GoogleFonts.poppins(
                          color: product.inStock ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pesos with thousands separators, e.g. ₱15,000.00
  String _formatPesoPrice(double amount) => '₱${_pesoPriceFormat.format(amount)}';

  /// Formats meters -> centimeters and avoids ugly trailing zeros.
  /// Returns an empty string if `meters` is null/invalid.
  String _formatMetersAsCm(double? meters) {
    if (meters == null || meters <= 0) return '-';

    final cm = meters * 100;
    final rounded = cm.round();
    final diff = (cm - rounded).abs();

    // If it's effectively an integer, show as `120 cm` instead of `120.0 cm`.
    if (diff < 0.01) {
      return '$rounded cm';
    }
    return '${cm.toStringAsFixed(1)} cm';
  }

  /// Reviews list + aggregate rating in the header; composer CTA sits after the last (oldest) card.
  Widget _buildReviewsSection(Product product) {
    // Newest first so the last visible card is the oldest — "Write a review" follows it at the bottom.
    final sorted = List<Review>.from(_reviews)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final reviewsCount = _reviews.length;
    final averageRating = reviewsCount == 0
        ? 0.0
        : _reviews.fold<double>(0.0, (sum, review) => sum + review.rating) / reviewsCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  Text(
                    'Reviews ($reviewsCount)',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.star_fill,
                        size: 17,
                        color: Color(0xFFFFC107),
                      ),
                      Text(
                        ' ${averageRating.toStringAsFixed(1)} ',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      Text(
                        '($reviewsCount reviews)',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _kMuted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_hasPurchased && !_purchaseCheckLoading && _hasReviewed) ...[
          // Inline message in the reviews section so the user sees *why* the composer is disabled.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4E6D4).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF8D6E63).withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              'You already submitted a review for this product. Thank you.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6D4C41),
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Reviews content area with proper width constraints
        if (_reviewsLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
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
          ...sorted.map((review) => _buildReviewCard(review)),
        if (!_reviewsLoading && _reviewsError == null) ...[
          // Add clear breathing room between the reviews content and CTA.
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Builder(
              builder: (context) {
                final canReview =
                    _hasPurchased && !_purchaseCheckLoading && !_hasReviewed;
                return CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: canReview ? _handleWriteReview : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: canReview ? _kWalnut : Colors.grey.shade400,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'Write a review',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        color: canReview ? _kWalnut : Colors.grey,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Keep this nearly flush so there is no visible "dead gap"
          // between the CTA and the bottom of the reviews block.
          const SizedBox(height: 0),
        ],
      ],
    );
  }

  /// Build a single review card with proper width constraints
  Widget _buildReviewCard(Review review) {
    return Container(
      width: double.infinity, // Ensure full width
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kWalnut.withValues(alpha: 0.18),
          width: 1,
        ),
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
  const _QtyButton({
    required this.icon,
    required this.onPressed,
    this.walnutStyle = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool walnutStyle;

  static const Color _kBrown = Color(0xFF8D6E63);
  static const Color _kLight = Color(0xFFF4E6D4);
  static const Color _kWalnut = Color(0xFF5D4037);

  @override
  Widget build(BuildContext context) {
    if (walnutStyle) {
      final enabled = onPressed != null;
      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        color: enabled ? _kWalnut : CupertinoColors.systemGrey4,
        borderRadius: BorderRadius.zero,
        onPressed: onPressed,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? Colors.white : Colors.grey,
        ),
      );
    }
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: Size.zero,
      color: _kLight,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      child: Icon(icon, size: 18, color: _kBrown),
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
  int _rating = 0;
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
                duration: Duration(milliseconds: 160 + (index * 40)),
                curve: Curves.easeOutBack,
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

