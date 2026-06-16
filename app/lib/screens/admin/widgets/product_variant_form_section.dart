import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../models/inventory_material.dart';
import '../../../models/product.dart';
import '../../../models/product_variant.dart';
import '../../../utils/dimension_format.dart';

/// One BOM row in the variant editor (draft state).
class BomLineDraft {
  BomLineDraft({
    this.inventoryMaterialId,
    String quantity = '',
  }) : quantity = TextEditingController(text: quantity);

  String? inventoryMaterialId;
  final TextEditingController quantity;

  void dispose() => quantity.dispose();

  static BomLineDraft fromBomLine(ProductVariantBomLine line) {
    return BomLineDraft(
      inventoryMaterialId: line.inventoryMaterialId,
      quantity: line.quantityRequired.toString(),
    );
  }
}

/// Draft state for a single product variant (dimensions + BOM).
class VariantDraft {
  VariantDraft({
    this.serverId,
    String variantName = 'Standard',
    this.isDefault = false,
    TextEditingController? nameController,
    TextEditingController? widthIn,
    TextEditingController? heightIn,
    TextEditingController? depthIn,
    TextEditingController? modelBaseScale,
    List<BomLineDraft>? bomLines,
    this.selectedTab = 0,
  })  : name = nameController ?? TextEditingController(text: variantName),
        widthIn = widthIn ?? TextEditingController(),
        heightIn = heightIn ?? TextEditingController(),
        depthIn = depthIn ?? TextEditingController(),
        modelBaseScale = modelBaseScale ?? TextEditingController(text: '1.00'),
        bomLines = bomLines ?? [BomLineDraft()];

  String? serverId;
  final TextEditingController name;
  bool isDefault;
  final TextEditingController widthIn;
  final TextEditingController heightIn;
  final TextEditingController depthIn;
  final TextEditingController modelBaseScale;
  List<BomLineDraft> bomLines;
  int selectedTab;

  factory VariantDraft.fromProduct(Product product, {String variantName = 'Standard'}) {
    return VariantDraft(
      variantName: variantName,
      isDefault: true,
      widthIn: TextEditingController(
        text: DimensionFormat.metersToInchesFieldValue(product.realWidthMeters),
      ),
      heightIn: TextEditingController(
        text: DimensionFormat.metersToInchesFieldValue(product.realHeightMeters),
      ),
      depthIn: TextEditingController(
        text: DimensionFormat.metersToInchesFieldValue(product.realDepthMeters),
      ),
      modelBaseScale: TextEditingController(
        text: product.modelBaseScale.toStringAsFixed(2),
      ),
    );
  }

  factory VariantDraft.fromVariant(ProductVariant variant) {
    return VariantDraft(
      serverId: variant.id,
      variantName: variant.name,
      isDefault: variant.isDefault,
      widthIn: TextEditingController(
        text: DimensionFormat.metersToInchesFieldValue(variant.realWidthM),
      ),
      heightIn: TextEditingController(
        text: DimensionFormat.metersToInchesFieldValue(variant.realHeightM),
      ),
      depthIn: TextEditingController(
        text: DimensionFormat.metersToInchesFieldValue(variant.realDepthM),
      ),
      modelBaseScale: TextEditingController(
        text: variant.modelBaseScale.toStringAsFixed(2),
      ),
      bomLines: variant.bomLines.isEmpty
          ? [BomLineDraft()]
          : variant.bomLines.map(BomLineDraft.fromBomLine).toList(),
    );
  }

  void dispose() {
    name.dispose();
    widthIn.dispose();
    heightIn.dispose();
    depthIn.dispose();
    modelBaseScale.dispose();
    for (final row in bomLines) {
      row.dispose();
    }
  }

  Map<String, dynamic> toSyncPayload() {
    final widthM = DimensionFormat.inchesFieldToMeters(widthIn.text);
    final heightM = DimensionFormat.inchesFieldToMeters(heightIn.text);
    final depthM = DimensionFormat.inchesFieldToMeters(depthIn.text);
    final scale = double.tryParse(modelBaseScale.text.trim()) ?? 1;

    final bomPayload = <Map<String, dynamic>>[];
    for (final row in bomLines) {
      final materialId = row.inventoryMaterialId;
      final qty = double.tryParse(row.quantity.text.trim());
      if (materialId == null || materialId.isEmpty || qty == null || qty <= 0) continue;
      bomPayload.add({
        'inventoryMaterialId': materialId,
        'quantityRequired': qty,
      });
    }

    return {
      if (serverId != null) 'serverId': serverId,
      'name': name.text.trim().isEmpty ? 'Standard' : name.text.trim(),
      'isDefault': isDefault,
      'realWidthM': widthM,
      'realHeightM': heightM,
      'realDepthM': depthM,
      'modelBaseScale': scale,
      'bomLines': bomPayload,
    };
  }
}

/// Variant list with per-variant Dimensions / Materials (BOM) tabs.
class ProductVariantFormSection extends StatelessWidget {
  const ProductVariantFormSection({
    super.key,
    required this.variants,
    required this.inventoryMaterials,
    required this.onChanged,
    required this.onAddVariant,
    required this.onRemoveVariant,
    required this.onDefaultChanged,
    required this.onProductMaterialSelected,
    required this.fieldErrors,
    required this.buildField,
  });

  final List<VariantDraft> variants;
  final List<InventoryMaterial> inventoryMaterials;
  final VoidCallback onChanged;
  final VoidCallback onAddVariant;
  final ValueChanged<int> onRemoveVariant;
  final void Function(int index) onDefaultChanged;
  final void Function(String? materialLabel) onProductMaterialSelected;
  final Map<String, String?> fieldErrors;
  final Widget Function(
    TextEditingController controller,
    String label, {
    int maxLines,
    TextInputType keyboardType,
    String? errorText,
  }) buildField;

  InventoryMaterial? _materialById(String? id) {
    if (id == null) return null;
    for (final m in inventoryMaterials) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Match catalog wood label (e.g. Mahogany) to an inventory material row.
  static InventoryMaterial? matchInventoryMaterial(String? label, List<InventoryMaterial> materials) {
    if (label == null || label.trim().isEmpty) return null;
    final needle = label.trim().toLowerCase();
    for (final m in materials) {
      if (m.name.toLowerCase() == needle) return m;
    }
    for (final m in materials) {
      if (m.name.toLowerCase().contains(needle)) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Variants',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6D4C41),
                  ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onAddVariant,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add variant'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (fieldErrors['variants'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              fieldErrors['variants']!,
              style: const TextStyle(color: CupertinoColors.systemRed, fontSize: 12),
            ),
          ),
        ...List.generate(variants.length, (index) => _buildVariantCard(context, index)),
      ],
    );
  }

  Widget _buildVariantCard(BuildContext context, int index) {
    final draft = variants[index];
    final tabIndex = draft.selectedTab.clamp(0, 1);
    final defaultIndex = variants.indexWhere((v) => v.isDefault);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.name,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Variant name',
                    filled: true,
                    fillColor: Color(0xFFF8F8F8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Radio<int>(
                value: index,
                groupValue: defaultIndex >= 0 ? defaultIndex : 0,
                onChanged: (_) => onDefaultChanged(index),
              ),
              const Text('Default', style: TextStyle(fontSize: 13)),
              if (variants.length > 1)
                IconButton(
                  onPressed: () => onRemoveVariant(index),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Remove variant',
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _tabChip(context, index, 0, 'Dimensions'),
                _tabChip(context, index, 1, 'Materials (BOM)'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: tabIndex == 0
                ? _buildDimensionsTab(index)
                : _buildBomTab(context, index),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(BuildContext context, int variantIndex, int tab, String label) {
    final draft = variants[variantIndex];
    final selected = draft.selectedTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          draft.selectedTab = tab;
          onChanged();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? const Color(0xFF6D4C41) : Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDimensionsTab(int index) {
    final draft = variants[index];
    final prefix = 'variant_${index}_';
    return Column(
      key: ValueKey('dim_$index'),
      children: [
        Row(
          children: [
            Expanded(
              child: buildField(
                draft.widthIn,
                'Width (in)',
                keyboardType: TextInputType.number,
                errorText: fieldErrors['${prefix}width'],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: buildField(
                draft.heightIn,
                'Height (in)',
                keyboardType: TextInputType.number,
                errorText: fieldErrors['${prefix}height'],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: buildField(
                draft.depthIn,
                'Depth (in)',
                keyboardType: TextInputType.number,
                errorText: fieldErrors['${prefix}depth'],
              ),
            ),
          ],
        ),
        buildField(
          draft.modelBaseScale,
          'Model base scale',
          keyboardType: TextInputType.number,
          errorText: fieldErrors['${prefix}scale'],
        ),
      ],
    );
  }

  Widget _buildBomTab(BuildContext context, int index) {
    final draft = variants[index];
    return Column(
      key: ValueKey('bom_$index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Text('Material', style: _headerStyle(context))),
                    Expanded(flex: 2, child: Text('Quantity', style: _headerStyle(context))),
                    Expanded(flex: 2, child: Text('Unit', style: _headerStyle(context))),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
              if (draft.bomLines.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No materials yet. Add a row or pick a product Material above to prefill.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ),
              ...List.generate(draft.bomLines.length, (rowIndex) {
                final row = draft.bomLines[rowIndex];
                final selected = _materialById(row.inventoryMaterialId);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<String>(
                          value: row.inventoryMaterialId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: Color(0xFFF8F8F8),
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('Select material'),
                          items: inventoryMaterials
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m.id,
                                  child: Text(m.name, overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            row.inventoryMaterialId = value;
                            onChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: row.quantity,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: Color(0xFFF8F8F8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            selected?.unit ?? '—',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          draft.bomLines.removeAt(rowIndex);
                          if (draft.bomLines.isEmpty) {
                            draft.bomLines.add(BomLineDraft());
                          }
                          onChanged();
                        },
                        icon: const Icon(Icons.close, size: 20, color: Colors.red),
                        tooltip: 'Remove row',
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              draft.bomLines.add(BomLineDraft());
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add material row'),
          ),
        ),
      ],
    );
  }

  TextStyle? _headerStyle(BuildContext context) {
    return Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        );
  }
}
