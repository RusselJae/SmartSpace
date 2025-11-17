import 'package:flutter/material.dart';

import '../../../models/product.dart';
import '../admin_theme.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';

class ProductsAdminPage extends StatefulWidget {
  const ProductsAdminPage({super.key});

  @override
  State<ProductsAdminPage> createState() => _ProductsAdminPageState();
}

class _ProductsAdminPageState extends State<ProductsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  List<Product> _products = [];
  bool _loading = true;
  String _segment = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
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
    if (_segment == 'all') return _products;
    return _products.where((p) => p.category.toLowerCase() == _segment).toList();
  }

  Future<void> _createProduct() async {
    final data = await showDialog<_ProductFormData>(
      context: context,
      builder: (_) => _ProductFormDialog(),
    );
    if (data == null) return;
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
      isPopular: data.isPopular,
      isNewArrival: data.isNewArrival,
      inStock: data.inStock,
    );
    await _loadProducts();
  }

  Future<void> _editProduct(Product product) async {
    final data = await showDialog<_ProductFormData>(
      context: context,
      builder: (_) => _ProductFormDialog(product: product),
    );
    if (data == null) return;
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
        isPopular: data.isPopular,
        isNewArrival: data.isNewArrival,
        inStock: data.inStock,
      ),
    );
    await _loadProducts();
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
    await _db.deleteProduct(product.id);
    await _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Catalog',
          actions: [
            AdminToolbarAction(label: 'Add product', icon: Icons.add, primary: true, onPressed: _createProduct),
          ],
          trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _loadProducts),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
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
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const Center(child: Text('No products yet. Add new items to see them here.'))
                  : LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        final int columns = constraints.maxWidth > 900 ? 3 : constraints.maxWidth > 600 ? 2 : 1;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 1.2,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (BuildContext context, int index) {
                            final product = filtered[index];
                            return _ProductCard(
                              product: product,
                              onEdit: () => _editProduct(product),
                              onDelete: () => _deleteProduct(product),
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onEdit, required this.onDelete});

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  height: 54,
                  width: 54,
                  decoration: BoxDecoration(
                    color: AdminPalette.clay,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.chair_alt_rounded, color: AdminPalette.dark),
                ),
                const Spacer(),
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
            const SizedBox(height: 12),
            Text(product.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(product.category, style: theme.textTheme.bodySmall),
            const Spacer(),
            Row(
              children: [
                Text('\$${product.price.toStringAsFixed(2)}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Chip(
                  label: Text(product.inStock ? 'In stock' : 'Out of stock'),
                  backgroundColor: product.inStock ? _tint(Colors.green, .15) : _tint(Colors.red, .15),
                  labelStyle: TextStyle(color: product.inStock ? Colors.green[700] : Colors.red[700]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onEdit, child: const Text('Edit')),
          ],
        ),
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
  bool _isPopular = false;
  bool _isNewArrival = false;
  bool _inStock = true;

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
    _isPopular = product?.isPopular ?? false;
    _isNewArrival = product?.isNewArrival ?? false;
    _inStock = product?.inStock ?? true;
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
    super.dispose();
  }

  void _submit() {
    final parsedPrice = double.tryParse(_price.text.trim());
    if (parsedPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price')));
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
              _buildField(_modelPath, '3D Model path or URL'),
              _buildField(_images, 'Image URLs (comma separated)'),
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
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

Color _tint(Color color, double opacity) => color.withAlpha((opacity * 255).round());

