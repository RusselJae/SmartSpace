/// Customer support intake forms (mirrors backend catalog keys).
class SupportFormFieldDef {
  const SupportFormFieldDef({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.placeholder,
    this.options = const [],
  });

  final String key;
  final String label;
  /// `text` | `textarea` | `select`
  final String type;
  final bool required;
  final String? placeholder;
  final List<String> options;
}

class SupportFormDef {
  const SupportFormDef({
    required this.type,
    required this.title,
    required this.description,
    required this.fields,
  });

  final String type;
  final String title;
  final String description;
  final List<SupportFormFieldDef> fields;
}

const List<SupportFormDef> kSupportFormCatalog = <SupportFormDef>[
  SupportFormDef(
    type: 'custom_quote',
    title: 'Custom quote request',
    description: 'Share dimensions and style so we can prepare a quote.',
    fields: [
      SupportFormFieldDef(key: 'itemName', label: 'Item / piece name', type: 'text', required: true),
      SupportFormFieldDef(
        key: 'dimensions',
        label: 'Dimensions (L × W × H)',
        type: 'text',
        required: true,
        placeholder: 'e.g. 200cm × 90cm × 75cm',
      ),
      SupportFormFieldDef(key: 'materialFinish', label: 'Material & finish', type: 'text', required: true),
      SupportFormFieldDef(key: 'orderId', label: 'Order ID (if any)', type: 'text'),
      SupportFormFieldDef(key: 'notes', label: 'Additional notes', type: 'textarea'),
    ],
  ),
  SupportFormDef(
    type: 'order_issue',
    title: 'Order issue',
    description: 'Report a problem with payment, delivery, or your order.',
    fields: [
      SupportFormFieldDef(key: 'orderId', label: 'Order ID', type: 'text', required: true),
      SupportFormFieldDef(
        key: 'issueType',
        label: 'Issue type',
        type: 'select',
        required: true,
        options: ['Payment', 'Delivery', 'Product quality', 'Other'],
      ),
      SupportFormFieldDef(key: 'description', label: 'Describe the issue', type: 'textarea', required: true),
    ],
  ),
  SupportFormDef(
    type: 'delivery_change',
    title: 'Delivery change',
    description: 'Request an address or schedule update before dispatch.',
    fields: [
      SupportFormFieldDef(key: 'orderId', label: 'Order ID', type: 'text', required: true),
      SupportFormFieldDef(key: 'newAddress', label: 'New delivery address', type: 'textarea', required: true),
      SupportFormFieldDef(
        key: 'preferredDate',
        label: 'Preferred delivery window',
        type: 'text',
        placeholder: 'e.g. June 10–12, mornings',
      ),
    ],
  ),
  SupportFormDef(
    type: 'damage_claim',
    title: 'Damage or defect report',
    description: 'Tell us what arrived damaged — attach photos in chat after you submit.',
    fields: [
      SupportFormFieldDef(key: 'orderId', label: 'Order ID', type: 'text', required: true),
      SupportFormFieldDef(key: 'description', label: 'What went wrong?', type: 'textarea', required: true),
      SupportFormFieldDef(key: 'receivedAt', label: 'Date received', type: 'text'),
    ],
  ),
];

SupportFormDef? supportFormDefForType(String formType) {
  final t = formType.trim();
  for (final def in kSupportFormCatalog) {
    if (def.type == t) return def;
  }
  return null;
}
