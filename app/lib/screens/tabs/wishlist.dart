import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../config/api_config.dart';
import '../../services/wishlist_service.dart';
import '../../models/product.dart';
import '../../widgets/toast.dart';
import '../../widgets/underline_filter_bar.dart';
import '../views/product_detail.dart';

/// Brand walnut (aligned with Orders tab + shell).
const Color _kWalnut = Color(0xFF5C4033);
const Color _kWalnutWash = Color(0xFFF5EFEA);

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
  final TextEditingController _search = TextEditingController();

  String _query = '';
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _wishlist.addListener(_onChanged);
    _search.addListener(() {
      final next = _search.text.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _wishlist.removeListener(_onChanged);
    _search.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _open(Product product) {
    // Use rootNavigator to hide tab bar when navigating to product detail
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  List<String> _categoriesFor(List<Product> items) {
    final cats = items.map((p) => p.category.trim()).where((c) => c.isNotEmpty).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...cats];
  }

  List<Product> _filtered(List<Product> items) {
    final q = _query.trim().toLowerCase();
    final cat = _selectedCategory;

    return items.where((p) {
      if (cat != 'All' && p.category != cat) return false;
      if (q.isEmpty) return true;
      final hay = '${p.name} ${p.category} ${p.style} ${p.material}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _wishlist.items;
    final categories = _categoriesFor(items);
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }
    final filtered = _filtered(items);

    final filterEntries = categories
        .map((c) => UnderlineFilterEntry(key: c, label: c))
        .toList();

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: _kWalnutWash,
        border: Border(
          bottom: BorderSide(
            color: _kWalnut.withValues(alpha: 0.18),
            width: 0.5,
          ),
        ),
        middle: Text(
          'Likes',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: _kWalnut,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoTextField(
                controller: _search,
                placeholder: 'Search likes',
                placeholderStyle: GoogleFonts.poppins(
                  fontSize: 14,
                  color: _kWalnut.withValues(alpha: 0.45),
                  decoration: TextDecoration.none,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _kWalnut.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    CupertinoIcons.search,
                    color: _kWalnut.withValues(alpha: 0.75),
                    size: 18,
                  ),
                ),
                suffix: _query.isNotEmpty
                    ? CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(24, 24),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        child: Icon(
                          CupertinoIcons.clear_circled_solid,
                          size: 18,
                          color: _kWalnut.withValues(alpha: 0.75),
                        ),
                      )
                    : null,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF5F5B56),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Category filters: same underline treatment as Orders — always visible.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: UnderlineFilterBar(
                entries: filterEntries,
                selectedKey: _selectedCategory,
                onSelect: (key) => setState(() => _selectedCategory = key),
                walnut: _kWalnut,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'Tap the heart on a product. Your likes show up here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF5F5B56),
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No matches.',
                            style: GoogleFonts.poppins(
                              color: Colors.black54,
                              fontSize: 15,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final crossAxisCount = width >= 1100
                                ? 4
                                : width >= 800
                                    ? 3
                                    : 2;

                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                // A touch taller than before to avoid bottom overflow
                                // while we also dedicate more space to text details.
                                childAspectRatio: 0.78,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final product = filtered[index];
                                return _LikeGridTile(
                                  product: product,
                                  onOpen: () => _open(product),
                                  onRemove: () {
                                    _wishlist.remove(product.id);
                                    Toast.info(context, '${product.name} removed from likes');
                                  },
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikeGridTile extends StatelessWidget {
  const _LikeGridTile({required this.product, required this.onOpen, required this.onRemove});
  final Product product;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  bool get _hasModel {
    final src = product.modelPath.trim();
    if (src.isEmpty) return false;
    return src.toLowerCase().endsWith('.glb') || src.toLowerCase().endsWith('.gltf');
  }

  String? get _resolvedModelSrc {
    final raw = product.modelPath.trim();
    if (raw.isEmpty) return null;

    // If the backend stored a full URL already, use it directly.
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    // If the backend stored an uploads path (common from /api/models/upload),
    // it will look like:
    // - /uploads/models/...
    // - uploads/models/...
    // - backend/uploads/models/... (local-ish)
    //
    // For Flutter Web, we MUST turn this into an absolute URL that points to
    // the backend origin, otherwise the browser will try to fetch it from the
    // Flutter dev-server origin and the model will fail to load (blank tile).
    final apiUri = Uri.parse(ApiConfig.baseUrl);
    final origin = apiUri.origin; // e.g. http://localhost:4000

    if (raw.startsWith('/uploads/')) {
      return '$origin$raw';
    }
    if (raw.startsWith('uploads/')) {
      return '$origin/$raw';
    }
    if (raw.contains('backend/uploads/')) {
      final idx = raw.indexOf('backend/uploads/');
      final tail = raw.substring(idx + 'backend/'.length); // uploads/...
      return '$origin/$tail';
    }

    // Otherwise treat it as a Flutter asset path (e.g. assets/chair.glb).
    return raw;
  }

  bool get _hasNetworkImage {
    if (product.imageUrls.isEmpty) return false;
    final first = product.imageUrls.first.trim();
    return first.startsWith('http://') || first.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _kWalnut.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Shorter preview area, more space for text/details below.
            AspectRatio(
              aspectRatio: 1.7,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: const Color(0xFFF2F2F7),
                    child: _hasModel
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              const Center(
                                child: Icon(
                                  CupertinoIcons.cube_box,
                                  color: Colors.black26,
                                  size: 26,
                                ),
                              ),
                              IgnorePointer(
                                ignoring: true,
                                child: ModelViewer(
                                  // Keep transparent so our fallback icon stays visible
                                  // if the model fails to load (instead of a blank tile).
                                  backgroundColor: Colors.transparent,
                                  src: _resolvedModelSrc ?? product.modelPath,
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
                          )
                        : _hasNetworkImage
                            ? Image.network(
                                product.imageUrls.first,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(
                                    CupertinoIcons.photo,
                                    color: Colors.black26,
                                    size: 26,
                                  ),
                                ),
                              )
                            : const Center(
                                child: Icon(
                                  CupertinoIcons.cube_box,
                                  color: Colors.black26,
                                  size: 26,
                                ),
                              ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: CupertinoButton(
                      padding: const EdgeInsets.all(6),
                      minSize: 0,
                      onPressed: onRemove,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Icon(
                          CupertinoIcons.heart_slash,
                          size: 16,
                          color: CupertinoColors.systemRed,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.black87,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.black54,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        height: 1.25,
                        color: Colors.black54,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '₱${product.price.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                        color: _kWalnut,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


