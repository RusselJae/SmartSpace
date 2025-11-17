import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../views/product_detail.dart';
import '../views/product_list.dart';
import '../../widgets/filters_sheet.dart';
import '../../services/database_service.dart';
import '../../models/product.dart';

/// =============================================================
/// CatalogHome
///
/// Home screen with categories, search, filters, and personalized
/// recommendations. Now displays products from database.
/// =============================================================
class CatalogHome extends StatefulWidget {
  const CatalogHome({super.key});

  @override
  State<CatalogHome> createState() => _CatalogHomeState();
}

class _CatalogHomeState extends State<CatalogHome> {
  final DatabaseService _db = DatabaseService();
  List<Product> _allProducts = [];
  List<Product> _newArrivals = [];
  List<Product> _popularProducts = [];

  static const Color _kDark = Color(0xFF3E2723);
  static const Color _kBrown = Color(0xFF5D4037);
  static const Color _kLight = Color(0xFFF4E6D4);
  static const Color _kSurface = Color(0xFFFFFBF7);

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  void _loadProducts() {
    setState(() {
      _allProducts = _db.getAllProducts();
      _newArrivals = _db.getNewArrivalProducts();
      _popularProducts = _db.getPopularProducts();
    });
  }

  void _openProduct(BuildContext context, Product product) {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  void _openFilters(BuildContext context) {
    FiltersSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle headerStyle = GoogleFonts.poppins(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: _kDark,
    );

    final TextStyle sectionTitle = GoogleFonts.poppins(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: _kDark,
    );

    const categories = [
      'Living Room', 'Dining', 'Bedroom', 'Office', 'Outdoor', 'Kids'
    ];

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('SmartSpace'),
      ),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Custom white search with left search icon (black) and right filter icon (light brown)
                    Container(
                      decoration: BoxDecoration(
                        color: _kSurface,
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
                          const Icon(CupertinoIcons.search, color: _kDark),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: CupertinoTextField(
                              placeholder: 'Search furniture or keywords',
                              decoration: null,
                              padding: EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.all(6),
                            minimumSize: Size.zero,
                            borderRadius: BorderRadius.circular(20),
                            color: _kLight,
                            onPressed: () => _openFilters(context),
                            child: const Icon(CupertinoIcons.slider_horizontal_3, color: _kBrown),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Recommended for you', style: sectionTitle),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, i) {
                    return _CategoryTile(label: categories[i]);
                  },
                ),
              ),
            ),
            // New Arrival section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('New Arrival', style: headerStyle),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const ProductListScreen(title: 'New Arrival Products'),
                          ),
                        );
                      },
                      child: const Text('See all'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final product = index < _newArrivals.length 
                        ? _newArrivals[index] 
                        : _allProducts[index % _allProducts.length];
                    return _HorizontalProductCard(
                      product: product,
                      onTap: () => _openProduct(context, product),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemCount: _newArrivals.isNotEmpty ? _newArrivals.length : _allProducts.length,
                ),
              ),
            ),
            // Popular section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Popular', style: headerStyle),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const ProductListScreen(title: 'Popular Products'),
                          ),
                        );
                      },
                      child: const Text('See all'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final product = index < _popularProducts.length 
                        ? _popularProducts[index] 
                        : _allProducts[index % _allProducts.length];
                    return _HorizontalProductCard(
                      product: product,
                      onTap: () => _openProduct(context, product),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemCount: _popularProducts.isNotEmpty ? _popularProducts.length : _allProducts.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label});
  final String label;

  IconData _iconForLabel() {
    switch (label) {
      case 'Living Room':
        return CupertinoIcons.house_fill;
      case 'Dining':
        return CupertinoIcons.table;
      case 'Bedroom':
        return CupertinoIcons.bed_double_fill;
      case 'Office':
        return CupertinoIcons.briefcase_fill;
      case 'Outdoor':
        return CupertinoIcons.tree;
      case 'Kids':
        return CupertinoIcons.person_2_fill;
      default:
        return CupertinoIcons.square_grid_2x2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.all(10),
      color: _CatalogHomeState._kLight,
      borderRadius: BorderRadius.circular(16),
      onPressed: () {},
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_iconForLabel(), color: _CatalogHomeState._kBrown, size: 28),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: _CatalogHomeState._kDark,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalProductCard extends StatelessWidget {
  const _HorizontalProductCard({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: _CatalogHomeState._kSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 140,
                child: ModelViewer(
                  key: ValueKey('${product.id}_preview'),
                  backgroundColor: const Color(0xFFF9F4EF),
                  src: product.modelPath,
                  alt: 'Preview of ${product.name}',
                  ar: false,
                  autoRotate: false,
                  cameraControls: false,
                  disableZoom: true,
                  interactionPrompt: InteractionPrompt.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                product.name,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: _CatalogHomeState._kDark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '\$${product.price.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(color: _CatalogHomeState._kBrown, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
