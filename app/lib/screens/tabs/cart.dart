import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
        middle: Text('Cart', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
                        return _CartRow(
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

class _CartRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onToggleSelected,
            child: Icon(
              selected ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
              // Light brown when inactive, normal brown when active
              color: selected ? const Color(0xFF8D6E63) : const Color(0xFFBCAAA4),
              size: 26,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey4,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.hardEdge,
            child: ModelViewer(
              backgroundColor: const Color(0xFFEFEFEF),
              src: item.product.modelPath,
              alt: '3D preview of ${item.product.name}',
              ar: false,
              autoRotate: false,
              cameraControls: false,
              disableZoom: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₱${item.unitPrice.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.normal,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      color: const Color(0xFFBCAAA4),
                      borderRadius: BorderRadius.circular(8),
                      onPressed: onDecrement,
                      child: const Icon(CupertinoIcons.minus, size: 16, color: Color(0xFF8D6E63)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.quantity.toString(),
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      color: const Color(0xFFBCAAA4),
                      borderRadius: BorderRadius.circular(8),
                      onPressed: onIncrement,
                      child: const Icon(CupertinoIcons.plus, size: 16, color: Color(0xFF8D6E63)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                onPressed: onRemove,
                child: const Icon(CupertinoIcons.delete, color: CupertinoColors.systemRed, size: 20),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  '₱${item.subtotal.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


