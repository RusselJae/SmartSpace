import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../models/address_entry.dart';
import '../../models/app_settings.dart';
import '../../models/cart_item.dart';
import '../../services/app_settings_service.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/mysql_database_service.dart';
import '../../services/profile_storage.dart';
import '../../utils/model_path_helper.dart';
import '../../widgets/toast.dart';
import '../views/sign_in.dart';
import 'models.dart';
import 'payment_confirmation_screen.dart';

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
  final AppSettingsService _settingsService = AppSettingsService();
  
  AppSettings? _settings;
  
  // Contact Information
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  // Address Information - Updated to match address screen format
  final TextEditingController _addressLine1Controller = TextEditingController(); // Block and Lot
  final TextEditingController _addressLine2Controller = TextEditingController(); // Street (optional)
  final TextEditingController _postalCodeController = TextEditingController();
  
  // Philippines address cascade dropdowns - matching address screen exactly
  final Map<String, List<String>> _provinceToCities = {};
  final Map<String, List<String>> _cityToBarangays = {};
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedBarangay;
  bool _loadingLocations = true;
  
  // Payment Method
  PaymentMethod _paymentMethod = PaymentMethod.gcash;
  
  bool _loading = false;
  bool _prefilling = true;

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

  /// Calculates shipping fee based on location and product count
  /// 
  /// Uses settings from AppSettingsService for configurable shipping rules
  double _calculateShippingFee() {
    final settings = _settings ?? const AppSettings();
    
    // Free shipping if user bought the configured number of products or more
    if (_checkoutItems.length >= settings.freeShippingProductCount) {
      return 0.0;
    }

    // Get the city from the selected dropdown
    final city = (_selectedCity ?? '').trim().toLowerCase();
    
    // Check for free shipping cities (from settings)
    for (final freeCity in settings.freeShippingCities) {
      if (city.contains(freeCity.toLowerCase())) {
        return 0.0;
      }
    }
    
    // Check for special shipping cities (from settings)
    for (final entry in settings.specialShippingCities.entries) {
      if (city.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    
    // For other locations, calculate based on configured base and max fees
    // Using a simple heuristic: if city name is longer, assume it's further away
    // This is a placeholder - replace with actual distance calculation
    final baseFee = settings.defaultShippingFeeBase;
    final maxFee = settings.defaultShippingFeeMax;
    final distanceMultiplier = (city.length / 10).clamp(0.0, 1.0); // Normalize to 0-1
    final additionalFee = distanceMultiplier * (maxFee - baseFee);
    
    return (baseFee + additionalFee).clamp(baseFee, maxFee);
  }

  /// Calculates downpayment amount based on payment method
  /// 
  /// COD: Configurable downpayment percentage (from settings)
  /// GCash: No downpayment (full payment upfront via GCash)
  double _calculateDownpayment() {
    if (_paymentMethod == PaymentMethod.cod) {
      final settings = _settings ?? const AppSettings();
      // COD requires configurable downpayment percentage via GCash
      final subtotal = _checkoutSubtotal;
      final shipping = _calculateShippingFee();
      final total = subtotal + shipping;
      return total * (settings.codDownpaymentPercentage / 100.0);
    } else {
      // GCash requires full payment upfront, no downpayment
      return 0.0;
    }
  }

  /// Calculates remaining balance after downpayment
  /// 
  /// COD: remaining balance is (100% - downpayment%) of total (paid upon delivery)
  /// GCash: no remaining balance (full payment upfront)
  double _calculateRemainingBalance() {
    final subtotal = _checkoutSubtotal;
    final shipping = _calculateShippingFee();
    final total = subtotal + shipping;
    
    if (_paymentMethod == PaymentMethod.cod) {
      final settings = _settings ?? const AppSettings();
      // For COD, remaining balance is (100% - downpayment%) of total
      final downpaymentPercentage = settings.codDownpaymentPercentage / 100.0;
      return total * (1.0 - downpaymentPercentage);
    } else {
      // For GCash, full payment is made upfront, no remaining balance
      return 0.0;
    }
  }

  /// Gets the payment amount required upfront
  /// 
  /// COD: 20% downpayment
  /// GCash: Full amount
  double _getUpfrontPaymentAmount() {
    if (_paymentMethod == PaymentMethod.cod) {
      return _calculateDownpayment();
    } else {
      final subtotal = _checkoutSubtotal;
      final shipping = _calculateShippingFee();
      return subtotal + shipping;
    }
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
    _loadSettings();
    _loadPhilippinesLocationData();
    _hydrateForm();
  }
  
  /// Load application settings for shipping and payment calculations
  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.loadSettings();
      if (mounted) {
        setState(() {
          _settings = settings;
        });
      }
    } catch (e) {
      // If settings fail to load, use default settings
      if (mounted) {
        setState(() {
          _settings = const AppSettings();
        });
      }
    }
  }
  
  /// Load Philippines address data from JSON asset - matching address screen exactly
  Future<void> _loadPhilippinesLocationData() async {
    try {
      final raw = await rootBundle.loadString('assets/philippines_addresses_sample.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;

      final Map<String, List<String>> provinceToCities = {};
      final Map<String, List<String>> cityToBarangays = {};

      decoded.forEach((province, citiesRaw) {
        if (citiesRaw is Map<String, dynamic>) {
          final cityNames = <String>[];
          citiesRaw.forEach((cityName, barangaysRaw) {
            cityNames.add(cityName);
            if (barangaysRaw is List) {
              cityToBarangays[cityName] =
                  barangaysRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
            }
          });
          if (cityNames.isNotEmpty) {
            provinceToCities[province] = cityNames;
          }
        }
      });

      setState(() {
        _provinceToCities.clear();
        _provinceToCities.addAll(provinceToCities);
        _cityToBarangays.clear();
        _cityToBarangays.addAll(cityToBarangays);
        _loadingLocations = false;
      });
    } catch (e) {
      setState(() {
        _loadingLocations = false;
      });
    }
  }

  /// Opens the address editor modal matching the exact design from addresses screen
  void _openAddressEditor() {
    // Create a temporary AddressEntry from current form data for editing
    // Note: The address editor uses "street" field which combines block/lot and street
    // We'll combine them for the editor, then split them back when updating
    final combinedStreet = [
      _addressLine1Controller.text.trim(),
      if (_addressLine2Controller.text.trim().isNotEmpty) _addressLine2Controller.text.trim(),
    ].join(', ');
    
    final currentEntry = AddressEntry(
      id: '',
      fullName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      region: [
        _selectedProvince,
        _selectedCity,
        _selectedBarangay,
      ].whereType<String>().join(', '),
      postalCode: _postalCodeController.text.trim(),
      street: combinedStreet,
      label: 'Home', // Default label
      isDefault: false,
    );

    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _AddressEditorSheet(
        entry: currentEntry,
        onSubmit: (updatedEntry) {
          // Update all form fields from the edited entry
          setState(() {
            _nameController.text = updatedEntry.fullName;
            _phoneController.text = updatedEntry.phoneNumber;
            _postalCodeController.text = updatedEntry.postalCode;
            
            // Split the street field back into block/lot and street
            // The street field from editor contains "Block and Lot, Street"
            final streetParts = updatedEntry.street.split(',').map((p) => p.trim()).toList();
            if (streetParts.isNotEmpty) {
              _addressLine1Controller.text = streetParts[0];
              if (streetParts.length > 1) {
                _addressLine2Controller.text = streetParts.sublist(1).join(', ');
              } else {
                _addressLine2Controller.text = '';
              }
            } else {
              _addressLine1Controller.text = updatedEntry.street;
              _addressLine2Controller.text = '';
            }
            
            // Parse region to extract province, city, barangay
            final regionParts = updatedEntry.region.split(',').map((p) => p.trim()).toList();
            if (regionParts.isNotEmpty && _provinceToCities.containsKey(regionParts[0])) {
              _selectedProvince = regionParts[0];
              if (regionParts.length > 1 && _provinceToCities[_selectedProvince]!.contains(regionParts[1])) {
                _selectedCity = regionParts[1];
                if (regionParts.length > 2 && _cityToBarangays[_selectedCity]?.contains(regionParts[2]) == true) {
                  _selectedBarangay = regionParts[2];
                } else {
                  _selectedBarangay = null;
                }
              } else {
                _selectedCity = null;
                _selectedBarangay = null;
              }
            } else {
              _selectedProvince = null;
              _selectedCity = null;
              _selectedBarangay = null;
            }
          });
        },
      ),
    );
  }

  Future<void> _hydrateForm() async {
    // Set prefilling state for loading indicator
    setState(() {
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
        // Parse the region string to extract province, city, barangay
        final regionParts = defaultAddress.region.split(',').map((p) => p.trim()).toList();
        if (regionParts.isNotEmpty && _provinceToCities.containsKey(regionParts[0])) {
          _selectedProvince = regionParts[0];
          if (regionParts.length > 1 && _provinceToCities[_selectedProvince]!.contains(regionParts[1])) {
            _selectedCity = regionParts[1];
            if (regionParts.length > 2 && _cityToBarangays[_selectedCity]?.contains(regionParts[2]) == true) {
              _selectedBarangay = regionParts[2];
            }
          }
        }
        // Split street field into block/lot and street if it contains a comma
        final streetParts = defaultAddress.street.split(',').map((p) => p.trim()).toList();
        if (streetParts.isNotEmpty) {
          _addressLine1Controller.text = streetParts[0];
          if (streetParts.length > 1) {
            _addressLine2Controller.text = streetParts.sublist(1).join(', ');
          }
        } else {
          _addressLine1Controller.text = defaultAddress.street;
        }
        _postalCodeController.text = defaultAddress.postalCode;
      } else if (user.addresses.isNotEmpty) {
        // Legacy fallback where addresses were kept as a raw string list.
        final legacy = user.addresses.first;
        final parts = legacy.split(', ');
        _addressLine1Controller.text = parts.isNotEmpty ? parts.first : legacy;
        if (parts.length > 2) {
          _postalCodeController.text = parts[2];
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _prefilling = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  void _placeOrder() {
    setState(() {
      _loading = true;
    });
    final checkoutItems = _checkoutItems;

    // Validate required fields - using toast messages instead of error banner
    if (_nameController.text.trim().isEmpty) {
      setState(() => _loading = false);
      Toast.warning(context, 'Please enter your full name');
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      setState(() => _loading = false);
      Toast.warning(context, 'Please enter your phone number');
      return;
    }

    if (_addressLine1Controller.text.trim().isEmpty) {
      setState(() => _loading = false);
      Toast.warning(context, 'Please enter block and lot');
      return;
    }

    if (_selectedProvince == null) {
      setState(() => _loading = false);
      Toast.warning(context, 'Please select a province');
      return;
    }

    if (_selectedCity == null) {
      setState(() => _loading = false);
      Toast.warning(context, 'Please select a city');
      return;
    }

    if (_selectedBarangay == null) {
      setState(() => _loading = false);
      Toast.warning(context, 'Please select a barangay');
      return;
    }

    if (_postalCodeController.text.trim().isEmpty) {
      setState(() => _loading = false);
      Toast.warning(context, 'Please enter postal code');
      return;
    }

    if (checkoutItems.isEmpty) {
      setState(() => _loading = false);
      Toast.warning(context, 'No products selected');
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      Toast.error(context, 'Please sign in to place your order');
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
        setState(() => _loading = false);
        Toast.error(context, 'Please sign in to place your order');
        return;
      }

      final subtotal = _checkoutSubtotal;
      final shipping = _calculateShippingFee();
      final total = subtotal + shipping;
      final downpayment = _calculateDownpayment();
      final remainingBalance = _calculateRemainingBalance();
      
      // Convert payment method to string for backend
      final paymentMethodString = _paymentMethod == PaymentMethod.gcash ? 'gcash' : 'cod';
      
      // Build merged address line 1 (Block & Lot + Street)
      final mergedLine1 = [
        _addressLine1Controller.text.trim(),
        if (_addressLine2Controller.text.trim().isNotEmpty) _addressLine2Controller.text.trim(),
      ].join(', ');
      
      // Build region string from selected dropdowns
      final region = [
        _selectedProvince,
        _selectedCity,
        _selectedBarangay,
      ].whereType<String>().join(', ');
      
      final shippingAddress = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'line1': mergedLine1,
        'city': _selectedCity ?? '',
        'region': region,
        'postalCode': _postalCodeController.text.trim(),
        'shippingFee': shipping, // Pass shipping fee to backend for accurate record keeping
        'paymentMethod': paymentMethodString, // Pass payment method to backend
        'downpayment': downpayment, // Pass downpayment amount for GCash orders
        'remainingBalance': remainingBalance, // Pass remaining balance for GCash orders
      };

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
      
      // Redirect to payment confirmation screen for both COD and GCash
      // COD needs 20% downpayment, GCash needs full payment
      Navigator.of(context).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (_) => PaymentConfirmationScreen(
            orderId: order.id,
            paymentAmount: _getUpfrontPaymentAmount(),
            paymentMethod: _paymentMethod,
            totalAmount: total,
            orderCreatedAt: order.createdAt,
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // Use toast message instead of error banner
      Toast.error(context, 'Failed to place order: ${e.toString()}');
      // Log error for debugging (using developer.log to avoid avoid_print lint)
      developer.log('Order creation error: $e', name: 'OrderSummary');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _checkoutItems;
    final subtotal = _checkoutSubtotal;
    final shipping = _calculateShippingFee();
    final total = subtotal + shipping;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: const Color(0xFF8D6E63),
        ),
        middle: Text(
          'Order Summary',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      child: SafeArea(
        child: _prefilling || _loadingLocations
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Product Information Section at the top with images
            Text(
              'Products',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 12),
            ...items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Static 3D model preview image
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey5,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: ModelViewer(
                      backgroundColor: const Color(0xFFEFEFEF),
                      src: ModelPathHelper.normalize(item.product.modelPath),
                      alt: '3D preview of ${item.product.name}',
                      ar: false,
                      autoRotate: false,
                      cameraControls: false,
                      disableZoom: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Product details
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
                        const SizedBox(height: 4),
                        Text(
                          '₱${item.subtotal.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF8D6E63),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 20),

            // Contact and Address Card - Read-only with Edit option
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF8D6E63).withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with Edit button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Contact & Address',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6D4C41),
                          decoration: TextDecoration.none,
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: _openAddressEditor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8D6E63),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                CupertinoIcons.pencil,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Edit',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Contact Information
                  _InfoRow(
                    label: 'Full Name',
                    value: _nameController.text.isEmpty ? 'Not provided' : _nameController.text,
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Phone Number',
                    value: _phoneController.text.isEmpty ? 'Not provided' : _phoneController.text,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFE0E0E0)),
                  const SizedBox(height: 16),
                  // Address Information - Displayed in descending order: Province, City, Barangay, Block and Lot, Street, Postal Code
                  _InfoRow(
                    label: 'Province',
                    value: _selectedProvince ?? 'Not selected',
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'City',
                    value: _selectedCity ?? 'Not selected',
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Barangay',
                    value: _selectedBarangay ?? 'Not selected',
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Block and Lot',
                    value: _addressLine1Controller.text.isEmpty ? 'Not provided' : _addressLine1Controller.text,
                  ),
                  if (_addressLine2Controller.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'Street',
                      value: _addressLine2Controller.text,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Postal Code',
                    value: _postalCodeController.text.isEmpty ? 'Not provided' : _postalCodeController.text,
                  ),
                ],
              ),
            ),
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
            const SizedBox(height: 12),
            // Payment Method Selection with Label
            Text(
              'Select Payment Method',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            _PaymentPill(
              label: 'GCash (Online)',
              selected: _paymentMethod == PaymentMethod.gcash,
              onTap: () => setState(() => _paymentMethod = PaymentMethod.gcash),
            ),
            const SizedBox(height: 8),
            _PaymentPill(
              label: 'Cash on Delivery (COD)',
              selected: _paymentMethod == PaymentMethod.cod,
              onTap: () => setState(() => _paymentMethod = PaymentMethod.cod),
            ),
            const SizedBox(height: 20),

            // Payment Method Notice
            if (_paymentMethod == PaymentMethod.cod) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.info_circle_fill,
                      color: Color(0xFFFF9800),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'COD: Downpayment Required',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFE65100),
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'A 20% downpayment via GCash is required to confirm your order. The remaining balance will be collected upon delivery.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                              color: const Color(0xFFE65100),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (_paymentMethod == PaymentMethod.gcash) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: Color(0xFF4CAF50),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GCash: Full Payment Upfront',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2E7D32),
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Full payment is required via GCash to confirm your order. No additional payment upon delivery.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                              color: const Color(0xFF2E7D32),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

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
                    'Order Summary',
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
                    isTotal: false,
                  ),
                  // Show downpayment and remaining balance for COD
                  if (_paymentMethod == PaymentMethod.cod) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 24),
                    _TotalRow(
                      label: 'Downpayment (${(_settings?.codDownpaymentPercentage ?? 20.0).toStringAsFixed(0)}%)',
                      value: '₱${_calculateDownpayment().toStringAsFixed(2)}',
                      isHighlighted: true,
                    ),
                    const SizedBox(height: 6),
                    _TotalRow(
                      label: 'Remaining Balance',
                      value: '₱${_calculateRemainingBalance().toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Payable upon delivery',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: CupertinoColors.systemGrey,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Place Order Button - simplified to just "Place Order"
            CupertinoButton.filled(
              onPressed: _loading ? null : _placeOrder,
              child: _loading
                  ? const CupertinoActivityIndicator()
                  : Text(
                      'Place Order',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
            ),
            // Additional info based on payment method
            const SizedBox(height: 8),
            Text(
              _paymentMethod == PaymentMethod.cod
                  ? 'After placing your order, you will be redirected to pay the 20% downpayment via GCash. The remaining balance will be collected upon delivery.'
                  : 'After placing your order, you will be redirected to complete full payment via GCash. No additional payment upon delivery.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: CupertinoColors.systemGrey,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
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
      // Improved inactive color - lighter beige with better contrast
      // Active: rich brown, Inactive: light beige background with brown border
      color: selected ? const Color(0xFF8D6E63) : const Color(0xFFF4E6D4),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF8D6E63),
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

/// Info row widget for displaying read-only contact and address information
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF6D4C41).withValues(alpha: 0.7),
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.normal,
              color: const Color(0xFF6D4C41),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// Address editor modal sheet matching the exact design from addresses screen
class _AddressEditorSheet extends StatefulWidget {
  const _AddressEditorSheet({this.entry, required this.onSubmit});
  final AddressEntry? entry;
  final ValueChanged<AddressEntry> onSubmit;

  @override
  State<_AddressEditorSheet> createState() => _AddressEditorSheetState();
}

class _AddressEditorSheetState extends State<_AddressEditorSheet> {
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _postal = TextEditingController();
  final TextEditingController _street = TextEditingController();
  String _label = 'Home';

  // Cascading PH address selection state
  final Map<String, List<String>> _provinceToCities = {};
  final Map<String, List<String>> _cityToBarangays = {};

  List<String> _allProvinces = [];
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedBarangay;

  bool _loadingLocations = true;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadPhilippinesLocationData();
    final entry = widget.entry;
    if (entry != null) {
      _fullName.text = entry.fullName;
      _phone.text = entry.phoneNumber;
      _postal.text = entry.postalCode;
      _street.text = entry.street;
      _label = entry.label;
    }
  }

  Future<void> _loadPhilippinesLocationData() async {
    try {
      final raw = await rootBundle.loadString('assets/philippines_addresses_sample.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;

      final Map<String, List<String>> provinceToCities = {};
      final Map<String, List<String>> cityToBarangays = {};

      decoded.forEach((province, citiesRaw) {
        if (citiesRaw is Map<String, dynamic>) {
          final cityNames = <String>[];
          citiesRaw.forEach((cityName, barangaysRaw) {
            cityNames.add(cityName);
            if (barangaysRaw is List) {
              cityToBarangays[cityName] =
                  barangaysRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
            }
          });
          if (cityNames.isNotEmpty) {
            provinceToCities[province] = cityNames;
          }
        }
      });

      // Try to hydrate selection from the existing `region` string
      final existing = widget.entry?.region ?? '';
      String? province;
      String? city;
      String? barangay;
      if (existing.trim().isNotEmpty) {
        final parts = existing.split(',').map((p) => p.trim()).toList();
        if (parts.isNotEmpty) province = parts[0];
        if (parts.length > 1) city = parts[1];
        if (parts.length > 2) barangay = parts[2];
      }

      setState(() {
        _provinceToCities.clear();
        _provinceToCities.addAll(provinceToCities);
        _cityToBarangays.clear();
        _cityToBarangays.addAll(cityToBarangays);
        _allProvinces = _provinceToCities.keys.toList()..sort();

        if (province != null && _provinceToCities.containsKey(province)) {
          _selectedProvince = province;
          if (city != null && _provinceToCities[province]!.contains(city)) {
            _selectedCity = city;
            if (barangay != null && _cityToBarangays[city]?.contains(barangay) == true) {
              _selectedBarangay = barangay;
            }
          }
        }

        _loadingLocations = false;
      });
    } catch (_) {
      setState(() {
        _loadingLocations = false;
      });
    }
  }

  bool get _hasValidationError {
    return _submitted &&
        (_fullName.text.trim().isEmpty ||
            _phone.text.trim().isEmpty ||
            _selectedProvince == null ||
            _selectedCity == null ||
            _selectedBarangay == null ||
            _street.text.trim().isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF6D4C41).withValues(alpha: 0.5),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.entry == null ? 'Add Address' : 'Edit Address',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                _buildSmallField('Full Name *', _fullName, showError: _submitted && _fullName.text.trim().isEmpty),
                _buildSmallField('Phone Number *', _phone,
                    keyboard: TextInputType.phone,
                    showError: _submitted && _phone.text.trim().isEmpty),
                const SizedBox(height: 4),
                Text('Address (Philippines)', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                if (_loadingLocations)
                  const Center(child: CupertinoActivityIndicator())
                else ...[
                  _DropdownFieldCompact(
                    label: 'Province *',
                    value: _selectedProvince,
                    options: _allProvinces,
                    showError: _submitted && _selectedProvince == null,
                    onChanged: (value) {
                      setState(() {
                        _selectedProvince = value;
                        _selectedCity = null;
                        _selectedBarangay = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  _DropdownFieldCompact(
                    label: 'City / Municipality *',
                    value: _selectedCity,
                    options: _selectedProvince == null
                        ? const []
                        : (_provinceToCities[_selectedProvince] ?? const []),
                    showError: _submitted && _selectedCity == null,
                    onChanged: (value) {
                      setState(() {
                        _selectedCity = value;
                        _selectedBarangay = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  _DropdownFieldCompact(
                    label: 'Barangay *',
                    value: _selectedBarangay,
                    options: _selectedCity == null
                        ? const []
                        : (_cityToBarangays[_selectedCity] ?? const []),
                    showError: _submitted && _selectedBarangay == null,
                    onChanged: (value) {
                      setState(() {
                        _selectedBarangay = value;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 10),
                _buildSmallField(
                  'Postal Code',
                  _postal,
                  keyboard: TextInputType.number,
                ),
                _buildSmallField(
                  'Street / Building / House No. *',
                  _street,
                  showError: _submitted && _street.text.trim().isEmpty,
                ),
                const SizedBox(height: 12),
                Text('Label As', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['Home', 'Work', 'Other'].map((label) {
                    final selected = _label == label;
                    return ChoiceChip(
                      label: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
                      selected: selected,
                      onSelected: (_) => setState(() => _label = label),
                      selectedColor: const Color(0xFF8D6E63),
                      labelStyle:
                          GoogleFonts.poppins(color: selected ? Colors.white : const Color(0xFF6D4C41), fontSize: 12),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: const Color(0xFFF4E6D4),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF8D6E63),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        color: const Color(0xFF8D6E63),
                        onPressed: () {
                          setState(() {
                            _submitted = true;
                          });
                          if (_hasValidationError) return;

                          final region = [
                            _selectedProvince,
                            _selectedCity,
                            _selectedBarangay,
                          ].whereType<String>().join(', ');

                          widget.onSubmit(
                            AddressEntry(
                              id: widget.entry?.id ?? '',
                              fullName: _fullName.text.trim(),
                              phoneNumber: _phone.text.trim(),
                              region: region,
                              postalCode: _postal.text.trim(),
                              street: _street.text.trim(),
                              label: _label,
                              isDefault: widget.entry?.isDefault ?? false,
                            ),
                          );
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          'Submit',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
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

  Widget _buildSmallField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
    bool showError = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: showError ? CupertinoColors.systemRed : const Color(0xFF6D4C41),
            ),
          ),
          const SizedBox(height: 4),
          CupertinoTextField(
            controller: controller,
            keyboardType: keyboard,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: CupertinoColors.separator),
            ),
            style: GoogleFonts.poppins(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Compact dropdown field matching addresses screen exactly
class _DropdownFieldCompact extends StatelessWidget {
  const _DropdownFieldCompact({
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
    this.showError = false,
  });

  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: options.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: showError ? CupertinoColors.systemRed : const Color(0xFF6D4C41),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        filled: true,
        fillColor: CupertinoColors.secondarySystemGroupedBackground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CupertinoColors.separator),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CupertinoColors.separator),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: showError ? CupertinoColors.systemRed : const Color(0xFF8D6E63),
            width: 1.4,
          ),
        ),
        errorText: showError ? 'Required' : null,
      ),
      icon: const Icon(CupertinoIcons.chevron_down, size: 16, color: CupertinoColors.systemGrey),
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(
                option,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: const Color(0xFF6D4C41),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: options.isEmpty ? null : onChanged,
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.isHighlighted = false,
  });
  final String label;
  final String value;
  final bool isTotal;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isHighlighted ? const Color(0xFF1976D2) : Colors.black,
            fontSize: isTotal ? 18 : (isHighlighted ? 16 : 16),
            fontWeight: isTotal
                ? FontWeight.w700
                : (isHighlighted ? FontWeight.w600 : FontWeight.normal),
            decoration: TextDecoration.none,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: isHighlighted ? const Color(0xFF1976D2) : Colors.black,
            fontSize: isTotal ? 18 : (isHighlighted ? 16 : 16),
            fontWeight: isTotal
                ? FontWeight.w700
                : (isHighlighted ? FontWeight.w600 : FontWeight.normal),
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}


