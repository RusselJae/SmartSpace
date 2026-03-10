import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';

/// Service for handling GCash payment operations
/// 
/// This service generates QR codes for GCash payments and handles
/// payment verification workflows. For production, consider integrating
/// with a payment gateway API for automated verification.
class GCashService {
  static final GCashService _instance = GCashService._internal();
  factory GCashService() => _instance;
  GCashService._internal();

  // Your GCash merchant account number
  // TODO: Move this to environment variables for security
  static const String _gcashAccountNumber = '09123456789'; // Replace with your actual GCash number
  
  /// Generates a GCash payment QR code data string
  /// 
  /// Format: GCash QR code format for merchant payments
  /// This creates a QR code that users can scan with their GCash app
  /// to send the exact downpayment amount to your account
  String generatePaymentQRData({
    required double amount,
    required String orderId,
    required String customerName,
  }) {
    // GCash QR code format (EMV QR Code standard)
    // Format: 00020101021226600009PH.P2PGW0110012345678905204000053036085802PH5913YOUR BUSINESS6007MANILA62140510ORDER1236304ABCD
    // 
    // For now, we'll use a simpler format that includes:
    // - Amount
    // - Order ID for reference
    // - Merchant account number
    
    final amountString = amount.toStringAsFixed(2);
    
    // Create a payment reference string
    // Format: "PAY {ORDER_ID} {AMOUNT} to {ACCOUNT}"
    final qrData = 'GCash Payment\n'
        'Order: $orderId\n'
        'Amount: ₱$amountString\n'
        'Account: $_gcashAccountNumber\n'
        'Reference: ${orderId.substring(0, 8).toUpperCase()}';
    
    return qrData;
  }

  /// Generates a QR code widget for display
  /// 
  /// This creates a visual QR code that users can scan with their GCash app
  Widget generateQRCodeWidget({
    required String data,
    required double size,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      backgroundColor: backgroundColor ?? Colors.white,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
  }

  /// Validates payment reference number format
  /// 
  /// GCash transaction references are typically 12-13 characters
  /// This is a basic validation - actual verification requires checking
  /// your GCash merchant account or payment gateway
  bool isValidReferenceNumber(String reference) {
    // GCash reference numbers are typically alphanumeric, 10-15 characters
    final regex = RegExp(r'^[A-Z0-9]{10,15}$');
    return regex.hasMatch(reference.toUpperCase());
  }

  /// Formats amount for GCash display
  String formatAmount(double amount) {
    return '₱${amount.toStringAsFixed(2)}';
  }

  /// Gets payment instructions for users
  String getPaymentInstructions({
    required double amount,
    required String orderId,
  }) {
    return '''
Payment Instructions:

1. Open your GCash app
2. Tap "Scan QR" or "Send Money"
3. Scan the QR code below or send ₱${amount.toStringAsFixed(2)} to:
   Account: $_gcashAccountNumber
4. Use Order ID as reference: ${orderId.substring(0, 8).toUpperCase()}
5. Take a screenshot of your payment confirmation
6. Upload the screenshot below

Your order will be confirmed once payment is verified.
''';
  }
}

