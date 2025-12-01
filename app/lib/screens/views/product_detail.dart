import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../models/product.dart';
import '../../services/ar_support_service.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/wishlist_service.dart';
import '../../widgets/toast.dart';
import 'ar_view.dart';
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
  int _quantity = 1;
  late final WishlistService _wishlist;
  late bool _wishlisted;
  late Future<ArCapabilityResult> _capabilityFuture;

  @override
  void initState() {
    super.initState();
    _wishlist = WishlistService();
    _wishlisted = _wishlist.isWishlisted(widget.product.id);
    _capabilityFuture = ArSupportService.instance.resolveCapability();
  }

  void _inc() => setState(() => _quantity += 1);
  void _dec() => setState(() {
    if (_quantity > 1) _quantity -= 1;
  });

  void _addToCart() {
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
                // 3D AR-enabled model view
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
                    src: product.modelPath,
                    alt: '3D model of ${product.name}',
                    ar: true,
                    arModes: const ['scene-viewer'],
                    arPlacement: ArPlacement.floor,
                    arScale: ArScale.auto,
                    autoRotate: false,
                    cameraControls: true,
                    disableZoom: false,
                  ),
                ),
                // Review button at top-right of the product card
                Positioned(
                  top: 8,
                  right: 8,
                  child: _OverlayIconButton(
                    icon: CupertinoIcons.text_bubble,
                    onPressed: () {
                      // TODO: Hook to reviews section/screen
                      HapticFeedback.selectionClick();
                    },
                  ),
                ),
                // Dedicated WebXR launcher anchored bottom-left per design.
                // This keeps ARCore + WebXR flows separate and mirrors the new AR screen.
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: FutureBuilder<ArCapabilityResult>(
                    future: _capabilityFuture,
                    builder: (context, snapshot) {
                      final bool loading = snapshot.connectionState != ConnectionState.done;
                      final ArCapabilityResult? capability = snapshot.data;
                      final bool webXrReady = capability?.supportsWebXr == true && capability!.enableAr;
                      return _WebXrLaunchButton(
                        loading: loading,
                        enabled: webXrReady,
                        onPressed: webXrReady
                            ? () {
                                HapticFeedback.selectionClick();
                                Navigator.of(context).push(
                                  CupertinoPageRoute(
                                    builder: (_) => ArViewScreen(
                                      modelSrc: product.modelPath,
                                      altText: '3D model of ${product.name}',
                                      initialMode: ArViewMode.webxr,
                                    ),
                                  ),
                                );
                              }
                            : null,
                      );
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
                  color: const Color(0xFFBCAAA4),
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
                    color: const Color(0xFF8D6E63),
                  ),
                ),
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
            // Quantity controls still inline with content
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
                const SizedBox(width: 8),
                _QtyButton(icon: CupertinoIcons.minus, onPressed: _dec),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    _quantity.toString(),
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                _QtyButton(icon: CupertinoIcons.plus, onPressed: _inc),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${product.description}\n\nSpecifications:\n- Category: ${product.category}\n- Style: ${product.style}\n- Material: ${product.material}\n- Color: ${product.color}\n- Size: ${product.size}',
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
            Text(
              'Availability: ${product.inStock ? 'In stock' : 'Out of stock'}\nDelivery estimate: 3-5 days',
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Colors.black,
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
                // Outlined "Add to Cart" with icon
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F5F2),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF8D6E63), width: 1.2),
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: product.inStock ? _addToCart : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.cart, size: 20, color: Color(0xFF8D6E63)),
                          const SizedBox(width: 10),
                          Text(
                            'Add to Cart',
                            style: GoogleFonts.poppins(color: const Color(0xFF8D6E63), fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Filled "Buy Now" with icon
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8D6E63), Color(0xFFFF9800)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF9800).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: product.inStock ? _buyNow : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.creditcard, size: 20, color: CupertinoColors.white),
                          const SizedBox(width: 10),
                          Text(
                            'Buy Now',
                            style: GoogleFonts.poppins(color: CupertinoColors.white, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size.zero,
      color: const Color(0xFFBCAAA4),
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
      child: Icon(icon, size: 16, color: const Color(0xFF8D6E63)),
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

/// Chips-style launcher dedicated to WebXR preview.
class _WebXrLaunchButton extends StatelessWidget {
  const _WebXrLaunchButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Compact chip styling so the button feels like a control, not a CTA.
    // Web icon reinforces that this path opens Chrome's WebXR instead of native ARCore.
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: enabled ? Colors.white.withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(18),
      onPressed: enabled && !loading ? onPressed : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CupertinoActivityIndicator(radius: 8),
            )
          else
            Icon(
              CupertinoIcons.globe,
              size: 16,
              color: enabled ? const Color(0xFF8D6E63) : const Color(0xFF9CA3AF),
            ),
          const SizedBox(width: 6),
          Text(
            'WebXR',
            style: GoogleFonts.poppins(
              color: enabled ? const Color(0xFF8D6E63) : const Color(0xFF9CA3AF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


