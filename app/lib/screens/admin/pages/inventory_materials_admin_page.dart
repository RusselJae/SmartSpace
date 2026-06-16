import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/inventory_material.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';
import '../../../widgets/toast.dart';

/// Shared field decoration for material modals — white surface, admin palette.
InputDecoration _materialFieldDecoration({
  required String label,
  String? helperText,
}) {
  return InputDecoration(
    labelText: label,
    helperText: helperText,
    filled: true,
    fillColor: const Color(0xFFF8F8F8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
    ),
  );
}

/// Materials stock panel — plywood, hardware, finishes, etc. (not catalog product stock).
class InventoryMaterialsAdminPage extends StatefulWidget {
  const InventoryMaterialsAdminPage({super.key});

  @override
  State<InventoryMaterialsAdminPage> createState() => _InventoryMaterialsAdminPageState();
}

class _InventoryMaterialsAdminPageState extends State<InventoryMaterialsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AdminAuthService _adminAuth = AdminAuthService();
  final TextEditingController _searchController = TextEditingController();

  List<InventoryMaterial> _items = const [];
  String _searchQuery = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _db.initialize();
      final items = await _db.getInventoryMaterials();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load materials: $e';
      });
    }
  }

  List<InventoryMaterial> get _filtered {
    if (_searchQuery.isEmpty) return _items;
    return _items.where((m) {
      final hay = '${m.name} ${m.sku ?? ''} ${m.supplier ?? ''} ${m.unit}'.toLowerCase();
      return hay.contains(_searchQuery);
    }).toList();
  }

  Future<void> _openForm({InventoryMaterial? existing}) async {
    final data = await showDialog<_MaterialFormData>(
      context: context,
      builder: (_) => _MaterialFormDialog(material: existing),
    );
    if (data == null) return;
    if (_adminAuth.adminAccessToken == null || _adminAuth.adminAccessToken!.isEmpty) {
      Toast.error(context, 'Session expired. Sign in again.');
      return;
    }
    try {
      if (existing == null) {
        await _db.createInventoryMaterial(
          name: data.name,
          sku: data.sku,
          materialType: data.materialType,
          unit: data.unit,
          costPerUnit: data.costPerUnit,
          quantityOnHand: data.quantityOnHand,
          reorderLevel: data.reorderLevel,
          supplier: data.supplier,
          notes: data.notes,
        );
        if (!mounted) return;
        Toast.success(context, 'Material added');
      } else {
        await _db.updateInventoryMaterial(
          id: existing.id,
          name: data.name,
          sku: data.sku,
          materialType: data.materialType,
          unit: data.unit,
          costPerUnit: data.costPerUnit,
          quantityOnHand: data.quantityOnHand,
          reorderLevel: data.reorderLevel,
          supplier: data.supplier,
          notes: data.notes,
        );
        if (!mounted) return;
        Toast.success(context, 'Material updated');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Save failed: $e');
    }
  }

  Future<void> _delete(InventoryMaterial material) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete material?'),
        content: Text('Remove "${material.name}" from inventory? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.deleteInventoryMaterial(id: material.id);
      if (!mounted) return;
      Toast.success(context, 'Material deleted');
      await _load();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final lowCount = _items.where((m) => m.isLowStock || m.isOutOfStock).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Materials Inventory',
          actions: const [],
          trailing: lowCount > 0
              ? Chip(
                  avatar: Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
                  label: Text('$lowCount need attention'),
                  backgroundColor: Colors.orange.shade50,
                )
              : null,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search materials by name, SKU, or supplier…',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add material'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8D6E63)),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _items.isEmpty ? 'No materials yet. Add plywood, hardware, or finishes.' : 'No matches.',
                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: filtered.length + 1,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index == 0) return const _MaterialsHeaderRow();
                        final m = filtered[index - 1];
                        return _MaterialRow(
                          material: m,
                          onEdit: () => _openForm(existing: m),
                          onDelete: () => _delete(m),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _MaterialsHeaderRow extends StatelessWidget {
  const _MaterialsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.grey[600],
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Material', style: style)),
          Expanded(flex: 2, child: Text('On hand', style: style)),
          Expanded(flex: 2, child: Text('Reorder at', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.material,
    required this.onEdit,
    required this.onDelete,
  });

  final InventoryMaterial material;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String statusLabel = material.stockStatusLabel;
    final Color statusColor;
    if (material.isOutOfStock) {
      statusColor = Colors.red.shade700;
    } else if (material.isLowStock) {
      statusColor = Colors.orange.shade800;
    } else {
      statusColor = Colors.green.shade700;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(material.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                if (material.sku != null && material.sku!.isNotEmpty)
                  Text('SKU: ${material.sku}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(
                  '${material.unit}${material.supplier != null ? ' · ${material.supplier}' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${material.quantityOnHand} ${material.unit}'),
          ),
          Expanded(flex: 2, child: Text('${material.reorderLevel}')),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaterialFormData {
  _MaterialFormData({
    required this.name,
    this.sku,
    required this.materialType,
    required this.unit,
    required this.costPerUnit,
    required this.quantityOnHand,
    required this.reorderLevel,
    this.supplier,
    this.notes,
  });

  final String name;
  final String? sku;
  final String materialType;
  final String unit;
  final double costPerUnit;
  final double quantityOnHand;
  final double reorderLevel;
  final String? supplier;
  final String? notes;
}

class _MaterialFormDialog extends StatefulWidget {
  const _MaterialFormDialog({this.material});

  final InventoryMaterial? material;

  @override
  State<_MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<_MaterialFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _cost;
  late final TextEditingController _qty;
  late final TextEditingController _reorder;
  late final TextEditingController _supplier;
  late final TextEditingController _notes;

  String _selectedType = 'Other';
  String _selectedUnit = 'pcs';

  @override
  void initState() {
    super.initState();
    final m = widget.material;
    _name = TextEditingController(text: m?.name ?? '');
    _sku = TextEditingController(text: m?.sku ?? '');
    _cost = TextEditingController(text: m?.costPerUnit.toString() ?? '0');
    _qty = TextEditingController(text: m?.quantityOnHand.toString() ?? '0');
    _reorder = TextEditingController(text: m?.reorderLevel.toString() ?? '0');
    _supplier = TextEditingController(text: m?.supplier ?? '');
    _notes = TextEditingController(text: m?.notes ?? '');
    _selectedType = m?.materialType ?? 'Other';
    _selectedUnit = m?.unit ?? 'pcs';
    if (!InventoryMaterial.materialTypes.contains(_selectedType)) {
      _selectedType = 'Other';
    }
    if (!InventoryMaterial.units.contains(_selectedUnit)) {
      _selectedUnit = 'pcs';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _cost.dispose();
    _qty.dispose();
    _reorder.dispose();
    _supplier.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final reorder = double.tryParse(_reorder.text.trim()) ?? 0;
    final cost = double.tryParse(_cost.text.trim()) ?? 0;
    Navigator.pop(
      context,
      _MaterialFormData(
        name: name,
        sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
        materialType: _selectedType,
        unit: _selectedUnit,
        costPerUnit: cost < 0 ? 0 : cost,
        quantityOnHand: qty < 0 ? 0 : qty,
        reorderLevel: reorder < 0 ? 0 : reorder,
        supplier: _supplier.text.trim().isEmpty ? null : _supplier.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: _materialFieldDecoration(label: label),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.material != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEdit ? 'Edit material' : 'Add material',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6D4C41),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _name,
                        decoration: _materialFieldDecoration(label: 'Name *'),
                      ),
                      TextField(
                        controller: _sku,
                        decoration: _materialFieldDecoration(label: 'SKU'),
                      ),
                      _dropdown(
                        label: 'Type',
                        value: _selectedType,
                        items: InventoryMaterial.materialTypes,
                        onChanged: (v) => setState(() => _selectedType = v ?? 'Other'),
                      ),
                      _dropdown(
                        label: 'Unit',
                        value: _selectedUnit,
                        items: InventoryMaterial.units,
                        onChanged: (v) => setState(() => _selectedUnit = v ?? 'pcs'),
                      ),
                      TextField(
                        controller: _cost,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _materialFieldDecoration(label: 'Cost per unit (PHP)'),
                      ),
                      TextField(
                        controller: _qty,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _materialFieldDecoration(label: 'Quantity on hand'),
                      ),
                      TextField(
                        controller: _reorder,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _materialFieldDecoration(
                          label: 'Reorder level',
                          helperText: 'Alert triggers when stock reaches this number',
                        ),
                      ),
                      TextField(
                        controller: _supplier,
                        decoration: _materialFieldDecoration(label: 'Supplier'),
                      ),
                      TextField(
                        controller: _notes,
                        maxLines: 3,
                        decoration: _materialFieldDecoration(label: 'Notes'),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8D6E63)),
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
}
