import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/address_entry.dart';
import '../../models/cart_item.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/mysql_database_service.dart';
import '../../services/profile_storage.dart';
import '../../widgets/toast.dart';
import '../views/sign_in.dart';
import 'models.dart';
import 'success_screen.dart';

/// Unified Order Summary page with all editable fields
class OrderSummaryScreen extends StatefulWidget {
  const OrderSummaryScreen({super.key, this.productIds});

  final List<String>? productIds;

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> {
  final CartService _cart = CartService();
  final AuthService _auth = AuthService();
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final ProfileStorage _storage = ProfileStorage();
  
  // Contact Information
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  // Address Information
  final TextEditingController _addressLine1Controller = TextEditingController();
  final TextEditingController _addressLine2Controller = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  
  // Payment Method
  PaymentMethod _paymentMethod = PaymentMethod.card;
  final TextEditingController _cardHolderController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  
  String? _error;
  bool _loading = false;
  bool _prefilling = true;
  AddressEntry? _defaultAddress;

  List<CartItem> get _checkoutItems {
    final ids = widget.productIds;
    final items = _cart.items;
    if (ids == null || ids.isEmpty) {
      return items;
    }
    final selected = ids.toSet();
    return items.where((item) => selected.contains(item.product.id)).toList();
  }

  double get _checkoutSubtotal {
    return _checkoutItems.fold<double>(0.0, (sum, item) => sum + item.subtotal);
  }

  @override
  void initState() {
    super.initState();
    // Check authentication before initializing
    if (!_auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Navigate to sign in screen as fullscreen dialog to hide navigation bar
          Navigator.of(context, rootNavigator: true).pushReplacement(
            CupertinoPageRoute(
              builder: (_) => const SignInScreen(),
              fullscreenDialog: true,
            ),
          );
        }
      });
      return;
    }
    _hydrateForm();
  }

  Future<void> _hydrateForm() async {
    // Clear error states so the shimmer/loader feels native.
    setState(() {
      _error = null;
      _prefilling = true;
    });

    final user = _auth.currentUser;
    AddressEntry? defaultAddress;

    if (user != null) {
      // Pull base info from the signed-in user profile.
      _nameController.text = user.fullName;
      if (user.phoneNumber?.isNotEmpty ?? false) {
        _phoneController.text = user.phoneNumber!;
      }

      // Pull the richer address objects that live inside the profile storage.
      final savedAddresses = await _storage.loadAddresses(user.id);
      if (savedAddresses.isNotEmpty) {
        // Always surface the default address; if the user somehow deleted the flag
        // we gracefully fall back to the first entry.
        defaultAddress = savedAddresses.firstWhere(
          (entry) => entry.isDefault,
          orElse: () => savedAddresses.first,
        );

        // Mirror the saved info to the editable form fields.
        if (defaultAddress.fullName.trim().isNotEmpty) {
          _nameController.text = defaultAddress.fullName;
        }
        if (defaultAddress.phoneNumber.trim().isNotEmpty) {
          _phoneController.text = defaultAddress.phoneNumber;
        }
        _addressLine1Controller.text = defaultAddress.street;
        _cityController.text = defaultAddress.region;
        _postalCodeController.text = defaultAddress.postalCode;
        _addressLine2Controller.text = '';
      } else if (user.addresses.isNotEmpty) {
        // Legacy fallback where addresses were kept as a raw string list.
        final legacy = user.addresses.first;
        final parts = legacy.split(', ');
        _addressLine1Controller.text = parts.isNotEmpty ? parts.first : legacy;
        if (parts.length > 1) {
          _cityController.text = parts[1];
        }
        if (parts.length > 2) {
          _postalCodeController.text = parts[2];
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _defaultAddress = defaultAddress;
      _prefilling = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _cardHolderController.dispose();
    _cardNumberController.dispose();
    super.dispose();
  }

  void _placeOrder() {
    setState(() {
      _error = null;
      _loading = true;
    });
    final checkoutItems = _checkoutItems;

    // Validate required fields
    if (_nameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _addressLine1Controller.text.isEmpty ||
        _cityController.text.isEmpty ||
        _postalCodeController.text.isEmpty) {
      setState(() {
        _error = 'Please fill in all required fields';
        _loading = false;
      });
      return;
    }

    if (checkoutItems.isEmpty) {
      setState(() {
        _error = 'No products selected';
        _loading = false;
      });
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Please sign in to place your order';
        _loading = false;
      });
      return;
    }

    _placeOrderAsync();
  }

  Future<void> _placeOrderAsync() async {
    try {
      final checkoutItems = _checkoutItems;
      final user = _auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Please sign in to place your order';
          _loading = false;
        });
        return;
      }

      final shippingAddress = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'line1': _addressLine1Controller.text.trim(),
        'line2': _addressLine2Controller.text.trim(),
        'city': _cityController.text.trim(),
        'postalCode': _postalCodeController.text.trim(),
      };
      final subtotal = _checkoutSubtotal;
      final shipping = 20.0;
      final total = subtotal + shipping;

      final order = await _db.createOrder(
        userId: user.id,
        userName: user.fullName,
        productIds: checkoutItems.map((item) => item.product.id).toList(),
        totalAmount: total,
        shippingAddress: shippingAddress,
        status: 'pending',
      );

      final updatedOrders = [...user.orderIds];
      if (!updatedOrders.contains(order.id)) {
        updatedOrders.add(order.id);
      }
      final updatedUser = user.copyWith(orderIds: updatedOrders);
      await _auth.updateCurrentUser(updatedUser);

      if (widget.productIds == null) {
        _cart.clear();
      } else {
        for (final id in widget.productIds!) {
          _cart.remove(id);
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      Toast.success(context, 'Order placed successfully!');
      Navigator.of(context).pushAndRemoveUntil(
        CupertinoPageRoute(builder: (_) => const SuccessScreen()),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to place order: ${e.toString()}';
        _loading = false;
      });
      // Log error for debugging (using developer.log to avoid avoid_print lint)
      developer.log('Order creation error: $e', name: 'OrderSummary');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _checkoutItems;
    final subtotal = _checkoutSubtotal;
    final shipping = 20.0;
    final total = subtotal + shipping;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          'Order Summary',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      child: SafeArea(
        child: _prefilling
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryCard(
              icon: CupertinoIcons.person_solid,
              title: 'Contact',
              subtitle: 'These details came straight from your profile.',
              lines: [
                _nameController.text.isEmpty ? 'Name missing' : _nameController.text,
                _phoneController.text.isEmpty ? 'Phone missing' : _phoneController.text,
              ],
            ),
            const SizedBox(height: 12),
            _SummaryCard(
              icon: CupertinoIcons.location_solid,
              title: 'Shipping',
              subtitle: _defaultAddress == null
                  ? 'No default address yet—add one below to speed up checkout.'
                  : 'Default address synced from My Addresses.',
              lines: _defaultAddress == null
                  ? [
                      _addressLine1Controller.text.isEmpty
                          ? 'Address missing'
                          : _addressLine1Controller.text,
                      [
                        _cityController.text,
                        _postalCodeController.text,
                      ].where((line) => line.trim().isNotEmpty).join(' • '),
                    ]
                  : [
                      '${_defaultAddress!.label} • ${_defaultAddress!.fullName}',
                      _defaultAddress!.street,
                      '${_defaultAddress!.region} ${_defaultAddress!.postalCode}'
                          .trim(),
                    ],
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x1FFF3B30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.poppins(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Contact Information Section
            Text(
              'Contact Information',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            _CupertinoField(
              controller: _nameController,
              placeholder: 'Full name *',
            ),
            const SizedBox(height: 12),
            _CupertinoField(
              controller: _phoneController,
              placeholder: 'Phone number *',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),

            // Address Section
            Text(
              'Address',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            _CupertinoField(
              controller: _addressLine1Controller,
              placeholder: 'Address line 1 *',
            ),
            const SizedBox(height: 12),
            _CupertinoField(
              controller: _addressLine2Controller,
              placeholder: 'Address line 2 (optional)',
            ),
            const SizedBox(height: 12),
            _CupertinoField(
              controller: _cityController,
              placeholder: 'City *',
            ),
            const SizedBox(height: 12),
            _CupertinoField(
              controller: _postalCodeController,
              placeholder: 'Postal code *',
            ),
            const SizedBox(height: 20),

            // Products Section
            Text(
              'Products',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            ...items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.product.name,
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Qty: ${item.quantity} × ₱${item.unitPrice.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₱${item.subtotal.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 20),

            // Payment Method Section
            Text(
              'Payment Method',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            _PaymentPill(
              label: 'Credit/Debit Card',
              selected: _paymentMethod == PaymentMethod.card,
              onTap: () => setState(() => _paymentMethod = PaymentMethod.card),
            ),
            const SizedBox(height: 8),
            _PaymentPill(
              label: 'PayPal',
              selected: _paymentMethod == PaymentMethod.paypal,
              onTap: () => setState(() => _paymentMethod = PaymentMethod.paypal),
            ),
            const SizedBox(height: 8),
            _PaymentPill(
              label: 'Cash on Delivery',
              selected: _paymentMethod == PaymentMethod.cod,
              onTap: () => setState(() => _paymentMethod = PaymentMethod.cod),
            ),
            if (_paymentMethod == PaymentMethod.card) ...[
              const SizedBox(height: 12),
              _CupertinoField(
                controller: _cardHolderController,
                placeholder: 'Cardholder name',
              ),
              const SizedBox(height: 12),
              _CupertinoField(
                controller: _cardNumberController,
                placeholder: 'Card number',
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: 20),

            // Order Total Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order Total',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TotalRow(label: 'Subtotal', value: '₱${subtotal.toStringAsFixed(2)}'),
                  const SizedBox(height: 6),
                  _TotalRow(label: 'Shipping', value: '₱${shipping.toStringAsFixed(2)}'),
                  const Divider(height: 24),
                  _TotalRow(
                    label: 'Total',
                    value: '₱${total.toStringAsFixed(2)}',
                    isTotal: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Place Order Button
            CupertinoButton.filled(
              onPressed: _loading ? null : _placeOrder,
              child: _loading
                  ? const CupertinoActivityIndicator()
                  : Text(
                      'Place Order',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CupertinoField extends StatelessWidget {
  const _CupertinoField({
    required this.controller,
    required this.placeholder,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CupertinoColors.separator.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        placeholderStyle: GoogleFonts.poppins(
          color: CupertinoColors.placeholderText,
          fontSize: 15,
          decoration: TextDecoration.none,
        ),
        style: GoogleFonts.poppins(
          color: const Color(0xFF6D4C41),
          fontSize: 15,
          decoration: TextDecoration.none,
        ),
        keyboardType: keyboardType,
        decoration: null,
      ),
    );
  }
}

class _PaymentPill extends StatelessWidget {
  const _PaymentPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // Light brown when inactive, normal brown when active
      color: selected ? const Color(0xFF8D6E63) : const Color(0xFFBCAAA4),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black,
              decoration: TextDecoration.none,
            ),
          ),
          if (selected)
            const Icon(CupertinoIcons.check_mark, color: Colors.white),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.isTotal = false});
  final String label;
  final String value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontSize: isTotal ? 18 : 16,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.normal,
            decoration: TextDecoration.none,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontSize: isTotal ? 18 : 16,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.normal,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

/// Glassy status card that mirrors Apple HIG summary tiles so shoppers can scan
/// their contact + shipping data before touching the form.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CupertinoColors.separator.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 25,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFEBE9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF8D6E63)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6D4C41),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...lines.where((line) => line.trim().isNotEmpty).map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: const Color(0xFF8D6E63),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

