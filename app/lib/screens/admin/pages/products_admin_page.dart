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

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
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
            onSelectionChanged: (Set<String> values) => setState(() => _segment = values.first),
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
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = filtered[index];
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
                    color: AdminPalette.clay,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (product.modelPath.isNotEmpty && product.modelPath != 'assets/chair.glb')
                      ? ModelViewer(
                          key: ValueKey('${product.id}_admin_preview'),
                          backgroundColor: AdminPalette.clay,
                          src: ModelPathHelper.normalize(product.modelPath),
                          alt: 'Preview of ${product.name}',
                          ar: false,
                          autoRotate: false,
                          cameraControls: false,
                          disableZoom: true,
                          interactionPrompt: InteractionPrompt.none,
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
                // Dynamic stock status based on inventory quantity
                final isInStock = product.inventoryQty > 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isInStock ? _tint(Colors.green, .15) : _tint(Colors.red, .15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isInStock ? 'In Stock' : 'Out of Stock',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      color: isInStock ? Colors.green.shade700 : Colors.red.shade700,
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

  // Extract unique values from existing products
  List<String> get _availableCategories {
    final categories = widget.allProducts.map((p) => p.category).where((c) => c.isNotEmpty).toSet().toList()..sort();
    // Add common categories if not present
    final commonCategories = ['Living Room', 'Dining', 'Bedroom', 'Office', 'Outdoor', 'Kids'];
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
    final commonStyles = ['Modern', 'Classic', 'Minimal', 'Industrial', 'Scandinavian', 'Traditional'];
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
    final commonMaterials = ['Wood', 'Metal', 'Fabric', 'Leather', 'Plastic', 'Glass'];
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
    _modelPath = TextEditingController(text: product?.modelPath ?? 'assets/chair.glb');
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
    _inventoryQty.dispose();
    super.dispose();
  }

  void _submit() {
    // Parse price (handles comma formatting)
    final parsedPrice = _parsePrice(_price.text);
    if (parsedPrice == null || parsedPrice <= 0) {
      Toast.warning(context, 'Enter a valid price');
      return;
    }
    
    // Validate required dropdowns
    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      Toast.warning(context, 'Please select a category');
      return;
    }
    if (_selectedStyle == null || _selectedStyle!.isEmpty) {
      Toast.warning(context, 'Please select a style');
      return;
    }
    if (_selectedMaterial == null || _selectedMaterial!.isEmpty) {
      Toast.warning(context, 'Please select a material');
      return;
    }
    if (_selectedColor == null || _selectedColor!.isEmpty) {
      Toast.warning(context, 'Please select a color');
      return;
    }
    
    final parsedInventoryQty = int.tryParse(_inventoryQty.text.trim());
    final double? widthM = double.tryParse(_realWidthM.text.trim().replaceAll(',', '.'));
    final double? heightM = double.tryParse(_realHeightM.text.trim().replaceAll(',', '.'));
    final double? depthM = double.tryParse(_realDepthM.text.trim().replaceAll(',', '.'));
    final double baseScale =
        double.tryParse(_modelBaseScale.text.trim().replaceAll(',', '.')) ?? 1.0;
    if (parsedInventoryQty == null || parsedInventoryQty < 0) {
      Toast.warning(context, 'Enter a valid inventory quantity (0 or greater)');
      return;
    }
    if (_name.text.trim().isEmpty || _modelPath.text.trim().isEmpty) {
      Toast.warning(context, 'Name and model path are required');
      return;
    }

    final data = _ProductFormData(
      name: _name.text.trim(),
      description: _description.text.trim(),
      price: parsedPrice,
      category: _selectedCategory!,
      style: _selectedStyle!,
      material: _selectedMaterial!,
      color: _selectedColor!,
      realWidthM: widthM,
      realHeightM: heightM,
      realDepthM: depthM,
      modelBaseScale: baseScale,
      modelPath: _modelPath.text.trim(),
      imageUrls: _imageUrls,
      inventoryQty: parsedInventoryQty,
      inStock: _inStock,
    );
    Navigator.of(context).pop(data);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Add product' : 'Edit product'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(_name, 'Name'),
              _buildField(_description, 'Description', maxLines: 3),
              _buildPriceField(),
              _buildDropdownField(
                label: 'Category',
                value: _selectedCategory,
                items: _availableCategories,
                onChanged: (value) => setState(() => _selectedCategory = value),
              ),
              _buildDropdownField(
                label: 'Style',
                value: _selectedStyle,
                items: _availableStyles,
                onChanged: (value) => setState(() => _selectedStyle = value),
              ),
              _buildDropdownField(
                label: 'Material',
                value: _selectedMaterial,
                items: _availableMaterials,
                onChanged: (value) => setState(() => _selectedMaterial = value),
              ),
              _buildDropdownField(
                label: 'Color',
                value: _selectedColor,
                items: _availableColors,
                onChanged: (value) => setState(() => _selectedColor = value),
              ),
          Row(
            children: [
              Expanded(child: _buildField(_realWidthM, 'Width (m)', keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _buildField(_realHeightM, 'Height (m)', keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _buildField(_realDepthM, 'Depth (m)', keyboardType: TextInputType.number)),
            ],
          ),
          _buildField(_modelBaseScale, 'Model base scale', keyboardType: TextInputType.number),
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
                  const SizedBox(height: 8),
                  // Display current model path (editable text field)
                  _buildField(_modelPath, 'Model path (.glb or .gltf file)', keyboardType: TextInputType.text),
                  const SizedBox(height: 4),
                  Text(
                    'Upload a .glb or .gltf file, or enter a path manually (e.g., assets/chair.glb or /uploads/models/...)',
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
                  if (_imageUrls.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'No images added. Click "Add Images" to upload.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else
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
              _buildField(_inventoryQty, 'Inventory Quantity', keyboardType: TextInputType.number),
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
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  Widget _buildField(TextEditingController controller, String label, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF6D4C41)),
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
    );
  }

  /// Build price field with comma formatting
  Widget _buildPriceField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _price,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Price',
          labelStyle: const TextStyle(color: Color(0xFF6D4C41)),
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
          prefixText: '₱',
        ),
      ),
    );
  }

  /// Build dropdown field for category, style, material, and color
  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF6D4C41)),
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
        items: items.map((item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Text(item),
          );
        }).toList(),
        onChanged: onChanged,
        hint: Text('Select $label', style: TextStyle(color: Colors.grey[600])),
      ),
    );
  }
}

Color _tint(Color color, double opacity) => color.withAlpha((opacity * 255).round());

