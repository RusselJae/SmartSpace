import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../widgets/filters_sheet.dart';
import '../../models/product.dart';
import 'product_detail.dart';
import '../../services/wishlist_service.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key, required this.title, this.products});
  final String title;
  final List<Product>? products;

  @override
  Widget build(BuildContext context) {
    final items = products ?? const <Product>[];
    final wishlist = WishlistService();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: CupertinoColors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.search, color: CupertinoColors.black),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: CupertinoTextField(
                          placeholder: 'Search products',
                          decoration: null,
                          padding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.all(6),
                        minimumSize: Size.zero,
                        borderRadius: BorderRadius.circular(20),
                        color: const Color(0xFFBCAAA4),
                        onPressed: () => FiltersSheet.show(context),
                        child: const Icon(CupertinoIcons.slider_horizontal_3, color: Color(0xFF4E342E)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No products found')),
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
                          Navigator.of(context).push(
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
                                      icon: wishlist.isWishlisted(product.id) ? CupertinoIcons.heart_solid : CupertinoIcons.heart,
                                      onPressed: () {
                                        wishlist.toggle(product);
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
                                  style: const TextStyle(inherit: true, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                    '\$${product.price.toStringAsFixed(0)}',
                                  style: const TextStyle(inherit: true, color: Color(0xFF6D4C41)),
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
      child: Icon(icon, size: 18, color: const Color(0xFF4E342E)),
    );
  }
}


