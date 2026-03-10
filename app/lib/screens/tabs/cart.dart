import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../checkout/order_summary_screen.dart';
import '../views/sign_in.dart';
import '../../services/cart_service.dart';
import '../../services/auth_service.dart';
import '../../models/cart_item.dart';
import '../../widgets/toast.dart';

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

    // Light brown color for navigation bar
    const lightBrown = Color(0xFFF4E6D4);
    const mediumBrown = Color(0xFF8D6E63);
    
    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: lightBrown,
        border: Border(
          bottom: BorderSide(
            color: mediumBrown.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        middle: Text(
          'Cart',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: mediumBrown,
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
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: const Color(0xFFF0E6E0),
                      borderRadius: BorderRadius.circular(20),
                      onPressed: _toggleSelectAll,
                      child: Text(
                        _selectedProductIds.length == items.length ? 'Clear All' : 'Select All',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF8D6E63),
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
                          color: Colors.black,
                          fontSize: 16,
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
                          'Selected Total',
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₱${selectedTotal.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (selectedCount < items.length) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Cart total: ₱${cartTotal.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              color: Colors.black.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  CupertinoButton.filled(
                    onPressed: selectedCount == 0 ? null : () => _proceedToCheckout(context),
                    child: Text(
                      selectedCount == items.length
                          ? 'Proceed to Checkout'
                          : 'Checkout ($selectedCount)',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
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
    // Color constants matching catalog_home.dart
    const Color kBrown = Color(0xFF8D6E63); // Primary brown
    const Color kLight = Color(0xFFF4E6D4); // Light color

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(6), // Further reduced from 8 to 6 to fix overflow
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox button with minimal constraints
          SizedBox(
            width: 24,
            height: 24,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: widget.onToggleSelected,
              child: Icon(
                widget.selected ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
                // Light brown when inactive, normal brown when active
                color: widget.selected ? kBrown : const Color(0xFFBCAAA4),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 4), // Reduced from 6 to 4
          Container(
            width: 60, // Further reduced from 64 to 60
            height: 60, // Further reduced from 64 to 60
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey4,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.hardEdge,
            child: ModelViewer(
              backgroundColor: const Color(0xFFEFEFEF),
              src: widget.item.product.modelPath,
              alt: '3D preview of ${widget.item.product.name}',
              ar: false,
              autoRotate: false,
              cameraControls: false,
              disableZoom: true,
            ),
          ),
          const SizedBox(width: 6), // Further reduced from 8 to 6
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF8D6E63), // Brown instead of black
                    fontSize: 14, // Further reduced from 15 to 14
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2), // Reduced from 3 to 2
                Text(
                  '₱${widget.item.unitPrice.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF5F5B56), // Dark grey instead of black
                    fontSize: 13, // Further reduced from 14 to 13
                    fontWeight: FontWeight.normal,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4), // Reduced from 6 to 4
                // Quantity controls with input field matching product detail screen
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Minus button matching catalog_home.dart style
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Further reduced padding
                      minimumSize: Size.zero,
                      color: kLight,
                      borderRadius: BorderRadius.circular(6), // Further reduced from 8 to 6
                      onPressed: widget.onDecrement,
                      child: const Icon(CupertinoIcons.minus, size: 14, color: kBrown), // Further reduced from 16 to 14
                    ),
                    const SizedBox(width: 4), // Reduced from 6 to 4
                    // Input field for quantity
                    Container(
                      width: 40, // Further reduced from 45 to 40
                      height: 28, // Further reduced from 32 to 28
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: kBrown.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: CupertinoTextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.black,
                          fontSize: 14, // Reduced from 16 to 14
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                        decoration: const BoxDecoration(),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), // Further reduced padding
                        inputFormatters: [
                          // Only allow numeric input
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) {
                          // Mark as editing when user starts typing
                          if (!_isEditing) {
                            setState(() {
                              _isEditing = true;
                            });
                          }
                        },
                        onSubmitted: (value) {
                          // Update quantity only when user finishes editing (on submit)
                          setState(() {
                            _isEditing = false;
                          });
                          final newQuantity = int.tryParse(value);
                          if (newQuantity == null || newQuantity < 1) {
                            // Invalid input, revert to current quantity
                            _quantityController.text = widget.item.quantity.toString();
                          } else {
                            // Update quantity to the new value
                            _updateQuantity(newQuantity);
                            // Sync controller with actual quantity (may differ if cart has limits)
                            _quantityController.text = widget.item.quantity.toString();
                          }
                          // Move cursor to end
                          _quantityController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _quantityController.text.length),
                          );
                        },
                        onTap: () {
                          // Select all text when user taps to edit
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
                    const SizedBox(width: 4), // Reduced from 6 to 4
                    // Plus button matching catalog_home.dart style
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Further reduced padding
                      minimumSize: Size.zero,
                      color: kLight,
                      borderRadius: BorderRadius.circular(6), // Further reduced from 8 to 6
                      onPressed: widget.onIncrement,
                      child: const Icon(CupertinoIcons.plus, size: 14, color: kBrown), // Further reduced from 16 to 14
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Vertical divider to separate product info from total price
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: CupertinoColors.separator.withValues(alpha: 0.3),
            ),
          ),
          // Price display - use SizedBox to prevent overflow instead of Flexible
          SizedBox(
            width: 75, // Fixed width to prevent overflow
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  '₱${widget.item.subtotal.toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF8D6E63), // Brown instead of black
                    fontSize: 13, // Further reduced from 14 to 13
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


