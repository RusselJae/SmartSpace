import 'package:flutter/cupertino.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../checkout/address_screen.dart';
import '../../services/cart_service.dart';
import '../../models/cart_item.dart';

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

  void _proceedToCheckout(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => const AddressScreen()),
    );
  }

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _cart.items;
    final total = _cart.totalPrice;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Cart'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Your cart is empty'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemBuilder: (context, index) {
                        final CartItem item = items[index];
                        return _CartRow(
                          item: item,
                          onIncrement: () => _cart.increment(item.product.id),
                          onDecrement: () => _cart.decrement(item.product.id),
                          onRemove: () => _cart.remove(item.product.id),
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
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF4E342E))),
                      ],
                    ),
                  ),
                  CupertinoButton.filled(
                    onPressed: items.isEmpty ? null : () => _proceedToCheckout(context),
                    child: const Text('Proceed to Checkout'),
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
  const _CartRow({required this.item, required this.onIncrement, required this.onDecrement, required this.onRemove});
  final CartItem item;
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
        children: [
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
              children: [
                Text(
                  item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text('\$${item.product.price.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF6D4C41))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      color: const Color(0xFFBCAAA4),
                      borderRadius: BorderRadius.circular(8),
                      onPressed: onDecrement,
                      child: const Icon(CupertinoIcons.minus, size: 16, color: Color(0xFF4E342E)),
                    ),
                    const SizedBox(width: 8),
                    Text(item.quantity.toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      color: const Color(0xFFBCAAA4),
                      borderRadius: BorderRadius.circular(8),
                      onPressed: onIncrement,
                      child: const Icon(CupertinoIcons.plus, size: 16, color: Color(0xFF4E342E)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                onPressed: onRemove,
                child: const Icon(CupertinoIcons.delete, color: CupertinoColors.systemRed),
              ),
              const SizedBox(height: 8),
              Text('\$${item.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}


