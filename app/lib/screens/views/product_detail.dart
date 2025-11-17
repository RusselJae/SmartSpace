import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../models/product.dart';
import '../../services/cart_service.dart';
import '../../services/wishlist_service.dart';

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

  @override
  void initState() {
    super.initState();
    _wishlist = WishlistService();
    _wishlisted = _wishlist.isWishlisted(widget.product.id);
  }

  void _inc() => setState(() => _quantity += 1);
  void _dec() => setState(() {
    if (_quantity > 1) _quantity -= 1;
  });

  void _addToCart() {
    _cart.add(widget.product, quantity: _quantity);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final product = widget.product;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Product'),
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
              ],
            ),
            const SizedBox(height: 8),
            const Text('Tip: Use the AR button in the viewer to place this item in your room.'),
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
                    style: theme.textTheme.textStyle.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
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
                    setState(() {
                      _wishlist.toggle(product);
                      _wishlisted = _wishlist.isWishlisted(product.id);
                      HapticFeedback.selectionClick();
                    });
                  },
                  child: Icon(
                    _wishlisted ? CupertinoIcons.heart_solid : CupertinoIcons.heart,
                    size: 18,
                    color: const Color(0xFF4E342E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '\$${product.price.toStringAsFixed(2)}',
              style: theme.textTheme.textStyle.copyWith(
                color: const Color(0xFF6D4C41),
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            // Quantity controls still inline with content
            Row(
              children: [
                const Text('Quantity'),
                const SizedBox(width: 8),
                _QtyButton(icon: CupertinoIcons.minus, onPressed: _dec),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(_quantity.toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                _QtyButton(icon: CupertinoIcons.plus, onPressed: _inc),
              ],
            ),
            const SizedBox(height: 16),
            Text('${product.description}\n\nSpecifications:\n- Category: ${product.category}\n- Style: ${product.style}\n- Material: ${product.material}\n- Color: ${product.color}\n- Size: ${product.size}'),
            const SizedBox(height: 16),
            Text('⭐ ${product.rating.toStringAsFixed(1)} (${product.reviewCount.toString()} reviews)'),
            const SizedBox(height: 16),
            Text('Availability: ${product.inStock ? 'In stock' : 'Out of stock'}\nDelivery estimate: 3-5 days'),

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
                        children: const [
                          Icon(CupertinoIcons.cart, size: 20, color: Color(0xFF5D4037)),
                          SizedBox(width: 10),
                          Text('Add to Cart', style: TextStyle(inherit: true, color: Color(0xFF5D4037), fontWeight: FontWeight.w700)),
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
                        colors: [Color(0xFF6D4C41), Color(0xFF4E342E)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: product.inStock ? _addToCart : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(CupertinoIcons.creditcard, size: 20, color: CupertinoColors.white),
                          SizedBox(width: 10),
                          Text('Buy Now', style: TextStyle(inherit: true, color: CupertinoColors.white, fontWeight: FontWeight.w800)),
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
      child: Icon(icon, size: 16, color: const Color(0xFF4E342E)),
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
      child: Icon(icon, size: 18, color: const Color(0xFF4E342E)),
    );
  }
}


