import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/app_settings.dart';
import '../../services/app_settings_service.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../widgets/toast.dart';
import '../shell/tab_shell.dart';
import 'models.dart';
import 'success_screen.dart';

/// Payment confirmation screen with QR code and payment proof upload
/// 
/// Users must complete payment within 15 minutes or order will be cancelled
class PaymentConfirmationScreen extends StatefulWidget {
  const PaymentConfirmationScreen({
    super.key,
    required this.orderId,
    required this.paymentAmount,
    required this.paymentMethod,
    required this.totalAmount,
    required this.orderCreatedAt,
    this.resetTimer = false, // If true, use current time instead of orderCreatedAt
  });

  final String orderId;
  final double paymentAmount;
  final PaymentMethod paymentMethod;
  final double totalAmount;
  final DateTime orderCreatedAt;
  final bool resetTimer; // Flag to reset timer for repaid orders

  @override
  State<PaymentConfirmationScreen> createState() => _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState extends State<PaymentConfirmationScreen> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AuthService _auth = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final AppSettingsService _settingsService = AppSettingsService();
  
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  Timer? _autoCancelTimer;
  late DateTime _deadline;
  
  File? _paymentProofImage;
  bool _uploading = false;
  bool _paymentConfirmed = false;
  bool _orderExpired = false;
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  /// Load application settings for payment confirmation
  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.loadSettings();
      if (mounted) {
        setState(() {
          _settings = settings;
          final timerMinutes = settings.paymentConfirmationTimeMinutes;
          _remainingSeconds = timerMinutes * 60;
          // If resetTimer is true (repaying expired order), use current time instead of orderCreatedAt
          final startTime = widget.resetTimer ? DateTime.now() : widget.orderCreatedAt;
          _deadline = startTime.add(Duration(minutes: timerMinutes));
        });
        _startTimers();
        _checkPaymentStatus();
      }
    } catch (e) {
      // If settings fail to load, use defaults
      if (mounted) {
        setState(() {
          _settings = const AppSettings();
          _remainingSeconds = 15 * 60;
          // If resetTimer is true (repaying expired order), use current time instead of orderCreatedAt
          final startTime = widget.resetTimer ? DateTime.now() : widget.orderCreatedAt;
          _deadline = startTime.add(const Duration(minutes: 15));
        });
        _startTimers();
        _checkPaymentStatus();
      }
    }
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  void _stopTimers() {
    _countdownTimer?.cancel();
    _autoCancelTimer?.cancel();
  }

  int _calculateRemainingSeconds() {
    final diff = _deadline.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Start countdown timer and auto-cancel timer
  void _startTimers() {
    _remainingSeconds = _calculateRemainingSeconds();
    if (_remainingSeconds <= 0) {
      _cancelOrderAutomatically();
      return;
    }

    // Countdown timer for UI display
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final secondsLeft = _calculateRemainingSeconds();
      if (secondsLeft <= 0) {
        timer.cancel();
        _cancelOrderAutomatically();
      } else {
        setState(() {
          _remainingSeconds = secondsLeft;
        });
      }
    });

    // Auto-cancel timer (aligned with actual deadline)
    final durationUntilDeadline = _deadline.difference(DateTime.now());
    if (durationUntilDeadline.isNegative) {
      _cancelOrderAutomatically();
    } else {
      _autoCancelTimer = Timer(durationUntilDeadline, () {
        if (!mounted) return;
        _cancelOrderAutomatically();
      });
    }
  }

  /// Check if payment has already been confirmed
  Future<void> _checkPaymentStatus() async {
    try {
      final orders = await _db.getAllOrders();
      final order = orders.firstWhere(
        (o) => o.id == widget.orderId,
        orElse: () => throw Exception('Order not found'),
      );
      
      // Check if payment is already confirmed or order is expired
      final paymentStatus = order.shippingAddress['paymentStatus'] as String?;
      if (paymentStatus == 'confirmed' || paymentStatus == 'downpayment_paid') {
        if (mounted) {
          setState(() {
            _paymentConfirmed = true;
          });
          _stopTimers();
        }
      } else if ((order.status == 'expired' || order.status == 'cancelled') && !widget.resetTimer) {
        // Only show expired screen if this is not a repayment (resetTimer = false)
        // If resetTimer is true, we're repaying so show the payment screen instead
        if (mounted) {
          setState(() {
            _orderExpired = true;
          });
          _stopTimers();
        }
      }
    } catch (e) {
      developer.log('Error checking payment status: $e', name: 'PaymentConfirmation');
    }
  }

  /// Expire order automatically after configured time (instead of cancelling)
  Future<void> _cancelOrderAutomatically() async {
    if (_paymentConfirmed || _orderExpired) return;
    _stopTimers();
    
    try {
      await _db.updateOrderStatus(widget.orderId, 'expired');
      if (mounted) {
        final settings = _settings ?? const AppSettings();
        setState(() {
          _orderExpired = true;
        });
        Toast.error(context, 'Order expired: Payment not received within ${settings.paymentConfirmationTimeMinutes} minutes. You can repay this order.');
      }
    } catch (e) {
      developer.log('Error expiring order: $e', name: 'PaymentConfirmation');
    }
  }

  /// Pick payment proof image from gallery or camera
  /// Supports both Android and iOS image selection
  Future<void> _pickPaymentProof() async {
    try {
      // Show dialog to choose between camera and gallery
      final ImageSource? source = await showCupertinoModalPopup<ImageSource>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: Text(
            'Select Image Source',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(ImageSource.camera),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.camera, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Camera',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.photo_on_rectangle, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Gallery',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            isDestructiveAction: true,
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                fontSize: 16,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      );

      if (source == null) return; // User cancelled

      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null && mounted) {
        setState(() {
          _paymentProofImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Failed to pick image: $e');
      }
    }
  }

  /// Upload payment proof and submit for verification
  Future<void> _submitPaymentProof() async {
    if (_paymentProofImage == null) {
      Toast.error(context, 'Please upload payment proof');
      return;
    }

    setState(() {
      _uploading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Upload payment proof to backend
      final imageBytes = await _paymentProofImage!.readAsBytes();
      final fileName = _paymentProofImage!.path.split('/').last;
      
      // Upload payment proof image
      final proofUrl = await _db.uploadPaymentProof(
        orderId: widget.orderId,
        imageBytes: imageBytes,
        fileName: fileName,
      );
      
      developer.log('✅ Payment proof uploaded: $proofUrl', name: 'PaymentConfirmation');

      if (mounted) {
        setState(() {
          _uploading = false;
        });
        _stopTimers();
        Toast.success(context, 'Payment proof submitted! Waiting for admin confirmation.');
        
        // Navigate to success screen
        Navigator.of(context).pushAndRemoveUntil(
          CupertinoPageRoute(
            builder: (_) => const SuccessScreen(),
          ),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
        Toast.error(context, 'Failed to submit payment proof: $e');
      }
    }
  }

  /// Format remaining time as MM:SS
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }


  @override
  Widget build(BuildContext context) {
    if (_orderExpired) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: CupertinoNavigationBarBackButton(
            onPressed: () => Navigator.of(context).maybePop(),
            color: const Color(0xFF8D6E63),
          ),
          middle: Text(
            'Order Expired',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    size: 80,
                    color: CupertinoColors.destructiveRed,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Order Expired',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF8D6E63),
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your order expired because payment was not received within ${_settings?.paymentConfirmationTimeMinutes ?? 15} minutes.',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: const Color(0xFF5F5B56),
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can repay this order to continue.',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFFF9800),
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        color: CupertinoColors.systemGrey5,
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Close',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF8D6E63),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        color: const Color(0xFFFF9800),
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () async {
                          // Reset order status to pending
                          try {
                            await _db.updateOrderStatus(widget.orderId, 'pending');
                            if (!mounted) return;
                            final navigator = Navigator.of(context);
                            navigator.pop();
                            // Reload will happen when we return to orders screen
                          } catch (e) {
                            if (!mounted) return;
                            final ctx = context;
                            Toast.error(ctx, 'Failed to reset order: $e');
                          }
                        },
                        child: Text(
                          'Repay Order',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_paymentConfirmed) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: CupertinoNavigationBarBackButton(
            onPressed: () => Navigator.of(context).maybePop(),
            color: const Color(0xFF8D6E63),
          ),
          middle: Text(
            'Payment Confirmed',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    size: 80,
                    color: CupertinoColors.activeGreen,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Payment Confirmed!',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your payment has been confirmed. You will receive an email confirmation shortly.',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  CupertinoButton.filled(
                    onPressed: () {
                      // Check if we can pop before trying to navigate
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      } else {
                        // If we can't pop, navigate to home using root navigator
                        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
                          TabShell.route,
                          (route) => false,
                        );
                      }
                    },
                    child: Text(
                      'Back to Home',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: CupertinoNavigationBarBackButton(
            onPressed: () => Navigator.of(context).maybePop(),
            color: const Color(0xFF8D6E63),
          ),
          middle: Text(
            'Complete Payment',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Timer warning
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _remainingSeconds < 300 // Less than 5 minutes
                    ? const Color(0xFFFFEBEE)
                    : const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _remainingSeconds < 300
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFFFF9800),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.timer,
                    color: _remainingSeconds < 300
                        ? const Color(0xFFD32F2F)
                        : const Color(0xFFFF9800),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Time Remaining',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _remainingSeconds < 300
                                ? const Color(0xFFD32F2F)
                                : const Color(0xFFE65100),
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _remainingSeconds < 300
                              ? '⚠️ ${_formatTime(_remainingSeconds)} - Order will be cancelled soon!'
                              : 'Complete payment within ${_formatTime(_remainingSeconds)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            color: _remainingSeconds < 300
                                ? const Color(0xFFD32F2F)
                                : const Color(0xFFE65100),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Payment amount
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Payment Amount',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₱${widget.paymentAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (widget.paymentMethod == PaymentMethod.cod) ...[
                    const SizedBox(height: 8),
                    Text(
                      '20% Downpayment (COD)',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Text(
                      'Remaining: ₱${(widget.totalAmount - widget.paymentAmount).toStringAsFixed(2)} (Payable on delivery)',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      'Full Payment (GCash)',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // QR Code - Using static image from assets
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: CupertinoColors.separator.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Scan QR Code to Pay',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Display QR code image from assets (configurable path)
                  Image.asset(
                    _settings?.qrCodeImagePath ?? 'assets/images/qrcode.jpg',
                    width: 250,
                    height: 250,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 250,
                      height: 250,
                      color: CupertinoColors.systemGrey5,
                      child: const Icon(CupertinoIcons.qrcode, size: 100),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _settings?.gcashAccountName ?? 'Rosalie M. Enon',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF8D6E63),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'GCash Account: ${_settings?.gcashAccountNumber ?? '09123456789'}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Order Reference: ${widget.orderId.substring(0, 8).toUpperCase()}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: CupertinoColors.systemGrey,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Payment Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.info_circle_fill,
                        color: Color(0xFF1976D2),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Payment Instructions',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1976D2),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InstructionStep(number: '1', text: 'Open your GCash app'),
                  _InstructionStep(number: '2', text: 'Tap "Scan QR" or "Send Money"'),
                  _InstructionStep(number: '3', text: 'Scan the QR code above or send ₱${widget.paymentAmount.toStringAsFixed(2)} to ${_settings?.gcashAccountNumber ?? '09123456789'}'),
                  _InstructionStep(number: '4', text: 'Take a screenshot of your payment confirmation'),
                  _InstructionStep(number: '5', text: 'Upload the screenshot below'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Payment Proof Upload
            Text(
              'Upload Payment Proof',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickPaymentProof,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: CupertinoColors.secondarySystemGroupedBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CupertinoColors.separator.withValues(alpha: 0.3),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
                child: _paymentProofImage == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            CupertinoIcons.photo_on_rectangle,
                            size: 48,
                            color: CupertinoColors.systemGrey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tap to upload payment screenshot',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: CupertinoColors.systemGrey,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          _paymentProofImage!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            CupertinoButton.filled(
              onPressed: _uploading || _paymentProofImage == null
                  ? null
                  : _submitPaymentProof,
              child: _uploading
                  ? const CupertinoActivityIndicator()
                  : Text(
                      'Submit Payment Proof',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              'After submission, your payment will be verified by our team. You will receive an email confirmation once verified.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: CupertinoColors.systemGrey,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF1976D2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: const Color(0xFF1565C0),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

