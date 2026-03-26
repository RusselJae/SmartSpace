// =============================================================
// Simple data models passed between checkout screens.
// These will later be replaced by a centralized state (e.g., provider/bloc).
// =============================================================

class AddressData {
  AddressData({
    required this.fullName,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.postalCode,
    required this.phone,
  });

  final String fullName;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String postalCode;
  final String phone;
}

class DeliveryData {
  DeliveryData({
    required this.dateLabel,
    required this.slotLabel,
  });

  final String dateLabel; // e.g., "Oct 12, 2025"
  final String slotLabel; // e.g., "10:00 - 12:00"
}

/// Checkout payment options. PayMongo = hosted gateway (test/live keys on server).
enum PaymentMethod { gcash, cod, paymongo }

/// Order Summary: PayMongo-only checkout — user picks full pay vs down payment (installment policy in UI).
enum CheckoutPaymentPlan {
  /// Single PayMongo session for the full order total.
  full,

  /// Split pay: choose [CheckoutOrderOption] below.
  downpayment,
}

/// When [CheckoutPaymentPlan.downpayment] — Lay-away (0%, ₱3k–₱5k DP) vs Hulugan (40% DP, 6% on balance).
enum CheckoutOrderOption {
  /// ₱3k–₱5k DP, 0% interest, deliver when fully paid, custom design allowed.
  layaway,

  /// 40% DP, 6% on financed amount, in-stock items only, ship ~10–12 days after order is confirmed.
  hulugan,
}

class PaymentData {
  PaymentData({
    required this.method,
    this.cardHolder,
    this.cardNumberMasked,
  });

  final PaymentMethod method;
  final String? cardHolder;
  final String? cardNumberMasked;
}


