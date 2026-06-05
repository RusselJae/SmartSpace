/**
 * Support intake forms — shared catalog for API + link generation.
 * Keys are stable; do not rename without a migration plan.
 */

export type SupportFormFieldType = 'text' | 'textarea' | 'select';

export type SupportFormField = {
  readonly key: string;
  readonly label: string;
  readonly type: SupportFormFieldType;
  readonly required?: boolean;
  readonly placeholder?: string;
  readonly options?: readonly string[];
};

export type SupportFormDefinition = {
  readonly type: string;
  readonly title: string;
  readonly description: string;
  readonly fields: readonly SupportFormField[];
};

export const SUPPORT_FORM_CATALOG: readonly SupportFormDefinition[] = [
  {
    type: 'custom_quote',
    title: 'Custom quote request',
    description: 'Share dimensions and style so we can prepare a quote.',
    fields: [
      { key: 'itemName', label: 'Item / piece name', type: 'text', required: true },
      { key: 'dimensions', label: 'Dimensions (L × W × H)', type: 'text', required: true, placeholder: 'e.g. 200cm × 90cm × 75cm' },
      { key: 'materialFinish', label: 'Material & finish', type: 'text', required: true },
      { key: 'orderId', label: 'Order ID (if any)', type: 'text' },
      { key: 'notes', label: 'Additional notes', type: 'textarea' },
    ],
  },
  {
    type: 'order_issue',
    title: 'Order issue',
    description: 'Report a problem with payment, delivery, or your order.',
    fields: [
      { key: 'orderId', label: 'Order ID', type: 'text', required: true },
      {
        key: 'issueType',
        label: 'Issue type',
        type: 'select',
        required: true,
        options: ['Payment', 'Delivery', 'Product quality', 'Other'],
      },
      { key: 'description', label: 'Describe the issue', type: 'textarea', required: true },
    ],
  },
  {
    type: 'delivery_change',
    title: 'Delivery change',
    description: 'Request an address or schedule update before dispatch.',
    fields: [
      { key: 'orderId', label: 'Order ID', type: 'text', required: true },
      { key: 'newAddress', label: 'New delivery address', type: 'textarea', required: true },
      { key: 'preferredDate', label: 'Preferred delivery window', type: 'text', placeholder: 'e.g. June 10–12, mornings' },
    ],
  },
  {
    type: 'damage_claim',
    title: 'Damage or defect report',
    description: 'Tell us what arrived damaged — attach photos in chat after you submit.',
    fields: [
      { key: 'orderId', label: 'Order ID', type: 'text', required: true },
      { key: 'description', label: 'What went wrong?', type: 'textarea', required: true },
      { key: 'receivedAt', label: 'Date received', type: 'text' },
    ],
  },
] as const;

export const getSupportFormDefinition = (formType: string): SupportFormDefinition | null => {
  const t = formType.trim();
  return SUPPORT_FORM_CATALOG.find((f) => f.type === t) ?? null;
};

/** Deep link token embedded in support chat messages. */
export const buildSupportFormLink = (formType: string, requestId: string): string => {
  return `support-form/${formType}?request=${requestId}`;
};

export const parseSupportFormLink = (
  text: string,
): { formType: string; requestId: string } | null => {
  const match = text.match(/support-form\/([a-z0-9_]+)\?request=([a-zA-Z0-9_-]+)/i);
  if (!match) return null;
  return { formType: match[1], requestId: match[2] };
};
