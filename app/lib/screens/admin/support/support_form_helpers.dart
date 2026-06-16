import '../../../models/order_record.dart';
import '../../../models/support_form_request.dart';
import 'support_conversation_tags.dart';
import 'support_quick_replies.dart';

/// Conversation tag applied automatically when admin sends a matching form.
String? supportTagForFormType(String formType) {
  switch (formType.trim()) {
    case 'damage_claim':
      return 'Damage report';
    case 'delivery_change':
      return 'Delivery issue';
    case 'custom_quote':
      return 'Made-to-order inquiry';
    case 'order_issue':
      return 'Order status';
    default:
      return null;
  }
}

bool isOrderCancelled(OrderRecord? order) =>
    order != null && order.status.trim().toLowerCase() == 'cancelled';

/// Whether a structured form can be sent given the customer's latest order state.
bool isSupportFormAvailable(String formType, OrderRecord? order) {
  if (!isOrderCancelled(order)) return true;
  switch (formType) {
    case 'delivery_change':
    case 'damage_claim':
      return false;
    default:
      return true;
  }
}

/// Quick replies that don't apply when the latest order was cancelled.
bool isQuickReplyAvailable(SupportQuickReply reply, OrderRecord? order) {
  if (!isOrderCancelled(order)) return true;
  const hidden = {'delivery_schedule', 'damage_return', 'mto_lead_time'};
  return !hidden.contains(reply.id);
}

/// Extra canned replies surfaced only for cancelled-order conversations.
const List<SupportQuickReply> kCancelledOrderQuickReplies = <SupportQuickReply>[
  SupportQuickReply(
    id: 'refund_status',
    label: 'Refund status',
    body:
        'Hi! I see your order was cancelled. Refunds for verified GCash payments are processed within 5–7 business days back to the same account. If you paid COD only a down payment, we’ll confirm what applies to your case — please share your Order ID.',
  ),
  SupportQuickReply(
    id: 'reorder',
    label: 'Reorder',
    body:
        'You’re welcome to place a new order anytime in the app. If you’d like help picking the same items or a custom quote, tell us what you need and we’ll assist.',
  ),
];

/// Sidebar fields derived from order + latest submitted form payloads.
class SupportOrderSidebarData {
  const SupportOrderSidebarData({
    required this.orderId,
    required this.status,
    required this.items,
    required this.delivery,
    required this.payment,
    required this.total,
    this.deliveryFromForm = false,
    this.address,
    this.addressFromForm = false,
  });

  final String orderId;
  final String status;
  final String items;
  final String delivery;
  final String payment;
  final String total;
  final bool deliveryFromForm;
  final String? address;
  final bool addressFromForm;
}

SupportOrderSidebarData buildSupportOrderSidebar({
  required OrderRecord? order,
  required Map<String, String> productNames,
  required Iterable<SupportFormRequest> formRequests,
  required String Function(String?) paymentMethodLabel,
  required String Function(OrderRecord order) deliveryFromOrder,
}) {
  if (order == null) {
    return const SupportOrderSidebarData(
      orderId: '—',
      status: '—',
      items: '—',
      delivery: '—',
      payment: '—',
      total: '—',
    );
  }

  var delivery = deliveryFromOrder(order);
  var deliveryFromForm = false;
  String? address;
  var addressFromForm = false;

  // Newest submitted forms first — latest customer input wins for sidebar display.
  final submitted = formRequests.where((f) => f.isSubmitted).toList()
    ..sort((a, b) {
      final aT = a.submittedAt ?? a.createdAt;
      final bT = b.submittedAt ?? b.createdAt;
      return bT.compareTo(aT);
    });

  for (final form in submitted) {
    final payload = form.payload;
    if (payload == null) continue;

    if (form.formType == 'delivery_change') {
      final preferred = payload['preferredDate']?.trim() ?? '';
      if (preferred.isNotEmpty) {
        delivery = preferred;
        deliveryFromForm = true;
      }
      final newAddress = payload['newAddress']?.trim() ?? '';
      if (newAddress.isNotEmpty) {
        address = newAddress;
        addressFromForm = true;
      }
    }
  }

  final items = order.productIds.map((id) => productNames[id] ?? id).join(', ');
  final status = order.status.isNotEmpty
      ? order.status[0].toUpperCase() + order.status.substring(1)
      : '—';

  return SupportOrderSidebarData(
    orderId: order.id,
    status: status,
    items: items.isEmpty ? '—' : items,
    delivery: delivery,
    payment: paymentMethodLabel(order.shippingAddress['paymentMethod']?.toString()),
    total: '₱${order.totalAmount.toStringAsFixed(2)}',
    deliveryFromForm: deliveryFromForm,
    address: address,
    addressFromForm: addressFromForm,
  );
}

/// Merges an auto tag from a sent form without removing manually added tags.
List<String> mergeAutoTag(List<String> currentTags, String formType) {
  final auto = supportTagForFormType(formType);
  if (auto == null || auto.isEmpty) return currentTags;
  if (currentTags.contains(auto)) return currentTags;
  return [...currentTags, auto];
}

/// Validates tag is from our known set (optional guard for manual adds).
bool isKnownSupportTag(String tag) => kSupportConversationTags.contains(tag);
