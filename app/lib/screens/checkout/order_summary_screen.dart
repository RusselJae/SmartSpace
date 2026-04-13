import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/address_entry.dart';
import '../../models/app_settings.dart';
import '../../models/cart_item.dart';
import '../../services/app_settings_service.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/mysql_database_service.dart';
import '../../services/profile_storage.dart';
import '../../utils/model_path_helper.dart';
import '../../utils/phone_input_formatters.dart';
import '../../widgets/cached_model_src_loader.dart';
import '../../widgets/toast.dart';
import '../views/sign_in.dart';
import 'models.dart';
import 'success_screen.dart';

// ---------------------------------------------------------------------------
// Walnut-forward palette (warm wood tone — Apple HIG: legible contrast, calm CTAs).
// ---------------------------------------------------------------------------
const Color _kWalnut = Color(0xFF5C4033);
const Color _kWalnutDeep = Color(0xFF3E2723);
const Color _kWalnutSoftBg = Color(0xFFEFE8E3);

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

  double get _layawayDownMin => (_settings ?? const AppSettings()).layawayDownpaymentMin;
  double get _layawayDownMax => (_settings ?? const AppSettings()).layawayDownpaymentMax;
  double get _huluganDownPercent => (_settings ?? const AppSettings()).huluganDownpaymentPercent;
  double get _huluganInterestPercent => (_settings ?? const AppSettings()).huluganInterestPercent;
  int get _policyTermMonths => (_settings ?? const AppSettings()).installmentTermMonths;
  double get _policyLateFeePerDay => (_settings ?? const AppSettings()).lateFeePerDay;
  
  // Contact Information
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _downPaymentInputController = TextEditingController(text: '3500');
  
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
  
  /// PayMongo-only: full pay vs split (down payment path).
  CheckoutPaymentPlan _paymentPlan = CheckoutPaymentPlan.full;

  /// Lay-away vs Hulugan — only when [_paymentPlan] is [CheckoutPaymentPlan.downpayment].
  CheckoutOrderOption _orderOption = CheckoutOrderOption.layaway;

  /// User-chosen down payment (₱3k–₱5k, capped by order total). **Lay-away only.**
  double _downPaymentPesos = 3500;

  /// One government ID — required before checkout.
  XFile? _validIdXFile;

  final ImagePicker _imagePicker = ImagePicker();

  bool _loading = false;
  bool _prefilling = true;
  List<AddressEntry> _savedAddresses = [];
  String? _selectedAddressId;

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

  /// Merchandise + shipping (no 6% hulugan interest).
  double _baseOrderTotal() {
    return _checkoutSubtotal + _calculateShippingFee();
  }

  /// Lay-away path needs order total ≥ configured minimum down payment.
  bool get _canOfferLayawaySplit => _baseOrderTotal() >= _layawayDownMin;

  /// Hulugan: in-stock SKUs only (inventory policy).
  bool get _allItemsEligibleForHulugan {
    return _checkoutItems.every((i) => i.product.inStock && i.product.inventoryQty > 0);
  }

  bool get _canOfferHuluganSplit => _allItemsEligibleForHulugan && _baseOrderTotal() > 0;

  /// User may pick “split pay” if at least one sub-option is valid.
  bool get _canUseAnySplitPlan => _canOfferLayawaySplit || _canOfferHuluganSplit;

  /// Configured hulugan down-payment percent of base (subtotal + shipping).
  double _huluganDownPaymentPesos() => _baseOrderTotal() * (_huluganDownPercent / 100);

  /// Principal after 40% DP (before 6% add-on).
  double _huluganFinancedPrincipal() => _baseOrderTotal() - _huluganDownPaymentPesos();

  /// Configured interest on financed principal.
  double _huluganInterestPesos() => _huluganFinancedPrincipal() * (_huluganInterestPercent / 100);

  /// Full amount customer pays on hulugan (base + interest on financed portion).
  double _huluganGrandTotalPayable() => _baseOrderTotal() + _huluganInterestPesos();

  /// Balance after first PayMongo (40% DP): financed × 1.06.
  double _huluganRemainingAfterDownPesos() => _huluganFinancedPrincipal() * 1.06;

  /// Grand total stored on the order (matches PayMongo full settle).
  double _orderGrandTotalForOrder() {
    if (_paymentPlan == CheckoutPaymentPlan.full) return _baseOrderTotal();
    if (_orderOption == CheckoutOrderOption.hulugan) return _huluganGrandTotalPayable();
    return _baseOrderTotal();
  }

  /// Lay-away: slider clamp. Hulugan: fixed 40%. Full: full.
  double _effectiveDownPaymentPesos() {
    if (_paymentPlan == CheckoutPaymentPlan.full) return _baseOrderTotal();
    if (_orderOption == CheckoutOrderOption.hulugan) return _huluganDownPaymentPesos();
    final total = _baseOrderTotal();
    if (total < _layawayDownMin) return total;
    final cap = math.min(_layawayDownMax, total);
    return _downPaymentPesos.clamp(_layawayDownMin, cap);
  }

  /// Shared required label: field name + red asterisk only.
  Widget _requiredLabel(String label, {double fontSize = 13}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: _kWalnutDeep,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        Text(
          '*',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: CupertinoColors.systemRed,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  /// Amount charged on the **first** PayMongo session for the selected plan.
  double _paymongoChargeAmountPesos() {
    if (_paymentPlan == CheckoutPaymentPlan.full) return _orderGrandTotalForOrder();
    return _effectiveDownPaymentPesos();
  }

  /// Remaining balance after the first tranche (0 for full pay).
  double _remainingAfterDownPesos() {
    if (_paymentPlan == CheckoutPaymentPlan.full) return 0;
    if (_orderOption == CheckoutOrderOption.hulugan) return _huluganRemainingAfterDownPesos();
    return (_baseOrderTotal() - _effectiveDownPaymentPesos()).clamp(0, double.infinity);
  }

  /// Info sheet: Lay-away vs Hulugan (matches business rules).
  void _showOrderOptionsInfoSheet() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Order options',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _kWalnutDeep,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(ctx),
                        child: Icon(CupertinoIcons.xmark_circle_fill, color: _kWalnut.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_policyTermMonths} months HULUGAN (Installments)',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _kWalnut,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• Available (in-stock) items only\n'
                    '• ${_huluganInterestPercent.toStringAsFixed(1)}% interest \n'
                    '• ${_huluganDownPercent.toStringAsFixed(0)}% down payment via PayMongo\n'
                    '• Estimated delivery 10–12 days after the order is confirmed (admin)\n'
                    '• Shipping fee applies as shown in your summary',
                    style: GoogleFonts.poppins(fontSize: 13, height: 1.45, color: _kWalnutDeep),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${_policyTermMonths} months LAY-AWAY',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _kWalnut,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• ₱${_layawayDownMin.toStringAsFixed(0)}–₱${_layawayDownMax.toStringAsFixed(0)} '
                    'down payment (you choose within the band)\n'
                    '• 0% / no interest on the plan\n'
                    '• Custom design choices where applicable\n'
                    '• Pay the balance within ${_policyTermMonths} months (from first payment)\n'
                    '• Delivery when fully paid',
                    style: GoogleFonts.poppins(fontSize: 13, height: 1.45, color: _kWalnutDeep),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickValidId() async {
    try {
      final x = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (!mounted) return;
      setState(() => _validIdXFile = x);
    } catch (e) {
      if (!mounted) return;
      Toast.warning(context, 'Could not pick image: $e');
    }
  }

  String _successSubtitle() {
    if (_paymentPlan == CheckoutPaymentPlan.full) {
      return 'PayMongo checkout should open in your browser. Your order updates when payment '
          'clears (usually seconds).';
    }
    if (_orderOption == CheckoutOrderOption.hulugan) {
      return 'First PayMongo charge is your ${_huluganDownPercent.toStringAsFixed(0)}% down payment. '
          'Balance includes ${_huluganInterestPercent.toStringAsFixed(1)}% on the financed '
          'amount. Estimated delivery is set 10–12 days after your order is confirmed.';
    }
    return 'First payment is your lay-away down payment. Your ${_policyTermMonths}-month 0% window starts '
        'when that payment clears. Delivery ships after you’re fully paid.';
  }

  /// Short policy copy that tracks Lay-away vs Hulugan vs full pay.
  String _policySummaryText() {
    const noRefund =
        '• No refunds on placed orders or payments — including if you cancel after a down payment.\n'
        '• You can cancel anytime; the no-refund rule still applies.\n';
    if (_paymentPlan == CheckoutPaymentPlan.full) {
      return '${noRefund}'
          '• Full payment via Gcash confirms the order; shipping fee is in your total.';
    }
    if (_orderOption == CheckoutOrderOption.hulugan) {
      return '${noRefund}'
          '• Hulugan: in-stock items only; ${_huluganDownPercent.toStringAsFixed(0)}% down via Gcash; '
          '${_huluganInterestPercent.toStringAsFixed(1)}% on the financed balance.\n'
          '• Balance due within $_policyTermMonths months from your first payment; '
          '₱${_policyLateFeePerDay.toStringAsFixed(0)}/day after month $_policyTermMonths until settled.\n'
          '• Estimated delivery 10–12 days after the order is confirmed (admin). Shipping fee included in total.';
    }
    return '${noRefund}'
        '• Lay-away: ₱${_layawayDownMin.toStringAsFixed(0)}–₱${_layawayDownMax.toStringAsFixed(0)} '
        'down via Gcash; 0% for $_policyTermMonths months from first payment.\n'
        '• Balance within $_policyTermMonths months from then; '
        '₱${_policyLateFeePerDay.toStringAsFixed(0)}/day after month $_policyTermMonths until settled.\n'
        '• Delivery only after the order is fully paid. Custom design choices where applicable.';
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

  /// Applies a selected saved address into the editable checkout form.
  /// This only updates local order form controllers and never updates the profile.
  void _applyAddressToForm(AddressEntry entry) {
    _postalCodeController.text = entry.postalCode;

    // Stored `street` may contain both line-1 and line-2 joined by commas.
    final streetParts = entry.street.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (streetParts.isNotEmpty) {
      _addressLine1Controller.text = streetParts.first;
      _addressLine2Controller.text = streetParts.length > 1 ? streetParts.sublist(1).join(', ') : '';
    } else {
      _addressLine1Controller.text = '';
      _addressLine2Controller.text = '';
    }

    final regionParts = entry.region.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    _selectedProvince = regionParts.isNotEmpty ? regionParts[0] : null;
    _selectedCity = regionParts.length > 1 ? regionParts[1] : null;
    _selectedBarangay = regionParts.length > 2 ? regionParts[2] : null;
  }

  /// Opens a local contact editor for this checkout only.
  /// Changes here are intentionally not persisted back to profile storage.
  void _openContactEditor() {
    final nameCtrl = TextEditingController(text: _nameController.text.trim());
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    final phoneCtrl = TextEditingController(text: _phoneController.text.trim());
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit Contact',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _buildSimpleSheetField(label: 'Full Name', controller: nameCtrl, required: true),
                _buildSimpleSheetField(
                  label: 'Email',
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                ),
                _buildSimpleSheetField(
                  label: 'Phone (11 digits, 09…)',
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: philippinesPhoneInputFormatters(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: _kWalnutSoftBg,
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            color: _kWalnut,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CupertinoButton(
                        color: _kWalnut,
                        onPressed: () {
                          final pErr = philippinesMobileRequiredError(phoneCtrl.text.trim());
                          if (pErr != null) {
                            Toast.warning(context, pErr);
                            return;
                          }
                          setState(() {
                            _nameController.text = nameCtrl.text.trim();
                            _emailController.text = emailCtrl.text.trim();
                            _phoneController.text = phoneCtrl.text.trim();
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: Text(
                          'Save',
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
    ).whenComplete(() {
      nameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
    });
  }

  /// Opens the address editor modal matching the exact design from addresses screen.
  /// Saving updates only this checkout form state.
  void _openAddressEditor() {
    final combinedStreet = [
      _addressLine1Controller.text.trim(),
      if (_addressLine2Controller.text.trim().isNotEmpty) _addressLine2Controller.text.trim(),
    ].join(', ');
    
    final currentUser = _auth.currentUser;
    final currentFullName = currentUser?.fullName ?? _nameController.text.trim();
    final currentPhone = currentUser?.phoneNumber ?? _phoneController.text.trim();

    final currentEntry = AddressEntry(
      id: '',
      // Name + contact are read-only (sourced from profile) during address edits.
      fullName: currentFullName,
      phoneNumber: currentPhone,
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
          setState(() {
            _applyAddressToForm(updatedEntry);
            _selectedAddressId = null;
          });
        },
      ),
    );
  }

  Widget _buildSimpleSheetField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (required)
            _requiredLabel(label, fontSize: 12)
          else
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _kWalnutDeep,
              ),
            ),
          const SizedBox(height: 4),
          CupertinoTextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kWalnut.withValues(alpha: 0.2)),
            ),
            style: GoogleFonts.poppins(fontSize: 13),
          ),
        ],
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
      _emailController.text = user.email;
      if (user.phoneNumber?.isNotEmpty ?? false) {
        _phoneController.text = user.phoneNumber!;
      }

      // Pull the richer address objects that live inside the profile storage.
      final savedAddresses = await _storage.loadAddresses(user.id);
      _savedAddresses = savedAddresses;
      if (savedAddresses.isNotEmpty) {
        // Always surface the default address; if the user somehow deleted the flag
        // we gracefully fall back to the first entry.
        defaultAddress = savedAddresses.firstWhere(
          (entry) => entry.isDefault,
          orElse: () => savedAddresses.first,
        );

        // Address selection defaults to the user's default address.
        _selectedAddressId = defaultAddress.id;
        _applyAddressToForm(defaultAddress);
      } else if (user.addresses.isNotEmpty) {
        // Legacy fallback where addresses were kept as a raw string list.
        final legacy = user.addresses.first;
        final parts = legacy.split(', ');
        _addressLine1Controller.text = parts.isNotEmpty ? parts.first : legacy;
        if (parts.length > 2) {
          _postalCodeController.text = parts[2];
        }
      }
    } else {
      _savedAddresses = [];
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
    _emailController.dispose();
    _downPaymentInputController.dispose();
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
      Toast.warning(context, 'Please add your full name in your profile');
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      setState(() => _loading = false);
      Toast.warning(context, 'Please add your phone number in your profile');
      return;
    }
    final phoneFmt = philippinesMobileRequiredError(_phoneController.text.trim());
    if (phoneFmt != null) {
      setState(() => _loading = false);
      Toast.warning(context, phoneFmt);
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

    if (_validIdXFile == null) {
      setState(() => _loading = false);
      Toast.warning(context, 'Upload one valid government ID to continue');
      return;
    }

    if (_paymentPlan == CheckoutPaymentPlan.downpayment) {
      if (_orderOption == CheckoutOrderOption.layaway && !_canOfferLayawaySplit) {
        setState(() => _loading = false);
        Toast.warning(
          context,
          'Lay-away needs at least ₱${_layawayDownMin.toStringAsFixed(0)} order total — pick full pay or Hulugan',
        );
        return;
      }
      if (_orderOption == CheckoutOrderOption.layaway) {
        final parsed = double.tryParse(_downPaymentInputController.text.replaceAll(',', '').trim());
        if (parsed == null) {
          setState(() => _loading = false);
          Toast.warning(context, 'Enter a valid down payment amount');
          return;
        }
        final maxDp = math.min(_layawayDownMax, _baseOrderTotal());
        if (parsed < _layawayDownMin || parsed > maxDp) {
          setState(() => _loading = false);
          Toast.warning(
            context,
            'Down payment must be between ₱${_layawayDownMin.toStringAsFixed(0)} and ₱${maxDp.toStringAsFixed(0)}',
          );
          return;
        }
        _downPaymentPesos = parsed;
      }
      if (_orderOption == CheckoutOrderOption.hulugan && !_canOfferHuluganSplit) {
        setState(() => _loading = false);
        Toast.warning(
          context,
          'Hulugan is for in-stock items only — adjust your cart or choose Lay-away / full pay',
        );
        return;
      }
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
      final totalForOrder = _orderGrandTotalForOrder();

      final planLabel = _paymentPlan == CheckoutPaymentPlan.full ? 'full' : 'downpayment';
      final downLine = _paymentPlan == CheckoutPaymentPlan.full
          ? totalForOrder
          : _effectiveDownPaymentPesos();
      final remainingLine = _paymentPlan == CheckoutPaymentPlan.full
          ? 0.0
          : _remainingAfterDownPesos();

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
        'shippingFee': shipping,
        // Hosted PayMongo only — backend routes checkout + webhooks to this method.
        'paymentMethod': 'paymongo',
        'paymentPlan': planLabel,
        'downpayment': downLine,
        'remainingBalance': remainingLine,
        // Line items only — correct subtotal in DB when total includes hulugan interest.
        'merchandiseSubtotal': subtotal,
        if (_paymentPlan == CheckoutPaymentPlan.downpayment)
          'orderOption': _orderOption == CheckoutOrderOption.layaway ? 'layaway' : 'hulugan',
      };

      final order = await _db.createOrder(
        userId: user.id,
        userName: user.fullName,
        productIds: checkoutItems.map((item) => item.product.id).toList(),
        totalAmount: totalForOrder,
        shippingAddress: shippingAddress,
        status: 'pending',
      );

      // KYC: one valid ID, stored server-side before we send the user to PayMongo.
      final idFile = _validIdXFile!;
      final idBytes = await idFile.readAsBytes();
      final idName = idFile.name.isNotEmpty ? idFile.name : 'valid_id.jpg';
      try {
        await _db.uploadOrderValidId(
          orderId: order.id,
          userId: user.id,
          imageBytes: idBytes,
          fileName: idName,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        Toast.error(context, 'ID upload failed: $e');
        developer.log('Valid ID upload error: $e', name: 'OrderSummary');
        return;
      }

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
      Toast.success(context, 'Order created — opening PayMongo checkout');

      // PayMongo: full pay and down payment both use hosted checkout (amount decided server-side).
      try {
        final checkoutUrl = await _db.createPaymongoCheckoutSession(
          orderId: order.id,
          userId: user.id,
        );
        if (!mounted) return;
        final payUri = Uri.parse(checkoutUrl);
        final opened = await launchUrl(
          payUri,
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) {
          Toast.warning(
            context,
            'Could not open browser — complete payment from Orders when ready.',
          );
        } else if (mounted) {
          Toast.info(context, 'Complete payment in the browser window.');
        }
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          CupertinoPageRoute(
            builder: (_) => SuccessScreen(
              subtitle: _successSubtitle(),
            ),
          ),
          (route) => route.isFirst,
        );
      } catch (e) {
        if (!mounted) return;
        Toast.error(context, 'PayMongo checkout failed: $e');
        developer.log('PayMongo checkout error: $e', name: 'OrderSummary');
      }
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
    final base = subtotal + shipping;
    final grand = _orderGrandTotalForOrder();

    // Keep split option valid if cart / stock changes while this screen is open.
    final validSplitOptions = <CheckoutOrderOption>[
      if (_canOfferLayawaySplit) CheckoutOrderOption.layaway,
      if (_canOfferHuluganSplit) CheckoutOrderOption.hulugan,
    ];
    if (_paymentPlan == CheckoutPaymentPlan.downpayment &&
        validSplitOptions.isNotEmpty &&
        !validSplitOptions.contains(_orderOption)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _orderOption = validSplitOptions.first);
      });
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: _kWalnut,
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
                    child: CachedModelSrcLoader(
                      sourceUrl: ModelPathHelper.normalize(item.product.modelPath),
                      placeholder: const Center(child: CupertinoActivityIndicator(radius: 10)),
                      builder: (context, resolvedSrc) => ModelViewer(
                        backgroundColor: const Color(0xFFEFEFEF),
                        src: resolvedSrc,
                        alt: '3D preview of ${item.product.name}',
                        ar: false,
                        environmentImage: 'neutral',
                        exposure: 1.35,
                        shadowIntensity: 0.18,
                        autoRotate: false,
                        cameraControls: false,
                        disableZoom: true,
                      ),
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
                            color: _kWalnut,
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

            // Contact card (editable only in this checkout).
            _CheckoutSectionCard(
              title: 'Contact',
              buttonLabel: 'Edit',
              onTapEdit: _openContactEditor,
              child: Column(
                children: [
                  _InfoRow(
                    label: 'Full Name',
                    value: _nameController.text.isEmpty ? 'Not provided' : _nameController.text,
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Email',
                    value: _emailController.text.isEmpty ? 'Not provided' : _emailController.text,
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Phone Number',
                    value: _phoneController.text.isEmpty ? 'Not provided' : _phoneController.text,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Address card with saved-address selector and local editor.
            _CheckoutSectionCard(
              title: 'Address',
              buttonLabel: 'Edit',
              onTapEdit: _openAddressEditor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_savedAddresses.isNotEmpty) ...[
                    Text(
                      'Saved address',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kWalnutDeep,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _kWalnutSoftBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kWalnut.withValues(alpha: 0.22)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedAddressId,
                          isExpanded: true,
                          icon: Icon(Icons.expand_more, color: _kWalnut),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _kWalnutDeep,
                          ),
                          items: _savedAddresses.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final address = entry.value;
                            final title = 'Address ${idx + 1}${address.isDefault ? ' (Default)' : ''}';
                            return DropdownMenuItem<String>(
                              value: address.id,
                              child: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            final picked = _savedAddresses.where((a) => a.id == value).toList();
                            if (picked.isEmpty) return;
                            setState(() {
                              _selectedAddressId = value;
                              _applyAddressToForm(picked.first);
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _InfoRow(label: 'Province', value: _selectedProvince ?? 'Not selected'),
                  const SizedBox(height: 8),
                  _InfoRow(label: 'City', value: _selectedCity ?? 'Not selected'),
                  const SizedBox(height: 8),
                  _InfoRow(label: 'Barangay', value: _selectedBarangay ?? 'Not selected'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'St./Bldg/House No.',
                    value: [
                      _addressLine1Controller.text.trim(),
                      if (_addressLine2Controller.text.trim().isNotEmpty) _addressLine2Controller.text.trim(),
                    ].where((line) => line.isNotEmpty).join(', ').isEmpty
                        ? 'Not provided'
                        : [
                            _addressLine1Controller.text.trim(),
                            if (_addressLine2Controller.text.trim().isNotEmpty) _addressLine2Controller.text.trim(),
                          ].where((line) => line.isNotEmpty).join(', '),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Postal Code',
                    value: _postalCodeController.text.isEmpty ? 'Not provided' : _postalCodeController.text,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // -----------------------------------------------------------------
            // Payment: PayMongo — payment type dropdown + order option (Lay-away / Hulugan).
            // -----------------------------------------------------------------
            Text(
              'Payment',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _kWalnutDeep,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Checkout is Gcash only. Choose full pay or split pay, then your plan.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: CupertinoColors.systemGrey,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Payment type',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kWalnutDeep,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _kWalnutSoftBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kWalnut.withValues(alpha: 0.25)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<CheckoutPaymentPlan>(
                  value: _paymentPlan,
                  isExpanded: true,
                  icon: Icon(Icons.expand_more, color: _kWalnut),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kWalnutDeep,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: CheckoutPaymentPlan.full,
                      child: Text('Full payment', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ),
                    if (_canUseAnySplitPlan)
                      DropdownMenuItem(
                        value: CheckoutPaymentPlan.downpayment,
                        child: Text(
                          'Down Payment',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _paymentPlan = v;
                      if (v == CheckoutPaymentPlan.downpayment) {
                        if (!_canOfferLayawaySplit && _canOfferHuluganSplit) {
                          _orderOption = CheckoutOrderOption.hulugan;
                        } else if (_canOfferLayawaySplit && !_canOfferHuluganSplit) {
                          _orderOption = CheckoutOrderOption.layaway;
                        }
                      }
                    });
                  },
                ),
              ),
            ),
            if (!_canUseAnySplitPlan) ...[
              const SizedBox(height: 8),
              Text(
                'Split pay needs either ₱3,000+ total (Lay-away) or in-stock items (Hulugan).',
                style: GoogleFonts.poppins(fontSize: 12, color: CupertinoColors.systemGrey),
              ),
            ],
            if (_paymentPlan == CheckoutPaymentPlan.downpayment) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Order option',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kWalnutDeep,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.all(4),
                    minimumSize: Size.zero,
                    onPressed: _showOrderOptionsInfoSheet,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _kWalnut.withValues(alpha: 0.45)),
                        color: Colors.white,
                      ),
                      child: Text(
                        '?',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _kWalnut,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _kWalnutSoftBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kWalnut.withValues(alpha: 0.25)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CheckoutOrderOption>(
                    value: _orderOption,
                    isExpanded: true,
                    icon: Icon(Icons.expand_more, color: _kWalnut),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kWalnutDeep,
                    ),
                    items: [
                      if (_canOfferLayawaySplit)
                        DropdownMenuItem(
                          value: CheckoutOrderOption.layaway,
                          child: Text(
                            'Lay-Away',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                          ),
                        ),
                      if (_canOfferHuluganSplit)
                        DropdownMenuItem(
                          value: CheckoutOrderOption.hulugan,
                          child: Text(
                            'Hulugan',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _orderOption = v);
                    },
                  ),
                ),
              ),
              if (_orderOption == CheckoutOrderOption.layaway && _canOfferLayawaySplit) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final maxDp = math.min(_layawayDownMax, base);
                    final minDp = math.min(_layawayDownMin, maxDp);
                    if (maxDp - minDp < 0.01) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lay-away down payment',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _kWalnutDeep,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Fixed at ₱${maxDp.toStringAsFixed(0)} (order total)',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _kWalnut,
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _requiredLabel('Amount', fontSize: 14),
                        const SizedBox(height: 6),
                        CupertinoTextField(
                          controller: _downPaymentInputController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          prefix: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(
                              '₱',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: _kWalnutDeep,
                              ),
                            ),
                          ),
                          onChanged: (value) {
                            final parsed = double.tryParse(value.replaceAll(',', '').trim());
                            if (parsed != null) {
                              setState(() => _downPaymentPesos = parsed.clamp(minDp, maxDp));
                            }
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _kWalnut.withValues(alpha: 0.25)),
                          ),
                        ),
                        Text(
                          'Allowed range: ₱${minDp.toStringAsFixed(0)} to ₱${maxDp.toStringAsFixed(0)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              if (_orderOption == CheckoutOrderOption.hulugan && _canOfferHuluganSplit) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kWalnutSoftBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kWalnut.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hulugan (installment)',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _kWalnutDeep,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_huluganDownPercent.toStringAsFixed(0)}% down now: ₱${_huluganDownPaymentPesos().toStringAsFixed(2)}\n'
                        '${_huluganInterestPercent.toStringAsFixed(1)}% on financed balance: ₱${_huluganInterestPesos().toStringAsFixed(2)}\n'
                        'Balance after down: ₱${_huluganRemainingAfterDownPesos().toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(fontSize: 12, height: 1.45, color: _kWalnutDeep),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kWalnutSoftBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kWalnut.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(CupertinoIcons.doc_text_fill, color: _kWalnut, size: 22),
                      const SizedBox(width: 10),
                      Expanded(child: _requiredLabel('Valid ID', fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upload one clear photo of a government-issued ID. PayMongo opens after you add it.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      height: 1.35,
                      color: _kWalnutDeep.withValues(alpha: 0.85),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_validIdXFile != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _validIdXFile!.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: _kWalnut,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            onPressed: () => setState(() => _validIdXFile = null),
                            child: Text(
                              'Remove',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: CupertinoColors.systemRed,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _pickValidId,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kWalnut.withValues(alpha: 0.35)),
                      ),
                      child: Center(
                        child: Text(
                          _validIdXFile == null ? 'Choose ID photo' : 'Change ID photo',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: _kWalnut,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoColors.systemBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kWalnut.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Policy & schedule',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kWalnutDeep,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _policySummaryText(),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      height: 1.45,
                      color: _kWalnutDeep.withValues(alpha: 0.88),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
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
                  if (_paymentPlan == CheckoutPaymentPlan.downpayment &&
                      _orderOption == CheckoutOrderOption.hulugan) ...[
                    const SizedBox(height: 6),
                    _TotalRow(
                      label: '${_huluganInterestPercent.toStringAsFixed(1)}% financing (on balance after ${_huluganDownPercent.toStringAsFixed(0)}% DP)',
                      value: '₱${_huluganInterestPesos().toStringAsFixed(2)}',
                    ),
                  ],
                  const Divider(height: 24),
                  _TotalRow(
                    label: 'Order total',
                    value: '₱${grand.toStringAsFixed(2)}',
                    isTotal: false,
                  ),
                  if (_paymentPlan == CheckoutPaymentPlan.downpayment &&
                      ((_orderOption == CheckoutOrderOption.layaway && _canOfferLayawaySplit) ||
                          (_orderOption == CheckoutOrderOption.hulugan && _canOfferHuluganSplit))) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 24),
                    _TotalRow(
                      label: 'Pay now',
                      value: '₱${_paymongoChargeAmountPesos().toStringAsFixed(2)}',
                      isHighlighted: true,
                    ),
                    const SizedBox(height: 6),
                    _TotalRow(
                      label: 'Remaining balance',
                      value: '₱${_remainingAfterDownPesos().toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _orderOption == CheckoutOrderOption.hulugan
                          ? 'After down payment, balance includes ${_huluganInterestPercent.toStringAsFixed(1)}% on the financed portion. '
                              'Second charge via PayMongo from Orders. '
                              'Delivery target: 10–12 days after the order is confirmed.'
                          : 'Second payment via PayMongo from Orders. 0% for $_policyTermMonths months from first payment; '
                              'delivery after full payment.',
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

            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _loading ? null : _placeOrder,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _loading ? _kWalnut.withValues(alpha: 0.45) : _kWalnut,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _kWalnut.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _loading
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : Text(
                        'Proceed to Pay',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          decoration: TextDecoration.none,
                        ),
                      ),
              ),
            ),
            // const SizedBox(height: 10),
            // Text(
            //   'PayMongo opens next — complete payment there. '
            //   'If you cancel, your order will be cancelled automatically.',
            //   style: GoogleFonts.poppins(
            //     fontSize: 12,
            //     color: CupertinoColors.systemGrey,
            //     decoration: TextDecoration.none,
            //   ),
            //   textAlign: TextAlign.center,
            // ),
            // const SizedBox(height: 8),
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
      color: selected ? _kWalnut : _kWalnutSoftBg,
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _kWalnut,
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

/// Shared card chrome used by checkout sections that have an "Edit" action.
class _CheckoutSectionCard extends StatelessWidget {
  const _CheckoutSectionCard({
    required this.title,
    required this.buttonLabel,
    required this.onTapEdit,
    required this.child,
  });

  final String title;
  final String buttonLabel;
  final VoidCallback onTapEdit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kWalnut.withValues(alpha: 0.22),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _kWalnutDeep,
                  decoration: TextDecoration.none,
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: onTapEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kWalnut,
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
                        buttonLabel,
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
          child,
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
              color: _kWalnutDeep.withValues(alpha: 0.72),
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
              color: _kWalnutDeep,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// Field-style info row used for the contact card.
/// Keeps labels readable while rendering values on white backgrounds.
class _InfoFieldRow extends StatelessWidget {
  const _InfoFieldRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _kWalnutDeep.withValues(alpha: 0.75),
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kWalnut.withValues(alpha: 0.2)),
          ),
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: _kWalnutDeep,
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
  final TextEditingController _postal = TextEditingController();
  final TextEditingController _street = TextEditingController();
  String _label = 'Home';

  final AuthService _auth = AuthService();

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
        (_selectedProvince == null ||
            _selectedCity == null ||
            _selectedBarangay == null ||
            _street.text.trim().isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
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
                Text('Address Philippines', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
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
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(10),
                        padding: EdgeInsets.zero,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF8D6E63), width: 1),
                          ),
                          child: Text(
                            'Cancel',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF8D6E63),
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        color: const Color(0xFF8D6E63),
                        borderRadius: BorderRadius.circular(10),
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

                          final user = _auth.currentUser;
                          final fullName = user?.fullName ?? widget.entry?.fullName ?? '';
                          final phone = user?.phoneNumber ?? widget.entry?.phoneNumber ?? '';

                          widget.onSubmit(
                            AddressEntry(
                              id: widget.entry?.id ?? '',
                              // Name + contact are sourced from profile; user cannot edit them here.
                              fullName: fullName,
                              phoneNumber: phone,
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
        errorText: showError ? '*' : null,
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
            color: isHighlighted ? _kWalnut : Colors.black,
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
            color: isHighlighted ? _kWalnut : Colors.black,
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


