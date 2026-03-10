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

enum PaymentMethod { gcash, cod }

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


