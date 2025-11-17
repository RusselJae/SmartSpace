import 'package:flutter/cupertino.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../services/wishlist_service.dart';
import '../../models/product.dart';
import '../views/product_detail.dart';

/// =============================================================
/// WishlistScreen
///
/// Lists saved products with remove and navigation.
/// =============================================================
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  final WishlistService _wishlist = WishlistService();

  @override
  void initState() {
    super.initState();
    _wishlist.addListener(_onChanged);
  }

  @override
  void dispose() {
    _wishlist.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _open(Product product) {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _wishlist.items;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Wishlist'),
      ),
      child: SafeArea(
        child: items.isEmpty
            ? const Center(child: Text('Your saved items will appear here.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final product = items[index];
                  return _WishlistRow(
                    product: product,
                    onOpen: () => _open(product),
                    onRemove: () => _wishlist.remove(product.id),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: items.length,
              ),
      ),
    );
  }
}

class _WishlistRow extends StatelessWidget {
  const _WishlistRow({required this.product, required this.onOpen, required this.onRemove});
  final Product product;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onOpen,
      child: Container(
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
                src: product.modelPath,
                alt: '3D preview of ${product.name}',
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
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('\$${product.price.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF6D4C41))),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(6),
              minimumSize: Size.zero,
              onPressed: onRemove,
              child: const Icon(CupertinoIcons.heart_slash, color: CupertinoColors.systemRed),
            )
          ],
        ),
      ),
    );
  }
}


