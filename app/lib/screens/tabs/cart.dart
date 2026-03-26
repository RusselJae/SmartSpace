import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../config/api_config.dart';
import '../../models/cart_item.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../utils/model_path_helper.dart';
import '../../widgets/toast.dart';
import '../checkout/order_summary_screen.dart';
import '../views/sign_in.dart';

// Matches wishlist tile: resolve GLB URLs for web; peso formatting for cart rows/footer.
final NumberFormat _cartPesoFormat = NumberFormat('#,##0.00', 'en_US');

String _formatCartPeso(double amount) => '₱${_cartPesoFormat.format(amount)}';

bool _productHasModel(Product p) {
  final src = p.modelPath.trim();
  if (src.isEmpty) return false;
  return src.toLowerCase().endsWith('.glb') || src.toLowerCase().endsWith('.gltf');
}

String? _productResolvedModelSrc(Product p) {
  final raw = p.modelPath.trim();
  if (raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  final apiUri = Uri.parse(ApiConfig.baseUrl);
  final origin = apiUri.origin;
  if (raw.startsWith('/uploads/')) return '$origin$raw';
  if (raw.startsWith('uploads/')) return '$origin/$raw';
  if (raw.contains('backend/uploads/')) {
    final idx = raw.indexOf('backend/uploads/');
    final tail = raw.substring(idx + 'backend/'.length);
    return '$origin/$tail';
  }
  return ModelPathHelper.normalize(raw);
}

bool _productHasNetworkImage(Product p) {
  if (p.imageUrls.isEmpty) return false;
  final first = p.imageUrls.first.trim();
  return first.startsWith('http://') || first.startsWith('https://');
}

/// Same priority as [Wishlist] tiles: GLB model when available, else first network image.
Widget _buildCartLineThumbnail(Product product) {
  if (_productHasModel(product)) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Center(
          child: Icon(
            CupertinoIcons.cube_box,
            color: Colors.black26,
            size: 22,
          ),
        ),
        IgnorePointer(
          ignoring: true,
          child: ModelViewer(
            backgroundColor: Colors.transparent,
            src: _productResolvedModelSrc(product) ?? product.modelPath,
            alt: '3D preview of ${product.name}',
            ar: false,
            environmentImage: 'neutral',
            exposure: 1.35,
            shadowIntensity: 0.18,
            autoRotate: false,
            cameraControls: false,
            disableZoom: true,
          ),
        ),
      ],
    );
  }
  if (_productHasNetworkImage(product)) {
    return Image.network(
      product.imageUrls.first,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(
          CupertinoIcons.photo,
          color: Colors.black26,
          size: 22,
        ),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CupertinoActivityIndicator(radius: 10));
      },
    );
  }
  return const Center(
    child: Icon(
      CupertinoIcons.cube_box,
      color: Colors.black26,
      size: 22,
    ),
  );
}

/// =============================================================
/// CartScreen
///
/// Shows cart items with quantity controls and totals.
/// =============================================================
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CartService _cart = CartService();
  final Set<String> _selectedProductIds = {};
  final Set<String> _knownProductIds = {};

  @override
  void initState() {
    super.initState();
    _syncSelection();
    _cart.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
    super.dispose();
  }

  void _syncSelection() {
    final currentIds = _cart.items.map((item) => item.product.id).toSet();
    _selectedProductIds.removeWhere((id) => !currentIds.contains(id));
    _knownProductIds.removeWhere((id) => !currentIds.contains(id));

    for (final id in currentIds) {
      if (!_knownProductIds.contains(id)) {
        _knownProductIds.add(id);
        _selectedProductIds.add(id);
      }
    }
  }

  void _onCartChanged() {
    if (!mounted) return;
    setState(() {
      _syncSelection();
    });
  }

  void _toggleSelection(String productId) {
    setState(() {
      if (_selectedProductIds.contains(productId)) {
        _selectedProductIds.remove(productId);
      } else {
        _selectedProductIds.add(productId);
      }
    });
  }

  void _toggleSelectAll() {
    final items = _cart.items;
    setState(() {
      if (_selectedProductIds.length == items.length) {
        _selectedProductIds.clear();
      } else {
        _selectedProductIds
          ..clear()
          ..addAll(items.map((item) => item.product.id));
      }
    });
  }

  void _proceedToCheckout(BuildContext context) {
    final selectedIds = _selectedProductIds.toSet();
    final selectedItems = _cart.items.where((item) => selectedIds.contains(item.product.id)).toList();

    if (selectedItems.isEmpty) {
      Toast.info(context, 'Select at least one product');
      return;
    }

    // Check if user is logged in before proceeding to checkout
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

    // Use rootNavigator to hide tab bar when navigating to order summary
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => OrderSummaryScreen(productIds: selectedIds.toList()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _cart.items;
    final cartTotal = _cart.totalPrice;
    final selectedItems = items.where((item) => _selectedProductIds.contains(item.product.id)).toList();
    final selectedCount = selectedItems.length;
    final selectedTotal = selectedItems.fold<double>(0.0, (sum, item) => sum + item.subtotal);

    const lightBrown = Color(0xFFF4E6D4);
    const kWalnut = Color(0xFF5D4037);
    
    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: lightBrown,
        border: Border(
          bottom: BorderSide(
            color: kWalnut.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        middle: Text(
          'Cart',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: kWalnut,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Selected $selectedCount / ${items.length}',
                        style: GoogleFonts.poppins(
                          color: kWalnut,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      minimumSize: Size.zero,
                      color: Colors.transparent,
                      onPressed: _toggleSelectAll,
                      child: Text(
                        _selectedProductIds.length == items.length ? 'Clear All' : 'Select All',
                        style: GoogleFonts.poppins(
                          color: kWalnut,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'Your cart is empty',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF5D4037).withValues(alpha: 0.75),
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                  : ListView.separated(
                      // Add bottom padding to prevent content from being blocked by tab bar
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemBuilder: (context, index) {
                        final CartItem item = items[index];
                        return _SwipeableCartRow(
                          key: ValueKey(item.product.id),
                          item: item,
                          selected: _selectedProductIds.contains(item.product.id),
                          onToggleSelected: () => _toggleSelection(item.product.id),
                          onIncrement: () {
                            _cart.increment(item.product.id);
                          },
                          onDecrement: () {
                            _cart.decrement(item.product.id);
                          },
                          onRemove: () {
                            _cart.remove(item.product.id);
                            _selectedProductIds.remove(item.product.id);
                            _knownProductIds.remove(item.product.id);
                            Toast.info(context, '${item.product.name} removed from cart');
                          },
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: items.length,
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground,
                border: Border(top: BorderSide(color: CupertinoColors.separator)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF5D4037),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatCartPeso(selectedTotal),
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF5D4037),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (selectedCount < items.length) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Cart total: ${_formatCartPeso(cartTotal)}',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF5D4037).withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    minimumSize: Size.zero,
                    color: selectedCount == 0
                        ? CupertinoColors.systemGrey4
                        : const Color(0xFF5D4037),
                    borderRadius: BorderRadius.circular(10),
                    onPressed: selectedCount == 0 ? null : () => _proceedToCheckout(context),
                    child: Text(
                      selectedCount == items.length
                          ? 'Proceed to Checkout'
                          : 'Checkout ($selectedCount)',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: selectedCount == 0 ? Colors.grey : Colors.white,
                        decoration: TextDecoration.none,
                      ),
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

/// Swipeable cart row with delete button revealed on swipe left (Shopee style)
/// Swipe left at least 1/4 of the row to reveal delete button on the right side
/// Delete button is clickable and does NOT auto-delete
class _SwipeableCartRow extends StatefulWidget {
  const _SwipeableCartRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onToggleSelected,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });
  final CartItem item;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  State<_SwipeableCartRow> createState() => _SwipeableCartRowState();
}

class _SwipeableCartRowState extends State<_SwipeableCartRow> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragOffset = 0.0;
  static const double _deleteButtonWidth = 80.0; // Fixed width for delete button

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Only allow swiping left (negative delta)
    if (details.delta.dx < 0) {
      setState(() {
        _dragOffset += details.delta.dx;
        // Clamp to maximum delete button width
        if (_dragOffset < -_deleteButtonWidth) {
          _dragOffset = -_deleteButtonWidth;
        }
        if (_dragOffset > 0) {
          _dragOffset = 0;
        }
      });
    } else if (details.delta.dx > 0 && _dragOffset < 0) {
      // Allow swiping back to the right
      setState(() {
        _dragOffset += details.delta.dx;
        if (_dragOffset > 0) {
          _dragOffset = 0;
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    // Manual slide control: position remains exactly where user left it
    // No auto-snap behavior - user controls the position completely
    // Clamp the position to valid bounds
    setState(() {
      if (_dragOffset < -_deleteButtonWidth) {
        _dragOffset = -_deleteButtonWidth;
      } else if (_dragOffset > 0) {
        _dragOffset = 0.0;
      }
      // Position stays at current _dragOffset value - no animation, no reset
    });
  }


  void _handleDeleteTap() {
    HapticFeedback.mediumImpact();
    widget.onRemove();
    // Reset position after delete
    setState(() {
      _dragOffset = 0.0;
    });
    _controller.reset();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          // Delete button background (revealed when swiped) - positioned on the right
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: _deleteButtonWidth,
                decoration: const BoxDecoration(
                  color: CupertinoColors.systemRed,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _handleDeleteTap,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            CupertinoIcons.delete,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Delete',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Cart row that slides over the delete button
          // Manual slide control: position persists until user manually changes it
          GestureDetector(
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            // Position remains until manually changed - no auto-reset
            child: Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: _CartRow(
                item: widget.item,
                selected: widget.selected,
                onToggleSelected: widget.onToggleSelected,
                onIncrement: widget.onIncrement,
                onDecrement: widget.onDecrement,
                onRemove: widget.onRemove,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cart row widget without delete button (delete is handled by swipe)
class _CartRow extends StatefulWidget {
  const _CartRow({
    required this.item,
    required this.selected,
    required this.onToggleSelected,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });
  final CartItem item;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  State<_CartRow> createState() => _CartRowState();
}

class _CartRowState extends State<_CartRow> {
  final TextEditingController _quantityController = TextEditingController();
  bool _isEditing = false; // Track if user is currently editing the field

  @override
  void initState() {
    super.initState();
    _quantityController.text = widget.item.quantity.toString();
  }

  @override
  void didUpdateWidget(_CartRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update quantity field when item quantity changes externally (but not while user is editing)
    if (oldWidget.item.quantity != widget.item.quantity && !_isEditing) {
      _quantityController.text = widget.item.quantity.toString();
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _updateQuantity(int newQuantity) {
    if (newQuantity < 1) return;
    final currentQuantity = widget.item.quantity;
    final difference = newQuantity - currentQuantity;
    
    // Update quantity by calling increment/decrement the required number of times
    if (difference > 0) {
      for (int i = 0; i < difference; i++) {
        widget.onIncrement();
      }
    } else if (difference < 0) {
      for (int i = 0; i < difference.abs(); i++) {
        widget.onDecrement();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color kWalnut = Color(0xFF5D4037);

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            child: Center(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: widget.onToggleSelected,
                child: Icon(
                  widget.selected
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                  color: widget.selected ? kWalnut : const Color(0xFFBCAAA4),
                  size: 26,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.hardEdge,
            child: _buildCartLineThumbnail(widget.item.product),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Line 1: product name (left, 1 line + ellipsis) — total (far right).
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        widget.item.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: kWalnut,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatCartPeso(widget.item.subtotal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: kWalnut,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Line 2: unit price (left) — qty stepper (right), same vertical center.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _formatCartPeso(widget.item.unitPrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: kWalnut.withValues(alpha: 0.72),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          color: kWalnut,
                          borderRadius: BorderRadius.zero,
                          onPressed: widget.onDecrement,
                          child: const Icon(
                            CupertinoIcons.minus,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.zero,
                            border: Border.all(
                              color: kWalnut.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: CupertinoTextField(
                            controller: _quantityController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: kWalnut,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                            decoration: const BoxDecoration(),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (value) {
                              if (!_isEditing) {
                                setState(() {
                                  _isEditing = true;
                                });
                              }
                            },
                            onSubmitted: (value) {
                              setState(() {
                                _isEditing = false;
                              });
                              final newQuantity = int.tryParse(value);
                              if (newQuantity == null || newQuantity < 1) {
                                _quantityController.text = widget.item.quantity.toString();
                              } else {
                                _updateQuantity(newQuantity);
                                _quantityController.text = widget.item.quantity.toString();
                              }
                              _quantityController.selection = TextSelection.fromPosition(
                                TextPosition(offset: _quantityController.text.length),
                              );
                            },
                            onTap: () {
                              setState(() {
                                _isEditing = true;
                              });
                              _quantityController.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: _quantityController.text.length,
                              );
                            },
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          color: kWalnut,
                          borderRadius: BorderRadius.zero,
                          onPressed: widget.onIncrement,
                          child: const Icon(
                            CupertinoIcons.plus,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


