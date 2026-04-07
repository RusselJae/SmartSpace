import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../../models/product.dart';
import '../admin_theme.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';
import '../../../services/backend_storage_service.dart';
import '../../../widgets/toast.dart';
import '../../../utils/model_path_helper.dart';
import '../../../widgets/cached_model_src_loader.dart';

class ProductsAdminPage extends StatefulWidget {
  const ProductsAdminPage({super.key});

  @override
  State<ProductsAdminPage> createState() => _ProductsAdminPageState();
}

class _ProductsAdminPageState extends State<ProductsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  bool _loading = true;
  String _segment = 'all';
  String _searchQuery = '';
  String? _error;

  static const int _pageSize = 10;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _pageIndex = 0;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await _db.getAllProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load products: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<String> get _categories {
    final cats = _products.map((p) => p.category).toSet().toList()..sort();
    return cats;
  }

  List<Product> get _filteredProducts {
    var filtered = _products;
    
    // Filter by archive status - by default show only non-archived products
    if (_segment != 'archived') {
      filtered = filtered.where((p) => !p.isArchived).toList();
    } else {
      filtered = filtered.where((p) => p.isArchived).toList();
    }
    
    // Filter by category if not 'all' and not 'archived'
    if (_segment != 'all' && _segment != 'archived') {
      filtered = filtered.where((p) => p.category.toLowerCase() == _segment).toList();
    }
    
    // Apply search query filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((p) {
        return p.name.toLowerCase().contains(_searchQuery) ||
               p.category.toLowerCase().contains(_searchQuery) ||
               p.style.toLowerCase().contains(_searchQuery) ||
               p.material.toLowerCase().contains(_searchQuery);
      }).toList();
    }
    
    return filtered;
  }

  Future<void> _createProduct() async {
    if (!_db.isConnected) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('⚠️ API Not Connected'),
          content: const Text(
            'Your backend API is not connected. Products will be saved in memory only and will NOT persist to the database.\n\n'
            'To save to MySQL:\n'
            '1. Start your Node.js backend server\n'
            '2. Check API_BASE_URL in your .env file\n'
            '3. Verify the backend is accessible\n\n'
            'Continue anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    if (!mounted) return;
    final data = await showDialog<_ProductFormData>(
      context: context,
      builder: (_) => _ProductFormDialog(allProducts: _products),
    );
    if (data == null) return;
    try {
      await _db.createProduct(
        name: data.name,
        description: data.description,
        price: data.price,
        category: data.category,
        style: data.style,
        material: data.material,
        color: data.color,
        modelPath: data.modelPath,
        components: data.components,
        realWidthM: data.realWidthM,
        realHeightM: data.realHeightM,
        realDepthM: data.realDepthM,
        modelBaseScale: data.modelBaseScale,
        imageUrls: data.imageUrls,
        inventoryQty: data.inventoryQty,
        inStock: data.inStock,
      );
      if (!mounted) return;
      final message = _db.isConnected
          ? 'Product created successfully and saved to database'
          : 'Product created in memory (API not connected - not saved to database)';
      if (_db.isConnected) {
        Toast.success(context, message);
      } else {
        Toast.warning(context, message);
      }
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to create product: $e');
    }
  }

  Future<void> _editProduct(Product product) async {
    final data = await showDialog<_ProductFormData>(
      context: context,
      builder: (_) => _ProductFormDialog(product: product, allProducts: _products),
    );
    if (data == null) return;
    try {
      await _db.updateProduct(
        product.copyWith(
          name: data.name,
          description: data.description,
          price: data.price,
          category: data.category,
          style: data.style,
          material: data.material,
          color: data.color,
          modelPath: data.modelPath,
          components: data.components,
          realWidthMeters: data.realWidthM,
          realHeightMeters: data.realHeightM,
          realDepthMeters: data.realDepthM,
          modelBaseScale: data.modelBaseScale,
          imageUrls: data.imageUrls,
          inventoryQty: data.inventoryQty,
          inStock: data.inStock,
          // Preserve isArchived status when editing
          isArchived: product.isArchived,
        ),
      );
      if (!mounted) return;
      Toast.success(context, 'Product updated successfully');
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to update product: $e');
    }
  }

  /// Archive a product instead of deleting it
  /// Archived products are hidden from the main catalog but can be restored
  Future<void> _archiveProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive product'),
        content: Text('Archive "${product.name}"? Archived products will be hidden from the catalog but can be restored later.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.updateProduct(
        product.copyWith(isArchived: true),
      );
      if (!mounted) return;
      Toast.success(context, 'Product archived successfully');
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to archive product: $e');
    }
  }

  /// Unarchive a product to restore it to the catalog
  Future<void> _unarchiveProduct(Product product) async {
    try {
      await _db.updateProduct(
        product.copyWith(isArchived: false),
      );
      if (!mounted) return;
      Toast.success(context, 'Product restored successfully');
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to restore product: $e');
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete product'),
        content: Text('Permanently delete "${product.name}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.deleteProduct(product.id);
      if (!mounted) return;
      Toast.success(context, 'Product deleted successfully');
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to delete product: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

    final totalCount = filtered.length;
    final pageCount = (totalCount / _pageSize).ceil();
    final safePageIndex = pageCount <= 1 ? 0 : _pageIndex.clamp(0, pageCount - 1).toInt();
    final start = safePageIndex * _pageSize;
    final end = (start + _pageSize) > totalCount ? totalCount : (start + _pageSize);
    final pageItems = totalCount == 0 ? const <Product>[] : filtered.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Catalog',
          actions: const [],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search products by name, category, or style...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _createProduct,
                icon: const Icon(Icons.add),
                label: const Text('Add product'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8D6E63),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _loadProducts),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<String>(
            segments: [
              const ButtonSegment<String>(value: 'all', label: Text('All')),
              ..._categories.map((cat) => ButtonSegment<String>(value: cat.toLowerCase(), label: Text(cat))),
              const ButtonSegment<String>(value: 'archived', label: Text('Archived')),
            ],
            selected: {_segment},
            onSelectionChanged: (Set<String> values) => setState(() {
              _segment = values.first;
              _pageIndex = 0;
            }),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No products yet. Add new items to see them here.',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                  : Card(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        children: [
                          const _ProductsHeaderRow(),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: pageItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = pageItems[index];
                                return _ProductRow(
                                  product: product,
                                  onEdit: () => _editProduct(product),
                                  onArchive: () => _archiveProduct(product),
                                  onUnarchive: () => _unarchiveProduct(product),
                                  isArchivedView: _segment == 'archived',
                                );
                              },
                            ),
                          ),
                          if (pageCount > 1)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.chevron_left),
                                        onPressed: safePageIndex > 0
                                            ? () => setState(() => _pageIndex = safePageIndex - 1)
                                            : null,
                                        tooltip: 'Previous page',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.chevron_right),
                                        onPressed: safePageIndex < pageCount - 1
                                            ? () => setState(() => _pageIndex = safePageIndex + 1)
                                            : null,
                                        tooltip: 'Next page',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Page ${safePageIndex + 1} of $pageCount',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

class _ProductsHeaderRow extends StatelessWidget {
  const _ProductsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.grey[600],
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Product', style: style)),
          Expanded(flex: 2, child: Text('Category', style: style)),
          Expanded(flex: 2, child: Text('Price', style: style)),
          Expanded(flex: 2, child: Text('Inventory', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          const SizedBox(width: 80),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.onEdit,
    required this.onArchive,
    required this.onUnarchive,
    this.isArchivedView = false,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;
  final bool isArchivedView;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // Display 3D model preview if available, otherwise show product image or icon placeholder
                // Prioritize showing the 3D model preview for a better visual representation
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AdminPalette.clay.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: product.modelPath.isNotEmpty
                      ? CachedModelSrcLoader(
                          sourceUrl: ModelPathHelper.normalize(product.modelPath),
                          placeholder: const SizedBox.shrink(),
                          builder: (context, resolvedSrc) => ModelViewer(
                            key: ValueKey('${product.id}_admin_preview'),
                            backgroundColor: Colors.transparent,
                            src: resolvedSrc,
                            alt: 'Preview of ${product.name}',
                            ar: false,
                            environmentImage: 'neutral',
                            exposure: 1.35,
                            shadowIntensity: 0.18,
                            autoRotate: false,
                            cameraControls: false,
                            disableZoom: true,
                            interactionPrompt: InteractionPrompt.none,
                          ),
                        )
                      : product.imageUrls.isNotEmpty
                          ? Image.network(
                              product.imageUrls.first,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                // Fallback to icon if image fails to load
                                return const Icon(Icons.chair_alt_rounded, color: AdminPalette.textPrimary, size: 20);
                              },
                            )
                          : const Icon(Icons.chair_alt_rounded, color: AdminPalette.textPrimary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        product.style,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(product.category),
          ),
          Expanded(
            flex: 2,
            child: Text('₱${product.price.toStringAsFixed(2)}'),
          ),
          Expanded(
            flex: 2,
            child: Text('${product.inventoryQty}'),
          ),
          Expanded(
            flex: 2,
            child: Builder(
              builder: (context) {
                // Dynamic stock status based on inventory quantity.
                // We now expose 3 states:
                // - In Stock: inventory > lowStockThreshold
                // - Low Stock: 1..lowStockThreshold
                // - Out of Stock: 0
                const int lowStockThreshold = 3;
                final int qty = product.inventoryQty;
                final bool isOutOfStock = qty <= 0;
                final bool isLowStock = qty > 0 && qty <= lowStockThreshold;
                final bool isInStock = qty > lowStockThreshold;

                final Color tint;
                final Color textColor;
                final String label;

                if (isOutOfStock) {
                  tint = _tint(Colors.red, .15);
                  textColor = Colors.red.shade700;
                  label = 'Out of Stock';
                } else if (isLowStock) {
                  tint = _tint(Colors.orange, .15);
                  textColor = Colors.orange.shade800;
                  label = 'Low Stock';
                } else {
                  tint = _tint(Colors.green, .15);
                  textColor = Colors.green.shade700;
                  label = 'In Stock';
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                onEdit();
              } else if (value == 'archive') {
                onArchive();
              } else if (value == 'unarchive') {
                onUnarchive();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (isArchivedView)
                const PopupMenuItem(value: 'unarchive', child: Text('Restore')),
              if (!isArchivedView)
                const PopupMenuItem(value: 'archive', child: Text('Archive')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductFormData {
  _ProductFormData({
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.style,
    required this.material,
    required this.color,
    required this.realWidthM,
    required this.realHeightM,
    required this.realDepthM,
    required this.modelBaseScale,
    required this.modelPath,
    required this.components,
    required this.imageUrls,
    required this.inventoryQty,
    required this.inStock,
  });

  final String name;
  final String description;
  final double price;
  final String category;
  final String style;
  final String material;
  final String color;
  final double? realWidthM;
  final double? realHeightM;
  final double? realDepthM;
  final double modelBaseScale;
  final String modelPath;
  final List<ProductSetComponent> components;
  final List<String> imageUrls;
  final int inventoryQty;
  final bool inStock;
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({this.product, required this.allProducts});

  final Product? product;
  final List<Product> allProducts; // Pass all products to extract unique values

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _realWidthM;
  late final TextEditingController _realHeightM;
  late final TextEditingController _realDepthM;
  late final TextEditingController _modelBaseScale;
  late final TextEditingController _modelPath;
  late final List<String> _imageUrls;
  late final TextEditingController _inventoryQty;
  late final List<_SetComponentDraft> _componentDrafts;
  
  // Dropdown selected values
  String? _selectedCategory;
  String? _selectedStyle;
  String? _selectedMaterial;
  String? _selectedColor;
  
  bool _inStock = true;
  bool _uploadingImage = false;
  bool _uploadingModel = false;
  String? _uploadError;
  String? _modelUploadError;

  /// Set to true after first submit attempt; used to show per-field errors
  /// (red border + small message below) instead of toasts.
  bool _submitted = false;
  /// Per-field error messages; key is field name, value is message or null.
  final Map<String, String?> _fieldErrors = {};

  // Extract unique values from existing products
  List<String> get _availableCategories {
    final categories = widget.allProducts.map((p) => p.category).where((c) => c.isNotEmpty).toSet().toList()..sort();
    // Add common categories if not present
    // NOTE: Per requirements we now only support Living Room, Dining, Bedroom, and Office
    final commonCategories = ['Living Room', 'Dining', 'Bedroom', 'Office'];
    for (final cat in commonCategories) {
      if (!categories.contains(cat)) {
        categories.add(cat);
      }
    }
    return categories..sort();
  }

  List<String> get _availableStyles {
    final styles = widget.allProducts.map((p) => p.style).where((s) => s.isNotEmpty).toSet().toList()..sort();
    // Add common styles if not present
    // NOTE: Industrial and Scandinavian have been removed from the style taxonomy
    final commonStyles = ['Modern', 'Classic', 'Minimal', 'Traditional'];
    for (final style in commonStyles) {
      if (!styles.contains(style)) {
        styles.add(style);
      }
    }
    return styles..sort();
  }

  List<String> get _availableMaterials {
    final materials = widget.allProducts.map((p) => p.material).where((m) => m.isNotEmpty).toSet().toList()..sort();
    // Add common materials if not present
    // NOTE: Restrict materials to the four supported wood species
    final commonMaterials = ['Mahogany', 'Acacia', 'Molave', 'Yakal'];
    for (final material in commonMaterials) {
      if (!materials.contains(material)) {
        materials.add(material);
      }
    }
    return materials..sort();
  }

  List<String> get _availableColors {
    final colors = widget.allProducts.map((p) => p.color).where((c) => c.isNotEmpty).toSet().toList()..sort();
    // Add common colors if not present
    final commonColors = ['Brown', 'Black', 'White', 'Light Brown', 'Dark Brown', 'Natural', 'Gray', 'Beige'];
    for (final color in commonColors) {
      if (!colors.contains(color)) {
        colors.add(color);
      }
    }
    return colors..sort();
  }

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    // Format price with commas
    _price = TextEditingController(text: product != null ? _formatPrice(product.price) : '');
    _selectedCategory = product?.category.isNotEmpty == true ? product!.category : null;
    _selectedStyle = product?.style.isNotEmpty == true ? product!.style : null;
    _selectedMaterial = product?.material.isNotEmpty == true ? product!.material : null;
    _selectedColor = product?.color.isNotEmpty == true ? product!.color : null;
    _realWidthM = TextEditingController(text: product?.realWidthMeters?.toStringAsFixed(3) ?? '');
    _realHeightM = TextEditingController(text: product?.realHeightMeters?.toStringAsFixed(3) ?? '');
    _realDepthM = TextEditingController(text: product?.realDepthMeters?.toStringAsFixed(3) ?? '');
    _modelBaseScale = TextEditingController(text: product?.modelBaseScale.toStringAsFixed(2) ?? '1.00');
    _modelPath = TextEditingController(text: product?.modelPath ?? '');
    _componentDrafts = (product?.components ?? const <ProductSetComponent>[])
        .map(_SetComponentDraft.fromComponent)
        .toList(growable: true);
    _imageUrls = List<String>.from(product?.imageUrls ?? []);
    _inventoryQty = TextEditingController(text: product?.inventoryQty.toString() ?? '0');
    _inStock = product?.inStock ?? true;
    
    // Add listener to format price as user types
    _price.addListener(_onPriceChanged);
  }

  /// Format price with commas (e.g., 25000 -> 25,000)
  String _formatPrice(double price) {
    final parts = price.toStringAsFixed(2).split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '00';
    
    // Add commas to integer part
    final buffer = StringBuffer();
    for (int i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(integerPart[i]);
    }
    
    return '${buffer.toString()}.$decimalPart';
  }

  /// Parse price from formatted string (removes commas)
  double? _parsePrice(String value) {
    // Remove commas and parse
    final cleaned = value.replaceAll(',', '').trim();
    return double.tryParse(cleaned);
  }

  /// Handle price input changes - format with commas
  void _onPriceChanged() {
    final text = _price.text;
    final cursorPosition = _price.selection.baseOffset;
    
    // Remove all non-digit characters except decimal point
    final cleaned = text.replaceAll(RegExp(r'[^\d.]'), '');
    
    // Parse and reformat
    final parsed = double.tryParse(cleaned);
    if (parsed != null) {
      final formatted = _formatPrice(parsed);
      if (formatted != text) {
        _price.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(
            offset: formatted.length,
          ),
        );
      }
    } else if (cleaned.isEmpty) {
      // Allow empty input
      _price.value = TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
  }

  void _addComponentDraft() {
    setState(() {
      _componentDrafts.add(_SetComponentDraft.empty());
    });
  }

  void _removeComponentDraft(int index) {
    if (index < 0 || index >= _componentDrafts.length) return;
    setState(() {
      final draft = _componentDrafts.removeAt(index);
      draft.dispose();
    });
  }

  void _duplicateComponentDraft(int index) {
    if (index < 0 || index >= _componentDrafts.length) return;
    setState(() {
      final source = _componentDrafts[index];
      _componentDrafts.insert(index + 1, source.copy());
    });
  }

  Widget _buildSetComponentsEditor() {
    final hasError = (_fieldErrors['components'] ?? '').isNotEmpty;
    final totalPieces = _componentDrafts.fold<int>(0, (sum, draft) {
      final qty = int.tryParse(draft.quantity.text.trim()) ?? 0;
      return sum + (qty > 0 ? qty : 0);
    });
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Set Items (optional)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6D4C41),
                    ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _addComponentDraft,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Item'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Add one row per piece in the set (e.g., table + chairs).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 8),
          if (_componentDrafts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                'No set items added. Single-piece dimensions above will be used.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          if (_componentDrafts.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _componentDrafts.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _componentDrafts.removeAt(oldIndex);
                  _componentDrafts.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final draft = _componentDrafts[index];
                return Container(
                  key: ValueKey(draft),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.white,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_indicator, color: Colors.grey),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: draft.name,
                              decoration: const InputDecoration(
                                labelText: 'Item name',
                                filled: true,
                                fillColor: Color(0xFFF8F8F8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: draft.quantity,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Qty',
                                filled: true,
                                fillColor: Color(0xFFF8F8F8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _duplicateComponentDraft(index),
                            tooltip: 'Duplicate item',
                            icon: const Icon(Icons.copy_outlined),
                          ),
                          IconButton(
                            onPressed: () => _removeComponentDraft(index),
                            tooltip: 'Remove item',
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: draft.widthM,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Width (m)',
                                filled: true,
                                fillColor: Color(0xFFF8F8F8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: draft.heightM,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Height (m)',
                                filled: true,
                                fillColor: Color(0xFFF8F8F8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: draft.depthM,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Depth (m)',
                                filled: true,
                                fillColor: Color(0xFFF8F8F8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          if (_componentDrafts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Total pieces: $totalPieces',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6D4C41),
                      ),
                ),
              ),
            ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _fieldErrors['components']!,
                style: const TextStyle(
                  color: CupertinoColors.systemRed,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Uploads product images to the backend server
  Future<void> _pickAndUploadImages() async {
    if (_imageUrls.length >= 10) {
      Toast.warning(context, 'Maximum 10 images allowed');
      return;
    }

    setState(() {
      _uploadError = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final remainingSlots = 10 - _imageUrls.length;
    final filesToUpload = result.files.take(remainingSlots).toList();

    setState(() {
      _uploadingImage = true;
    });

    try {
      final handle = _deriveProductHandle();
      final uploadedUrls = <String>[];

      for (final file in filesToUpload) {
        if (file.bytes == null) continue;

        final uploadResult = await BackendStorageService.instance.uploadImage(
          productHandle: handle,
          fileName: file.name,
          bytes: file.bytes!,
        );
        uploadedUrls.add(uploadResult.downloadUrl);
      }

      setState(() {
        _imageUrls.addAll(uploadedUrls);
      });

      if (!mounted) return;
      Toast.success(context, '${uploadedUrls.length} image(s) uploaded successfully');
    } catch (error) {
      setState(() {
        _uploadError = 'Upload failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploadingImage = false;
        });
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageUrls.removeAt(index);
    });
  }

  /// If [modelPath] points to a backend-managed upload (i.e. `/uploads/models/...`),
  /// return the relative `product-handle/filename.glb` path expected by
  /// `DELETE /api/models/:filePath`.
  String? _extractManagedModelFilePath(String modelPath) {
    final raw = modelPath.trim().replaceAll('\\', '/');
    if (raw.isEmpty) return null;

    const prefixA = '/uploads/models/';
    const prefixB = 'uploads/models/';

    if (raw.startsWith(prefixA)) {
      return raw.substring(prefixA.length);
    }
    if (raw.startsWith(prefixB)) {
      return raw.substring(prefixB.length);
    }
    return null;
  }

  /// Removes the currently configured backend-managed model file (if any),
  /// then resets the model path to the default asset.
  Future<void> _removeCurrentModel() async {
    final managedFilePath = _extractManagedModelFilePath(_modelPath.text);
    if (managedFilePath == null || managedFilePath.isEmpty) {
      // Reset to empty so previews fall back to images/icons.
      setState(() => _modelPath.text = '');
      return;
    }

    setState(() => _modelUploadError = null);

    try {
      await BackendStorageService.instance.deleteModel(managedFilePath);
      if (!mounted) return;
      Toast.success(context, 'Model removed');
      setState(() => _modelPath.text = '');
    } catch (error) {
      setState(() => _modelUploadError = 'Failed to remove model: $error');
      if (!mounted) return;
      Toast.error(context, 'Failed to remove model: $error');
    }
  }

  /// Uploads a 3D model file (.glb or .gltf) to the backend server
  /// Automatically updates the model path field with the uploaded file path
  Future<void> _pickAndUploadModel() async {
    setState(() {
      _modelUploadError = null;
    });

    // Pick a single 3D model file (.glb or .gltf)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['glb', 'gltf'],
      withData: true,
    );

    if (result == null || result.files.isEmpty || result.files.first.bytes == null) {
      return;
    }

    final file = result.files.first;

    setState(() {
      _uploadingModel = true;
    });

    // Capture current managed model (if any). We delete it AFTER the upload succeeds
    // to avoid leaving the product without a model on upload failure.
    final oldManagedFilePath = _extractManagedModelFilePath(_modelPath.text);

    try {
      // Derive product handle for folder organization
      final handle = _deriveProductHandle();

      // Upload the model file to backend storage
      final uploadResult = await BackendStorageService.instance.uploadModel(
        productHandle: handle,
        fileName: file.name,
        bytes: file.bytes!,
      );

      // Update the model path field with the relative path format
      // The backend returns filePath as 'product-handle/file.glb' (relative to modelsDir)
      // We prepend '/uploads/models/' so ModelPathHelper can normalize it to a full URL
      // ModelPathHelper expects paths starting with '/uploads' or 'uploads/'
      setState(() {
        _modelPath.text = '/uploads/models/${uploadResult.filePath}';
      });

      if (!mounted) return;
      Toast.success(context, '3D model uploaded successfully');

      // Auto-delete previous model file (if it was backend-managed) after success.
      if (oldManagedFilePath != null &&
          oldManagedFilePath.isNotEmpty &&
          oldManagedFilePath != uploadResult.filePath) {
        try {
          await BackendStorageService.instance.deleteModel(oldManagedFilePath);
        } catch (_) {
          // Non-fatal: model upload already succeeded; deletion failure should not block.
        }
      }
    } catch (error) {
      setState(() {
        _modelUploadError = 'Model upload failed: $error';
      });
      if (!mounted) return;
      Toast.error(context, 'Failed to upload 3D model: $error');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingModel = false;
        });
      }
    }
  }

  /// Builds a stable folder handle per product. Existing products reuse their id,
  /// while brand new drafts fall back to their current name or a timestamp slug.
  String _deriveProductHandle() {
    if (widget.product?.id != null && widget.product!.id.isNotEmpty) {
      return widget.product!.id;
    }
    final candidate = _name.text.trim();
    if (candidate.isNotEmpty) {
      return candidate;
    }
    return 'draft-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.removeListener(_onPriceChanged);
    _price.dispose();
    _realWidthM.dispose();
    _realHeightM.dispose();
    _realDepthM.dispose();
    _modelBaseScale.dispose();
    _modelPath.dispose();
    for (final draft in _componentDrafts) {
      draft.dispose();
    }
    _inventoryQty.dispose();
    super.dispose();
  }

  void _submit() {
    _submitted = true;
    _fieldErrors.clear();

    final parsedPrice = _parsePrice(_price.text);
    final parsedInventoryQty = int.tryParse(_inventoryQty.text.trim());
    final double? widthM = double.tryParse(_realWidthM.text.trim().replaceAll(',', '.'));
    final double? heightM = double.tryParse(_realHeightM.text.trim().replaceAll(',', '.'));
    final double? depthM = double.tryParse(_realDepthM.text.trim().replaceAll(',', '.'));
    final double baseScale =
        double.tryParse(_modelBaseScale.text.trim().replaceAll(',', '.')) ?? 1.0;
    final parsedComponents = <ProductSetComponent>[];

    if (_name.text.trim().isEmpty) _fieldErrors['name'] = 'Fill this field';
    if (_description.text.trim().isEmpty) _fieldErrors['description'] = 'Fill this field';
    if (parsedPrice == null || parsedPrice <= 0) _fieldErrors['price'] = 'Enter a valid price';
    if (_selectedCategory == null || _selectedCategory!.isEmpty) _fieldErrors['category'] = 'Choose a category';
    if (_selectedStyle == null || _selectedStyle!.isEmpty) _fieldErrors['style'] = 'Choose a style';
    if (_selectedMaterial == null || _selectedMaterial!.isEmpty) _fieldErrors['material'] = 'Choose a material';
    if (_selectedColor == null || _selectedColor!.isEmpty) _fieldErrors['color'] = 'Choose a color';
    if (widthM == null || widthM <= 0) _fieldErrors['width'] = 'Must be greater than 0';
    if (heightM == null || heightM <= 0) _fieldErrors['height'] = 'Must be greater than 0';
    if (depthM == null || depthM <= 0) _fieldErrors['depth'] = 'Must be greater than 0';
    if (baseScale <= 0) _fieldErrors['modelBaseScale'] = 'Must be greater than 0';
    if (_modelPath.text.trim().isEmpty) _fieldErrors['modelPath'] = 'Add a model path';
    for (final draft in _componentDrafts) {
      final name = draft.name.text.trim();
      final quantityText = draft.quantity.text.trim();
      final widthText = draft.widthM.text.trim();
      final heightText = draft.heightM.text.trim();
      final depthText = draft.depthM.text.trim();

      final isRowCompletelyEmpty = name.isEmpty &&
          quantityText.isEmpty &&
          widthText.isEmpty &&
          heightText.isEmpty &&
          depthText.isEmpty;
      if (isRowCompletelyEmpty) continue;

      final quantity = int.tryParse(quantityText);
      final width = double.tryParse(widthText.replaceAll(',', '.'));
      final height = double.tryParse(heightText.replaceAll(',', '.'));
      final depth = double.tryParse(depthText.replaceAll(',', '.'));
      if (name.isEmpty ||
          quantity == null ||
          quantity <= 0 ||
          width == null ||
          width <= 0 ||
          height == null ||
          height <= 0 ||
          depth == null ||
          depth <= 0) {
        _fieldErrors['components'] =
            'Each set item row needs name, quantity, width, height, and depth';
        break;
      }
      parsedComponents.add(
        ProductSetComponent(
          name: name,
          quantity: quantity,
          widthMeters: width,
          heightMeters: height,
          depthMeters: depth,
        ),
      );
    }
    if (parsedInventoryQty == null || parsedInventoryQty < 0) _fieldErrors['inventory'] = 'Use 0 or greater';
    if (_imageUrls.isEmpty) _fieldErrors['images'] = 'Add at least one image';

    if (_fieldErrors.isNotEmpty) {
      setState(() {});
      return;
    }

    // At this point validation passed, so parsedPrice and parsedInventoryQty are non-null.
    final data = _ProductFormData(
      name: _name.text.trim(),
      description: _description.text.trim(),
      price: parsedPrice!,
      category: _selectedCategory!,
      style: _selectedStyle!,
      material: _selectedMaterial!,
      color: _selectedColor!,
      realWidthM: widthM,
      realHeightM: heightM,
      realDepthM: depthM,
      modelBaseScale: baseScale,
      modelPath: _modelPath.text.trim(),
      components: parsedComponents,
      imageUrls: _imageUrls,
      inventoryQty: parsedInventoryQty!,
      inStock: _inStock,
    );
    Navigator.of(context).pop(data);
  }

  @override
  Widget build(BuildContext context) {
    // Constrained modal matching admin container size—not full screen.
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 700),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with back/close
              Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                    Expanded(
                      child: Text(
                        widget.product == null ? 'Add product' : 'Edit product',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable form body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      _buildField(_name, 'Name', errorText: _fieldErrors['name']),
                      _buildField(_description, 'Description', maxLines: 3, errorText: _fieldErrors['description']),
                      _buildPriceField(errorText: _fieldErrors['price']),
                      _buildDropdownField(
                        label: 'Category',
                        value: _selectedCategory,
                        items: _availableCategories,
                        onChanged: (value) => setState(() => _selectedCategory = value),
                        errorText: _fieldErrors['category'],
                      ),
                      _buildDropdownField(
                        label: 'Style',
                        value: _selectedStyle,
                        items: _availableStyles,
                        onChanged: (value) => setState(() => _selectedStyle = value),
                        errorText: _fieldErrors['style'],
                      ),
                      _buildDropdownField(
                        label: 'Material',
                        value: _selectedMaterial,
                        items: _availableMaterials,
                        onChanged: (value) => setState(() => _selectedMaterial = value),
                        errorText: _fieldErrors['material'],
                      ),
                      _buildDropdownField(
                        label: 'Color',
                        value: _selectedColor,
                        items: _availableColors,
                        onChanged: (value) => setState(() => _selectedColor = value),
                        errorText: _fieldErrors['color'],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildField(
                              _realWidthM,
                              'Width (m)',
                              keyboardType: TextInputType.number,
                              errorText: _fieldErrors['width'],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildField(
                              _realHeightM,
                              'Height (m)',
                              keyboardType: TextInputType.number,
                              errorText: _fieldErrors['height'],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildField(
                              _realDepthM,
                              'Depth (m)',
                              keyboardType: TextInputType.number,
                              errorText: _fieldErrors['depth'],
                            ),
                          ),
                        ],
                      ),
                      _buildField(
                        _modelBaseScale,
                        'Model base scale',
                        keyboardType: TextInputType.number,
                        errorText: _fieldErrors['modelBaseScale'],
                      ),
                      _buildSetComponentsEditor(),
                      const SizedBox(height: 8),
              // 3D Model Upload Section
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '3D Model',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          if (_extractManagedModelFilePath(_modelPath.text) != null)
                            OutlinedButton.icon(
                              onPressed: _uploadingModel ? null : _removeCurrentModel,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Remove'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                          if (_extractManagedModelFilePath(_modelPath.text) != null)
                            const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _uploadingModel ? null : _pickAndUploadModel,
                            icon: _uploadingModel
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.upload_file, size: 18),
                            label: const Text('Upload Model'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Display current model path (editable text field)
                  _buildField(
                    _modelPath,
                    'Model path (.glb or .gltf file)',
                    keyboardType: TextInputType.text,
                    errorText: _fieldErrors['modelPath'],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upload a .glb or .gltf file, or enter a path manually (e.g., assets/your_model.glb or /uploads/models/...)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (_modelUploadError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _modelUploadError!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Product Images Section
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Product Images (${_imageUrls.length}/10)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_imageUrls.length < 10)
                        FilledButton.icon(
                          onPressed: _uploadingImage ? null : _pickAndUploadImages,
                          icon: _uploadingImage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add_photo_alternate, size: 18),
                          label: const Text('Add Images'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_imageUrls.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _fieldErrors['images'] != null
                              ? CupertinoColors.systemRed
                              : Colors.grey.shade300,
                          width: _fieldErrors['images'] != null ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'No images added. Click "Add Images" to upload.',
                          style: TextStyle(
                            color: _fieldErrors['images'] != null
                                ? CupertinoColors.systemRed
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    if (_fieldErrors['images'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _fieldErrors['images']!,
                          style: const TextStyle(
                            color: CupertinoColors.systemRed,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ] else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(_imageUrls.length, (index) {
                        return Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: Image.network(
                                _imageUrls[index],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image),
                                  );
                                },
                              ),
                            ),
                            Positioned(
                              top: -4,
                              right: -4,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                iconSize: 20,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _removeImage(index),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  if (_uploadError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _uploadError!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              _buildField(
                _inventoryQty,
                'Inventory Quantity',
                keyboardType: TextInputType.number,
                errorText: _fieldErrors['inventory'],
              ),
              SwitchListTile(
                value: _inStock,
                title: const Text('In stock'),
                onChanged: (value) => setState(() => _inStock = value),
              ),
              // Note: Popular and New Arrival are now automatic
              // - New Arrival: Products created within the last week
              // - Popular: Based on number of orders for the product
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Note: Popular and New Arrival status are automatically calculated based on order history and creation date.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                ),
              ),
                    ],
                  ),
                ),
              ),
            ),
              // Footer with Cancel/Save
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _submit,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Label for a required field: shows "Label " plus a red asterisk.
  static Widget _requiredLabel(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: const TextStyle(color: Color(0xFF6D4C41), fontSize: 16),
        ),
        const Text(
          '*',
          style: TextStyle(color: CupertinoColors.systemRed, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? errorText,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;
    final borderColor = hasError ? CupertinoColors.systemRed : CupertinoColors.separator.withValues(alpha: 0.1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _requiredLabel(label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              errorText: errorText,
              errorStyle: const TextStyle(color: CupertinoColors.systemRed, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor, width: hasError ? 1.5 : 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: hasError ? CupertinoColors.systemRed : const Color(0xFF8D6E63),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build price field with comma formatting and optional inline error.
  Widget _buildPriceField({String? errorText}) {
    final hasError = errorText != null && errorText.isNotEmpty;
    final borderColor = hasError ? CupertinoColors.systemRed : CupertinoColors.separator.withValues(alpha: 0.1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _requiredLabel('Price'),
          const SizedBox(height: 6),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              errorText: errorText,
              errorStyle: const TextStyle(color: CupertinoColors.systemRed, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor, width: hasError ? 1.5 : 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: hasError ? CupertinoColors.systemRed : const Color(0xFF8D6E63),
                  width: 2,
                ),
              ),
              prefixText: '₱',
            ),
          ),
        ],
      ),
    );
  }

  /// Build dropdown field for category, style, material, and color.
  /// Shows required label with red * and inline error (red border + message below).
  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? errorText,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;
    final borderColor = hasError ? CupertinoColors.systemRed : CupertinoColors.separator.withValues(alpha: 0.1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _requiredLabel(label),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: value,
            decoration: InputDecoration(
              errorText: errorText,
              errorStyle: const TextStyle(color: CupertinoColors.systemRed, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor, width: hasError ? 1.5 : 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: hasError ? CupertinoColors.systemRed : const Color(0xFF8D6E63),
                  width: 2,
                ),
              ),
            ),
            items: items.map((item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: onChanged,
            hint: Text('Select $label', style: TextStyle(color: Colors.grey[600])),
          ),
        ],
      ),
    );
  }
}

class _SetComponentDraft {
  _SetComponentDraft({
    required this.name,
    required this.quantity,
    required this.widthM,
    required this.heightM,
    required this.depthM,
  });

  factory _SetComponentDraft.empty() {
    return _SetComponentDraft(
      name: TextEditingController(),
      quantity: TextEditingController(text: '1'),
      widthM: TextEditingController(),
      heightM: TextEditingController(),
      depthM: TextEditingController(),
    );
  }

  factory _SetComponentDraft.fromComponent(ProductSetComponent component) {
    return _SetComponentDraft(
      name: TextEditingController(text: component.name),
      quantity: TextEditingController(text: component.quantity.toString()),
      widthM: TextEditingController(text: component.widthMeters.toStringAsFixed(3)),
      heightM: TextEditingController(text: component.heightMeters.toStringAsFixed(3)),
      depthM: TextEditingController(text: component.depthMeters.toStringAsFixed(3)),
    );
  }

  _SetComponentDraft copy() {
    return _SetComponentDraft(
      name: TextEditingController(text: name.text),
      quantity: TextEditingController(text: quantity.text),
      widthM: TextEditingController(text: widthM.text),
      heightM: TextEditingController(text: heightM.text),
      depthM: TextEditingController(text: depthM.text),
    );
  }

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController widthM;
  final TextEditingController heightM;
  final TextEditingController depthM;

  void dispose() {
    name.dispose();
    quantity.dispose();
    widthM.dispose();
    heightM.dispose();
    depthM.dispose();
  }
}

Color _tint(Color color, double opacity) => color.withAlpha((opacity * 255).round());

