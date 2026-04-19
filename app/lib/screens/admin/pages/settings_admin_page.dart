import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/app_settings.dart';
import '../../../services/app_settings_service.dart';
import '../../../widgets/toast.dart';

/// Admin settings page for managing application configuration
/// 
/// Allows admins to configure:
/// - Shipping settings (fees, free shipping rules)
/// - Store information (used by About Us)
/// - Tax and service fee values
class SettingsAdminPage extends StatefulWidget {
  const SettingsAdminPage({super.key});

  @override
  State<SettingsAdminPage> createState() => _SettingsAdminPageState();
}

class _SettingsAdminPageState extends State<SettingsAdminPage> {
  final AppSettingsService _settingsService = AppSettingsService();
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  
  bool _loading = true;
  bool _saving = false;
  
  // Payment Settings
  final TextEditingController _gcashAccountController = TextEditingController();
  final TextEditingController _gcashNameController = TextEditingController();
  File? _qrCodeImage;
  String _qrCodeImagePath = 'assets/images/qrcode.jpg';
  double _codDownpaymentPercentage = 20.0;
  int _paymentConfirmationTime = 15;
  
  // Shipping Settings
  int _freeShippingProductCount = 3;
  final TextEditingController _freeShippingCitiesController = TextEditingController();
  final TextEditingController _specialShippingCitiesController = TextEditingController();
  final TextEditingController _selectedSpecialShippingFeeController = TextEditingController();
  // Lets admins rename the currently-selected "special shipping location"
  // (the map key in `specialShippingCities`).
  final TextEditingController _editSelectedSpecialShippingCityController = TextEditingController();
  final TextEditingController _newSpecialShippingCityController = TextEditingController();
  final TextEditingController _newSpecialShippingFeeController = TextEditingController();
  Map<String, double> _specialShippingCitiesMap = {};
  String? _selectedSpecialShippingCity;
  final TextEditingController _shippingFeeBaseController = TextEditingController();
  final TextEditingController _shippingFeeMaxController = TextEditingController();
  double _defaultShippingFeeBase = 3000.0;
  double _defaultShippingFeeMax = 5000.0;

  // Installment / lay-away policy + schedule
  final TextEditingController _layawayMinController = TextEditingController();
  final TextEditingController _layawayMaxController = TextEditingController();
  double _huluganDownpaymentPercent = 40.0;
  double _huluganInterestPercent = 6.0;
  int _installmentTermMonths = 3;
  double _lateFeePerDay = 100.0;
  
  // Store Information
  final TextEditingController _storeNameController = TextEditingController();
  final TextEditingController _storeEmailController = TextEditingController();
  final TextEditingController _storePhoneController = TextEditingController();
  final TextEditingController _storeAddressController = TextEditingController();
  File? _logoImage;
  String _logoImagePath = 'assets/images/logo.jpg';
  
  // Tax and Fees
  double _taxRate = 0.0;
  double _serviceFee = 0.0;
  
  // Other Settings
  double _minOrderAmount = 0.0;
  double _maxOrderAmount = 0.0;
  int _orderCancellationTime = 60;

  // Numeric fields (replaces range sliders for clearer input)
  final TextEditingController _huluganDpPctController = TextEditingController();
  final TextEditingController _huluganInterestController = TextEditingController();
  final TextEditingController _installmentMonthsController = TextEditingController();
  final TextEditingController _lateFeePerDayController = TextEditingController();
  final TextEditingController _taxRateController = TextEditingController();
  final TextEditingController _serviceFeeController = TextEditingController();

  // Dropdown options
  final List<int> _freeShippingCountOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _gcashAccountController.dispose();
    _gcashNameController.dispose();
    _freeShippingCitiesController.dispose();
    _specialShippingCitiesController.dispose();
    _selectedSpecialShippingFeeController.dispose();
    _editSelectedSpecialShippingCityController.dispose();
    _newSpecialShippingCityController.dispose();
    _newSpecialShippingFeeController.dispose();
    _shippingFeeBaseController.dispose();
    _shippingFeeMaxController.dispose();
    _layawayMinController.dispose();
    _layawayMaxController.dispose();
    _storeNameController.dispose();
    _storeEmailController.dispose();
    _storePhoneController.dispose();
    _storeAddressController.dispose();
    _huluganDpPctController.dispose();
    _huluganInterestController.dispose();
    _installmentMonthsController.dispose();
    _lateFeePerDayController.dispose();
    _taxRateController.dispose();
    _serviceFeeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final settings = await _settingsService.loadSettings();
      
      // Payment Settings
      _gcashAccountController.text = settings.gcashAccountNumber;
      _gcashNameController.text = settings.gcashAccountName;
      _qrCodeImagePath = settings.qrCodeImagePath;
      _codDownpaymentPercentage = settings.codDownpaymentPercentage;
      _paymentConfirmationTime = settings.paymentConfirmationTimeMinutes;
      
      // Shipping Settings
      _freeShippingProductCount = settings.freeShippingProductCount;
      _freeShippingCitiesController.text = settings.freeShippingCities.join(', ');
      _specialShippingCitiesMap = Map<String, double>.from(settings.specialShippingCities);
      _specialShippingCitiesController.text = _specialShippingCitiesMap.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
      final sortedCities = _specialShippingCitiesMap.keys.toList()..sort();
      _selectedSpecialShippingCity = sortedCities.isEmpty ? null : sortedCities.first;
      if (_selectedSpecialShippingCity != null) {
        _selectedSpecialShippingFeeController.text =
            _specialShippingCitiesMap[_selectedSpecialShippingCity!]!.toStringAsFixed(0);
        _editSelectedSpecialShippingCityController.text = _selectedSpecialShippingCity!;
      } else {
        _selectedSpecialShippingFeeController.clear();
        _editSelectedSpecialShippingCityController.clear();
      }
      _defaultShippingFeeBase = settings.defaultShippingFeeBase;
      _defaultShippingFeeMax = settings.defaultShippingFeeMax;
      _shippingFeeBaseController.text = _defaultShippingFeeBase.toStringAsFixed(0);
      _shippingFeeMaxController.text = _defaultShippingFeeMax.toStringAsFixed(0);

      _huluganDownpaymentPercent = settings.huluganDownpaymentPercent;
      _huluganInterestPercent = settings.huluganInterestPercent;
      _installmentTermMonths = settings.installmentTermMonths;
      _lateFeePerDay = settings.lateFeePerDay;
      _huluganDpPctController.text = _huluganDownpaymentPercent.toStringAsFixed(0);
      _huluganInterestController.text = _huluganInterestPercent.toStringAsFixed(1);
      _installmentMonthsController.text = _installmentTermMonths.toString();
      _lateFeePerDayController.text = _lateFeePerDay.toStringAsFixed(0);
      _taxRateController.text = _taxRate.toStringAsFixed(1);
      _serviceFeeController.text = _serviceFee.toStringAsFixed(0);
      _layawayMinController.text = settings.layawayDownpaymentMin.toStringAsFixed(0);
      _layawayMaxController.text = settings.layawayDownpaymentMax.toStringAsFixed(0);
      
      // Store Information
      _storeNameController.text = settings.storeName;
      _storeEmailController.text = settings.storeEmail;
      _storePhoneController.text = settings.storePhone;
      _storeAddressController.text = settings.storeAddress;
      _logoImagePath = settings.logoImagePath;
      
      // Tax and Fees
      _taxRate = settings.taxRate;
      _serviceFee = settings.serviceFee;
      
      // Other Settings
      _minOrderAmount = settings.minOrderAmount;
      _maxOrderAmount = settings.maxOrderAmount;
      _orderCancellationTime = settings.orderCancellationTimeMinutes;
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to load settings: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickImage({required bool isQRCode}) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null && mounted) {
        setState(() {
          if (isQRCode) {
            _qrCodeImage = File(image.path);
            _qrCodeImagePath = image.path; // Store local path for now
          } else {
            _logoImage = File(image.path);
            _logoImagePath = image.path; // Store local path for now
          }
        });
        Toast.success(context, 'Image selected successfully');
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Failed to pick image: $e');
      }
    }
  }

  List<String> get _specialShippingCityOptions {
    final keys = _specialShippingCitiesMap.keys.toList()..sort();
    return keys;
  }

  void _setSelectedSpecialCity(String? city) {
    setState(() {
      _selectedSpecialShippingCity = city;
      if (city == null) {
        _selectedSpecialShippingFeeController.clear();
        _editSelectedSpecialShippingCityController.clear();
      } else {
        _selectedSpecialShippingFeeController.text =
            _specialShippingCitiesMap[city]?.toStringAsFixed(0) ?? '';
        _editSelectedSpecialShippingCityController.text = city;
      }
    });
  }

  void _onSelectedSpecialFeeChanged(String raw) {
    final city = _selectedSpecialShippingCity;
    if (city == null) return;
    final nextFee = double.tryParse(raw.trim());
    if (nextFee == null || nextFee < 0) return;
    setState(() {
      _specialShippingCitiesMap[city] = nextFee;
      // Keep text representation synced for backward compatibility/debugging.
      _specialShippingCitiesController.text = _specialShippingCitiesMap.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
    });
  }

  void _addOrUpdateSpecialShippingCity() {
    final cityRaw = _newSpecialShippingCityController.text.trim().toLowerCase();
    final fee = double.tryParse(_newSpecialShippingFeeController.text.trim());
    if (cityRaw.isEmpty) {
      Toast.error(context, 'Enter a location name');
      return;
    }
    if (fee == null || fee < 0) {
      Toast.error(context, 'Enter a valid fee amount');
      return;
    }
    setState(() {
      _specialShippingCitiesMap[cityRaw] = fee;
      _selectedSpecialShippingCity = cityRaw;
      _selectedSpecialShippingFeeController.text = fee.toStringAsFixed(0);
      _editSelectedSpecialShippingCityController.text = cityRaw;
      _specialShippingCitiesController.text = _specialShippingCitiesMap.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
      _newSpecialShippingCityController.clear();
      _newSpecialShippingFeeController.clear();
    });
    Toast.success(context, 'Location fee saved');
  }

  void _removeSelectedSpecialShippingCity() {
    final city = _selectedSpecialShippingCity;
    if (city == null) return;
    setState(() {
      _specialShippingCitiesMap.remove(city);
      final options = _specialShippingCityOptions;
      _selectedSpecialShippingCity = options.isEmpty ? null : options.first;
      if (_selectedSpecialShippingCity != null) {
        _selectedSpecialShippingFeeController.text =
            _specialShippingCitiesMap[_selectedSpecialShippingCity!]!.toStringAsFixed(0);
        _editSelectedSpecialShippingCityController.text = _selectedSpecialShippingCity!;
      } else {
        _selectedSpecialShippingFeeController.clear();
        _editSelectedSpecialShippingCityController.clear();
      }
      _specialShippingCitiesController.text = _specialShippingCitiesMap.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
    });
    Toast.success(context, 'Location removed');
  }

  void _renameSelectedSpecialShippingCity() {
    final oldCity = _selectedSpecialShippingCity;
    if (oldCity == null) return;

    // Rename changes the map key (location name), while keeping the existing fee.
    final newCityRaw = _editSelectedSpecialShippingCityController.text.trim().toLowerCase();
    if (newCityRaw.isEmpty) {
      Toast.error(context, 'Enter a location name to rename');
      return;
    }
    final oldCityLower = oldCity.toLowerCase();
    if (newCityRaw == oldCityLower) {
      Toast.info(context, 'Location name unchanged');
      return;
    }

    // Case-insensitive conflict check (e.g. "Imus" vs "imus").
    final hasCaseInsensitiveConflict = _specialShippingCitiesMap.keys.any(
      (k) => k.toLowerCase() == newCityRaw && k != oldCity,
    );
    if (hasCaseInsensitiveConflict) {
      Toast.error(context, 'That location name already exists');
      return;
    }

    final fee = _specialShippingCitiesMap[oldCity];
    if (fee == null) {
      Toast.error(context, 'Selected location is missing a fee');
      return;
    }

    setState(() {
      _specialShippingCitiesMap.remove(oldCity);
      _specialShippingCitiesMap[newCityRaw] = fee;
      _selectedSpecialShippingCity = newCityRaw;

      // Keep UI fields synced.
      _selectedSpecialShippingFeeController.text = fee.toStringAsFixed(0);
      _editSelectedSpecialShippingCityController.text = newCityRaw;
      _specialShippingCitiesController.text = _specialShippingCitiesMap.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
    });

    Toast.success(context, 'Location renamed');
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final dp = double.tryParse(_huluganDpPctController.text.trim());
      if (dp != null) {
        _huluganDownpaymentPercent = dp.clamp(10.0, 90.0);
      }
      final intr = double.tryParse(_huluganInterestController.text.trim());
      if (intr != null) {
        _huluganInterestPercent = intr.clamp(0.0, 20.0);
      }
      final months = int.tryParse(_installmentMonthsController.text.trim());
      if (months != null) {
        _installmentTermMonths = months.clamp(1, 12);
      }
      final late = double.tryParse(_lateFeePerDayController.text.trim());
      if (late != null) {
        _lateFeePerDay = late.clamp(0.0, 1000.0);
      }
      final tax = double.tryParse(_taxRateController.text.trim());
      if (tax != null) {
        _taxRate = tax.clamp(0.0, 100.0);
      }
      final svc = double.tryParse(_serviceFeeController.text.trim());
      if (svc != null) {
        _serviceFee = svc.clamp(0.0, 1000.0);
      }

      // Special shipping cities are managed by dropdown + amount field state.
      final specialShippingMap = Map<String, double>.from(_specialShippingCitiesMap);

      // Parse free shipping cities
      final freeShippingCities = _freeShippingCitiesController.text
          .split(',')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();

      final settings = AppSettings(
        // Payment Settings
        gcashAccountNumber: _gcashAccountController.text.trim(),
        gcashAccountName: _gcashNameController.text.trim(),
        qrCodeImagePath: _qrCodeImagePath,
        codDownpaymentPercentage: _codDownpaymentPercentage,
        paymentConfirmationTimeMinutes: _paymentConfirmationTime,
        
        // Shipping Settings
        freeShippingProductCount: _freeShippingProductCount,
        freeShippingCities: freeShippingCities,
        specialShippingCities: specialShippingMap,
        defaultShippingFeeBase: _defaultShippingFeeBase,
        defaultShippingFeeMax: _defaultShippingFeeMax,
        layawayDownpaymentMin: double.tryParse(_layawayMinController.text.trim()) ?? 3000.0,
        layawayDownpaymentMax: double.tryParse(_layawayMaxController.text.trim()) ?? 5000.0,
        huluganDownpaymentPercent: _huluganDownpaymentPercent,
        huluganInterestPercent: _huluganInterestPercent,
        installmentTermMonths: _installmentTermMonths,
        lateFeePerDay: _lateFeePerDay,
        
        // Store Information
        storeName: _storeNameController.text.trim(),
        storeEmail: _storeEmailController.text.trim(),
        storePhone: _storePhoneController.text.trim(),
        storeAddress: _storeAddressController.text.trim(),
        logoImagePath: _logoImagePath,
        
        // Tax and Fees
        taxRate: _taxRate,
        serviceFee: _serviceFee,
        
        // Other Settings
        minOrderAmount: _minOrderAmount,
        maxOrderAmount: _maxOrderAmount,
        orderCancellationTimeMinutes: _orderCancellationTime,
      );

      await _settingsService.saveSettings(settings);
      _settingsService.clearCache(); // Clear cache to force reload
      
      if (mounted) {
        Toast.success(context, 'Settings saved successfully');
        // Reflect clamped / normalized values back into the fields.
        setState(() {
          _huluganDpPctController.text = _huluganDownpaymentPercent.toStringAsFixed(0);
          _huluganInterestController.text = _huluganInterestPercent.toStringAsFixed(1);
          _installmentMonthsController.text = _installmentTermMonths.toString();
          _lateFeePerDayController.text = _lateFeePerDay.toStringAsFixed(0);
          _taxRateController.text = _taxRate.toStringAsFixed(1);
          _serviceFeeController.text = _serviceFee.toStringAsFixed(0);
        });
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Failed to save settings: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildSectionTitle(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(height: 1, thickness: 1),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int? maxLines,
    void Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines ?? 1,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red, width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: GoogleFonts.poppins(fontSize: 13),
            validator: validator,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) displayText,
    required void Function(T?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<T>(
            // ignore: deprecated_member_use
            value: value,
            items: items.map((item) {
              return DropdownMenuItem<T>(
                value: item,
                child: Text(
                  displayText(item),
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
              );
            }).toList(),
            onChanged: onChanged,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: GoogleFonts.poppins(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildImageUpload({
    required String label,
    required File? image,
    required String imagePath,
    required void Function() onPick,
  }) {
    // Extract filename and extension
    String? fileName;
    String? fileExtension;
    
    if (image != null) {
      final path = image.path;
      final pathParts = path.split('/');
      fileName = pathParts.last;
      final dotIndex = fileName.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex < fileName.length - 1) {
        fileExtension = fileName.substring(dotIndex + 1).toUpperCase();
        fileName = fileName.substring(0, dotIndex);
      }
    } else if (!imagePath.startsWith('assets/')) {
      final pathParts = imagePath.split('/');
      fileName = pathParts.last;
      final dotIndex = fileName.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex < fileName.length - 1) {
        fileExtension = fileName.substring(dotIndex + 1).toUpperCase();
        fileName = fileName.substring(0, dotIndex);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onPick,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: image != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            image,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                        if (fileName != null)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      fileName.length > 20 ? '${fileName.substring(0, 20)}...' : fileName,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (fileExtension != null) ...[
                                    Text(
                                      '.$fileExtension',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
                  : imagePath.startsWith('assets/')
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_outlined, size: 32, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                'Tap to upload',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_outlined, size: 32, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              if (fileName != null)
                                Text(
                                  '$fileName${fileExtension != null ? '.$fileExtension' : ''}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                )
                              else
                                Text(
                                  'Tap to change',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Application Settings',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage shipping logic and store information',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 32),

                // Two Column Layout
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Shipping Settings
                          _buildSectionTitle('Shipping Settings'),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Checkout uses this rule order: free-shipping product count, then free-shipping cities, then special city fee overrides, then default base/max fallback.',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.black54,
                                height: 1.4,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          _buildDropdown<int>(
                            label: 'Free shipping product count threshold',
                            value: _freeShippingProductCount,
                            items: _freeShippingCountOptions,
                            displayText: (value) => value == 0 ? 'No free shipping' : '$value products',
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _freeShippingProductCount = value;
                                });
                              }
                            },
                          ),
                          _buildTextField(
                            label: 'Free-shipping cities (comma-separated)',
                            controller: _freeShippingCitiesController,
                            hint: 'dasmariñas, dasmarinas',
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Special shipping location',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[700],
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedSpecialShippingCity,
                                  items: _specialShippingCityOptions
                                      .map(
                                        (city) => DropdownMenuItem<String>(
                                          value: city,
                                          child: Text(
                                            city,
                                            style: GoogleFonts.poppins(fontSize: 13),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _specialShippingCityOptions.isEmpty ? null : _setSelectedSpecialCity,
                                  decoration: InputDecoration(
                                    hintText: _specialShippingCityOptions.isEmpty
                                        ? 'No special city overrides configured yet'
                                        : 'Select location',
                                    filled: true,
                                    fillColor: const Color(0xFFF8F8F8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Colors.grey[300]!),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Colors.grey[300]!),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildTextField(
                            label: 'Selected location shipping fee (₱)',
                            controller: _selectedSpecialShippingFeeController,
                            hint: 'Auto-filled from selected location',
                            keyboardType: TextInputType.number,
                            onChanged: _onSelectedSpecialFeeChanged,
                          ),
                          if (_selectedSpecialShippingCity != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _editSelectedSpecialShippingCityController,
                                      decoration: InputDecoration(
                                        labelText: 'Edit selected location name',
                                        hintText: 'e.g. bacoor',
                                        filled: true,
                                        fillColor: const Color(0xFFF8F8F8),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: Colors.grey[300]!),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: Colors.grey[300]!),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                      style: GoogleFonts.poppins(fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 150,
                                    child: ElevatedButton.icon(
                                      onPressed: _renameSelectedSpecialShippingCity,
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      label: const Text('Rename'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF8D6E63),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _newSpecialShippingCityController,
                                    decoration: InputDecoration(
                                      labelText: 'Add location',
                                      hintText: 'e.g. imus',
                                      filled: true,
                                      fillColor: const Color(0xFFF8F8F8),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.grey[300]!),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.grey[300]!),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                    style: GoogleFonts.poppins(fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 150,
                                  child: TextFormField(
                                    controller: _newSpecialShippingFeeController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Fee (₱)',
                                      hintText: '1800',
                                      filled: true,
                                      fillColor: const Color(0xFFF8F8F8),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.grey[300]!),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.grey[300]!),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                    style: GoogleFonts.poppins(fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _addOrUpdateSpecialShippingCity,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8D6E63),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_selectedSpecialShippingCity != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _removeSelectedSpecialShippingCity,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Remove selected location'),
                                style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'When you pick a location above (e.g. bacoor), this field auto-fills its shipping fee (e.g. 1800).',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.black54,
                                height: 1.35,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          // Shipping fee range as input fields in one line
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Fallback shipping base (₱)',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey[700],
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                        controller: _shippingFeeBaseController,
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText: '3000',
                                          filled: true,
                                          fillColor: const Color(0xFFF8F8F8),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: Colors.grey[300]!),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: Colors.grey[300]!),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        ),
                                        style: GoogleFonts.poppins(fontSize: 13),
                                        onChanged: (value) {
                                          final parsed = double.tryParse(value);
                                          if (parsed != null) {
                                            setState(() {
                                              _defaultShippingFeeBase = parsed;
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Fallback shipping max (₱)',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey[700],
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                        controller: _shippingFeeMaxController,
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText: '5000',
                                          filled: true,
                                          fillColor: const Color(0xFFF8F8F8),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: Colors.grey[300]!),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: Colors.grey[300]!),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        ),
                                        style: GoogleFonts.poppins(fontSize: 13),
                                        onChanged: (value) {
                                          final parsed = double.tryParse(value);
                                          if (parsed != null) {
                                            setState(() {
                                              _defaultShippingFeeMax = parsed;
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Plan Policy & Schedule
                          _buildSectionTitle('Plan Policy & Schedule'),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    label: 'Lay-away DP minimum (₱)',
                                    controller: _layawayMinController,
                                    hint: '3000',
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    label: 'Lay-away DP maximum (₱)',
                                    controller: _layawayMaxController,
                                    hint: '5000',
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  label: 'Installment down payment (%)',
                                  controller: _huluganDpPctController,
                                  hint: '10–90',
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildTextField(
                                  label: 'Installment financing interest (%)',
                                  controller: _huluganInterestController,
                                  hint: '0–20',
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  label: 'Installment term (months)',
                                  controller: _installmentMonthsController,
                                  hint: '1–12',
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildTextField(
                                  label: 'Late fee per day (₱)',
                                  controller: _lateFeePerDayController,
                                  hint: '0–1000',
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 24),

                    // Right Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Store Information
                          _buildSectionTitle('Store Information'),
                          _buildTextField(
                            label: 'Store Name',
                            controller: _storeNameController,
                            hint: 'Wood Home Furniture Trading',
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Fill this field';
                              }
                              return null;
                            },
                          ),
                          _buildTextField(
                            label: 'Store Email',
                            controller: _storeEmailController,
                            hint: 'store@example.com',
                            keyboardType: TextInputType.emailAddress,
                          ),
                          _buildTextField(
                            label: 'Store Phone',
                            controller: _storePhoneController,
                            hint: '+63 123 456 7890',
                            keyboardType: TextInputType.phone,
                          ),
                          _buildTextField(
                            label: 'Store Address',
                            controller: _storeAddressController,
                            hint: '123 Main Street, City, Country',
                            maxLines: 2,
                          ),
                          _buildImageUpload(
                            label: 'Logo Image',
                            image: _logoImage,
                            imagePath: _logoImagePath,
                            onPick: () => _pickImage(isQRCode: false),
                          ),

                          // Tax and Fees
                          _buildSectionTitle('Tax and Fees'),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  label: 'Tax rate (%)',
                                  controller: _taxRateController,
                                  hint: '0–100',
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildTextField(
                                  label: 'Service fee (₱)',
                                  controller: _serviceFeeController,
                                  hint: '0–1000',
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ),

                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                
                // Save Button
                Center(
                  child: SizedBox(
                    width: 200,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8D6E63),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Save Settings',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                decoration: TextDecoration.none,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
