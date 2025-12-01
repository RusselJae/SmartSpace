import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/product.dart';
import '../admin_theme.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';
import '../../../services/google_drive_service.dart';

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
    if (_segment != 'all') {
      filtered = filtered.where((p) => p.category.toLowerCase() == _segment).toList();
    }
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
      builder: (_) => _ProductFormDialog(),
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
        size: data.size,
        modelPath: data.modelPath,
        imageUrls: data.imageUrls,
        inventoryQty: data.inventoryQty,
        isPopular: data.isPopular,
        isNewArrival: data.isNewArrival,
        inStock: data.inStock,
      );
      if (!mounted) return;
      final message = _db.isConnected
          ? 'Product created successfully and saved to database'
          : 'Product created in memory (API not connected - not saved to database)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _db.isConnected ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create product: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editProduct(Product product) async {
    final data = await showDialog<_ProductFormData>(
      context: context,
      builder: (_) => _ProductFormDialog(product: product),
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
          size: data.size,
          modelPath: data.modelPath,
          imageUrls: data.imageUrls,
          inventoryQty: data.inventoryQty,
          isPopular: data.isPopular,
          isNewArrival: data.isNewArrival,
          inStock: data.inStock,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product updated successfully'), backgroundColor: Colors.green),
      );
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update product: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete product'),
        content: Text('Delete "${product.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.deleteProduct(product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product deleted successfully'), backgroundColor: Colors.green),
      );
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete product: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<String>(
            segments: [
              const ButtonSegment<String>(value: 'all', label: Text('All')),
              ..._categories.map((cat) => ButtonSegment<String>(value: cat.toLowerCase(), label: Text(cat))),
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
                                  onDelete: () => _deleteProduct(product),
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
    required this.onDelete,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: AdminPalette.clay,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chair_alt_rounded, color: AdminPalette.textPrimary, size: 20),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: product.inStock ? _tint(Colors.green, .15) : _tint(Colors.red, .15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                product.inStock ? 'In stock' : 'Out of stock',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                onEdit();
              } else if (value == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
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
    required this.size,
    required this.modelPath,
    required this.imageUrls,
    required this.inventoryQty,
    required this.isPopular,
    required this.isNewArrival,
    required this.inStock,
  });

  final String name;
  final String description;
  final double price;
  final String category;
  final String style;
  final String material;
  final String color;
  final String size;
  final String modelPath;
  final List<String> imageUrls;
  final int inventoryQty;
  final bool isPopular;
  final bool isNewArrival;
  final bool inStock;
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({this.product});

  final Product? product;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _category;
  late final TextEditingController _style;
  late final TextEditingController _material;
  late final TextEditingController _color;
  late final TextEditingController _size;
  late final TextEditingController _modelPath;
  late final TextEditingController _images;
  late final TextEditingController _inventoryQty;
  bool _isPopular = false;
  bool _isNewArrival = false;
  bool _inStock = true;
  bool _uploadingModel = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    _price = TextEditingController(text: product?.price.toString() ?? '');
    _category = TextEditingController(text: product?.category ?? '');
    _style = TextEditingController(text: product?.style ?? '');
    _material = TextEditingController(text: product?.material ?? '');
    _color = TextEditingController(text: product?.color ?? '');
    _size = TextEditingController(text: product?.size ?? '');
    _modelPath = TextEditingController(text: product?.modelPath ?? 'assets/chair.glb');
    _images = TextEditingController(text: product?.imageUrls.join(', ') ?? '');
    _inventoryQty = TextEditingController(text: product?.inventoryQty.toString() ?? '0');
    _isPopular = product?.isPopular ?? false;
    _isNewArrival = product?.isNewArrival ?? false;
    _inStock = product?.inStock ?? true;
  }

  /// Uploads a GLB/GTLF file straight into the shared Drive folder and stores
  /// the public download URL back into the model path text field.
  Future<void> _pickAndUploadModel() async {
    setState(() {
      _uploadError = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['glb', 'gltf'],
      withData: true,
    );

    if (result == null) {
      return;
    }

    final picked = result.files.single;
    final bytes = picked.bytes;

    if (bytes == null) {
      setState(() {
        _uploadError = 'Unable to read the file bytes. Please retry on a platform that supports in-memory reads.';
      });
      return;
    }

    setState(() {
      _uploadingModel = true;
    });

    try {
      final handle = _deriveProductHandle();
      final uploadResult = await GoogleDriveService.instance.uploadModel(
        productHandle: handle,
        fileName: picked.name,
        bytes: bytes,
      );

      setState(() {
        _modelPath.text = uploadResult.downloadUrl;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model uploaded to Drive as ${uploadResult.fileName}')),
      );
    } catch (error) {
      setState(() {
        _uploadError = 'Drive upload failed: $error';
      });
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
    _price.dispose();
    _category.dispose();
    _style.dispose();
    _material.dispose();
    _color.dispose();
    _size.dispose();
    _modelPath.dispose();
    _images.dispose();
    _inventoryQty.dispose();
    super.dispose();
  }

  void _submit() {
    final parsedPrice = double.tryParse(_price.text.trim());
    if (parsedPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price')));
      return;
    }
    final parsedInventoryQty = int.tryParse(_inventoryQty.text.trim());
    if (parsedInventoryQty == null || parsedInventoryQty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid inventory quantity (0 or greater)')));
      return;
    }
    if (_name.text.trim().isEmpty || _modelPath.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and model path are required')));
      return;
    }

    final data = _ProductFormData(
      name: _name.text.trim(),
      description: _description.text.trim(),
      price: parsedPrice,
      category: _category.text.trim().isEmpty ? 'General' : _category.text.trim(),
      style: _style.text.trim().isEmpty ? 'Modern' : _style.text.trim(),
      material: _material.text.trim().isEmpty ? 'Wood' : _material.text.trim(),
      color: _color.text.trim().isEmpty ? 'Brown' : _color.text.trim(),
      size: _size.text.trim().isEmpty ? 'M' : _size.text.trim(),
      modelPath: _modelPath.text.trim(),
      imageUrls: _images.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      inventoryQty: parsedInventoryQty,
      isPopular: _isPopular,
      isNewArrival: _isNewArrival,
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
              _buildField(_price, 'Price', keyboardType: TextInputType.number),
              _buildField(_category, 'Category'),
              _buildField(_style, 'Style'),
              _buildField(_material, 'Material'),
              _buildField(_color, 'Color'),
              _buildField(_size, 'Size'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildField(_modelPath, '3D Model path or URL'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _uploadingModel ? null : _pickAndUploadModel,
                        icon: _uploadingModel
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload_rounded),
                        label: Text(_uploadingModel ? 'Uploading...' : 'Upload to Drive'),
                      ),
                      Flexible(
                        child: Text(
                          'Uploads are stored per-product inside the shared Google Drive catalog so AR previews always fetch from the cloud.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  if (_uploadError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _uploadError!,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                ],
              ),
              _buildField(_images, 'Image URLs (comma separated)'),
              _buildField(_inventoryQty, 'Inventory Quantity', keyboardType: TextInputType.number),
              SwitchListTile(
                value: _isPopular,
                title: const Text('Mark as popular'),
                onChanged: (value) => setState(() => _isPopular = value),
              ),
              SwitchListTile(
                value: _isNewArrival,
                title: const Text('Mark as new arrival'),
                onChanged: (value) => setState(() => _isNewArrival = value),
              ),
              SwitchListTile(
                value: _inStock,
                title: const Text('In stock'),
                onChanged: (value) => setState(() => _inStock = value),
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
}

Color _tint(Color color, double opacity) => color.withAlpha((opacity * 255).round());

