/// Canned support messages staff/owner can tap to insert into the reply composer.
class SupportQuickReply {
  const SupportQuickReply({
    required this.id,
    required this.label,
    required this.body,
  });

  final String id;
  final String label;
  final String body;
}

/// Built-in templates for Wood Home / SmartSpace support (editable later via settings if needed).
const List<SupportQuickReply> kSupportQuickReplies = <SupportQuickReply>[
  SupportQuickReply(
    id: 'order_status',
    label: 'Order status',
    body:
        'Hi! Thanks for reaching out. Please share your Order ID (found in Orders → Order details) and we’ll check production and delivery status for you.',
  ),
  SupportQuickReply(
    id: 'how_to_order',
    label: 'How to order',
    body:
        'You can browse the catalog in the app, add items to cart, and checkout with GCash (upload payment proof) or Cash on Delivery (down payment may apply). For custom pieces, use Made-to-Order or tell us your dimensions and style here.',
  ),
  SupportQuickReply(
    id: 'payment_gcash',
    label: 'GCash payment',
    body:
        'To pay via GCash: complete checkout, scan the QR on the payment screen, pay the amount shown, then upload a clear screenshot of your receipt in the same screen. We’ll verify and update your order once confirmed.',
  ),
  SupportQuickReply(
    id: 'payment_cod',
    label: 'COD / down payment',
    body:
        'For Cash on Delivery orders, a down payment may be required before we start production. We’ll confirm the exact amount and schedule after you place the order.',
  ),
  SupportQuickReply(
    id: 'mto_lead_time',
    label: 'Made-to-order lead time',
    body:
        'Custom / made-to-order pieces typically take about 6–7 weeks depending on materials and our production queue. We’ll confirm the timeline once your specs and payment are approved.',
  ),
  SupportQuickReply(
    id: 'delivery_schedule',
    label: 'Delivery scheduling',
    body:
        'We’ll contact you to schedule delivery once your order is ready. Please confirm your delivery address and a contact number that’s reachable on delivery day.',
  ),
  SupportQuickReply(
    id: 'catalog_help',
    label: 'Catalog & AR',
    body:
        'Open any product to view photos, specs, and AR preview in your room. If you need help choosing size or style, tell us your room dimensions and we can recommend options.',
  ),
  SupportQuickReply(
    id: 'quote_followup',
    label: 'Quote follow-up',
    body:
        'Thanks for your interest! We’re preparing your quote based on the details you sent. We’ll message you here with price, lead time, and next steps shortly.',
  ),
  SupportQuickReply(
    id: 'damage_return',
    label: 'Damage / concern',
    body:
        'We’re sorry to hear that. Please send photos of the item and packaging, plus your Order ID, within 48 hours of delivery so we can review and assist.',
  ),
  SupportQuickReply(
    id: 'closing',
    label: 'Closing',
    body:
        'You’re welcome! If anything else comes up, reply here anytime. Have a great day.',
  ),
];
