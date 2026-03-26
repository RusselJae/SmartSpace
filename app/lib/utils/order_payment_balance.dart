// =============================================================================
// Order payment / installment helpers (PayMongo down-payment plan policy).
//
// Policy: 0% for the first 3 calendar months from **first PayMongo payment**
// (down payment posted). Backend sets `firstInstallmentPaidAt` (ISO) when the
// first tranche clears. Before that, we show a “window starts after payment” line.
// Legacy: if status is `downpayment_received` but timestamp is missing, we fall
// back to `order.createdAt + 3 months`.
// =============================================================================

import '../models/order_record.dart';

/// Parses numeric fields that may arrive as [num] or [String] from the API.
double? parseShippingDouble(Map<String, dynamic> map, String key) {
  final v = map[key];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// PayMongo installment plan with a down payment + remaining balance.
bool isInstallmentDownPaymentPlan(OrderRecord order) {
  return order.shippingAddress['paymentPlan']?.toString() == 'downpayment';
}

/// Hulugan path (40% DP, 6% on financed balance) vs Lay-away.
bool isHuluganOrder(OrderRecord order) {
  return order.shippingAddress['orderOption']?.toString() == 'hulugan';
}

/// Order is settled for UI purposes (no balance row / countdown).
bool isInstallmentFullyPaid(OrderRecord order) {
  final ps = order.shippingAddress['paymentStatus']?.toString();
  if (ps == 'completed') return true;
  final rem = parseShippingDouble(order.shippingAddress, 'remainingBalance');
  return rem != null && rem <= 0.01;
}

/// Show remaining balance + interest countdown for down-payment orders still owing money.
bool shouldShowInstallmentBalanceUi(OrderRecord order) {
  if (!isInstallmentDownPaymentPlan(order)) return false;
  if (isInstallmentFullyPaid(order)) return false;
  final rem = parseShippingDouble(order.shippingAddress, 'remainingBalance');
  return rem != null && rem > 0.01;
}

/// ISO string from API when first PayMongo tranche (down payment) was recorded.
DateTime? parseFirstInstallmentPaidAt(OrderRecord order) {
  final v = order.shippingAddress['firstInstallmentPaidAt'];
  if (v == null) return null;
  if (v is String && v.isNotEmpty) {
    try {
      return DateTime.parse(v);
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// +3 calendar months from [anchor] (local).
DateTime _addThreeCalendarMonths(DateTime anchorLocal) {
  return DateTime(
    anchorLocal.year,
    anchorLocal.month + 3,
    anchorLocal.day,
    anchorLocal.hour,
    anchorLocal.minute,
    anchorLocal.second,
  );
}

/// End of the 3-month 0% / no-daily-fee window; **null** if the window hasn’t started yet.
DateTime? zeroInterestPeriodEndsAt(OrderRecord order) {
  final anchor = parseFirstInstallmentPaidAt(order);
  if (anchor != null) {
    return _addThreeCalendarMonths(anchor.toLocal());
  }
  // Legacy: down payment already recorded but no timestamp column (old DB)
  final ps = order.shippingAddress['paymentStatus']?.toString();
  if (ps == 'downpayment_received' && isInstallmentDownPaymentPlan(order)) {
    return _addThreeCalendarMonths(order.createdAt.toLocal());
  }
  return null;
}

/// Remaining balance label for lists (whole pesos when possible).
String formatRemainingBalancePesos(OrderRecord order) {
  final rem = parseShippingDouble(order.shippingAddress, 'remainingBalance');
  if (rem == null) return '—';
  if (rem >= 1000 || rem == rem.roundToDouble()) {
    return '₱${rem.toStringAsFixed(0)}';
  }
  return '₱${rem.toStringAsFixed(2)}';
}

/// Compact cell for admin table: outstanding amount or em dash.
String adminOrdersBalanceColumnText(OrderRecord order) {
  final rem = parseShippingDouble(order.shippingAddress, 'remainingBalance');
  if (shouldShowInstallmentBalanceUi(order)) {
    return formatRemainingBalancePesos(order);
  }
  if (rem != null) {
    return rem <= 0.01 ? '₱0' : formatRemainingBalancePesos(order);
  }
  return '—';
}

/// Highlight balance column when something is still owed.
bool adminOrdersBalanceColumnHighlighted(OrderRecord order) {
  final rem = parseShippingDouble(order.shippingAddress, 'remainingBalance');
  return rem != null && rem > 0.01;
}

/// Short status line for cards: time left before daily fee window, or overdue notice.
String installmentInterestCountdownLine(OrderRecord order, DateTime now) {
  if (!shouldShowInstallmentBalanceUi(order)) return '';

  final ps = order.shippingAddress['paymentStatus']?.toString();
  // First PayMongo payment not posted yet — policy window hasn’t started.
  if (ps == 'pending' && parseFirstInstallmentPaidAt(order) == null) {
    return 'Your 3-month 0% period starts when your first PayMongo payment is confirmed.';
  }

  final end = zeroInterestPeriodEndsAt(order);
  if (end == null) {
    return 'Complete your PayMongo payment to see your balance deadline.';
  }

  if (now.isAfter(end)) {
    final suffix = isHuluganOrder(order)
        ? ' Your balance includes 6% on the financed portion.'
        : '';
    return 'Late fee may apply: ₱100/day until fully paid — settle your remaining balance.$suffix';
  }
  final diff = end.difference(now);
  final days = diff.inDays;
  if (days >= 1) {
    return '$days day${days == 1 ? '' : 's'} left before ₱100/day late fee window (0% period ends '
        '${end.day}/${end.month}/${end.year}).';
  }
  if (diff.inHours >= 1) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} left before late fee window.';
  }
  final mins = diff.inMinutes.clamp(0, 59);
  return '$mins min left before late fee window — pay remaining balance soon.';
}
