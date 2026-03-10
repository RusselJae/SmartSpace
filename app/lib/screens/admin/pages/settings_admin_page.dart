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
/// - Payment settings (GCash account, QR code, downpayment percentage)
/// - Shipping settings (fees, free shipping rules)
/// - Store information
/// - Tax and fees
/// - Other configurable values
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
  final TextEditingController _shippingFeeBaseController = TextEditingController();
  final TextEditingController _shippingFeeMaxController = TextEditingController();
  double _defaultShippingFeeBase = 3000.0;
  double _defaultShippingFeeMax = 5000.0;
  
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

  // Dropdown options
  final List<int> _paymentTimeOptions = [5, 10, 15, 20, 30, 45, 60];
  final List<int> _freeShippingCountOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  final List<int> _cancellationTimeOptions = [15, 30, 45, 60, 90, 120, 180, 240];

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
    _shippingFeeBaseController.dispose();
    _shippingFeeMaxController.dispose();
    _storeNameController.dispose();
    _storeEmailController.dispose();
    _storePhoneController.dispose();
    _storeAddressController.dispose();
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
      _specialShippingCitiesController.text = settings.specialShippingCities.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
      _defaultShippingFeeBase = settings.defaultShippingFeeBase;
      _defaultShippingFeeMax = settings.defaultShippingFeeMax;
      _shippingFeeBaseController.text = _defaultShippingFeeBase.toStringAsFixed(0);
      _shippingFeeMaxController.text = _defaultShippingFeeMax.toStringAsFixed(0);
      
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

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      // Parse special shipping cities
      final specialShippingMap = <String, double>{};
      final specialShippingText = _specialShippingCitiesController.text.trim();
      if (specialShippingText.isNotEmpty) {
        final entries = specialShippingText.split(',');
        for (final entry in entries) {
          final parts = entry.trim().split(':');
          if (parts.length == 2) {
            final city = parts[0].trim().toLowerCase();
            final fee = double.tryParse(parts[1].trim());
            if (fee != null && city.isNotEmpty) {
              specialShippingMap[city] = fee;
            }
          }
        }
      }

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

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required void Function(double) onChanged,
    String Function(double)? valueDisplay,
    int? divisions,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              Text(
                valueDisplay?.call(value) ?? value.toStringAsFixed(1),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8D6E63),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: const Color(0xFF8D6E63),
            onChanged: onChanged,
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
                  'Manage payment, shipping, and store configuration',
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
                          // Payment Settings
                          _buildSectionTitle('Payment Settings'),
                          _buildTextField(
                            label: 'GCash Account Number',
                            controller: _gcashAccountController,
                            hint: '09123456789',
                            keyboardType: TextInputType.phone,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                          _buildTextField(
                            label: 'GCash Account Name',
                            controller: _gcashNameController,
                            hint: 'Rosalie M. Enon',
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                          _buildImageUpload(
                            label: 'QR Code Image',
                            image: _qrCodeImage,
                            imagePath: _qrCodeImagePath,
                            onPick: () => _pickImage(isQRCode: true),
                          ),
                          _buildSlider(
                            label: 'COD Downpayment Percentage',
                            value: _codDownpaymentPercentage,
                            min: 0,
                            max: 100,
                            divisions: 100,
                            onChanged: (value) {
                              setState(() {
                                _codDownpaymentPercentage = value;
                              });
                            },
                            valueDisplay: (value) => '${value.toStringAsFixed(0)}%',
                          ),
                          _buildDropdown<int>(
                            label: 'Payment Confirmation Time',
                            value: _paymentConfirmationTime,
                            items: _paymentTimeOptions,
                            displayText: (value) => '$value minutes',
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _paymentConfirmationTime = value;
                                });
                              }
                            },
                          ),

                          // Shipping Settings
                          _buildSectionTitle('Shipping Settings'),
                          _buildDropdown<int>(
                            label: 'Free Shipping Product Count',
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
                            label: 'Free Shipping Cities (comma-separated)',
                            controller: _freeShippingCitiesController,
                            hint: 'dasmariñas, dasmarinas',
                          ),
                          _buildTextField(
                            label: 'Special Shipping Cities (format: city:amount)',
                            controller: _specialShippingCitiesController,
                            hint: 'bacoor:1800.0',
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
                                        'Shipping Fee Base (₱)',
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
                                        'Shipping Fee Max (₱)',
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
                                return 'Required';
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
                          _buildSlider(
                            label: 'Tax Rate',
                            value: _taxRate,
                            min: 0,
                            max: 100,
                            divisions: 200,
                            onChanged: (value) {
                              setState(() {
                                _taxRate = value;
                              });
                            },
                            valueDisplay: (value) => '${value.toStringAsFixed(1)}%',
                          ),
                          _buildSlider(
                            label: 'Service Fee',
                            value: _serviceFee,
                            min: 0,
                            max: 1000,
                            divisions: 200,
                            onChanged: (value) {
                              setState(() {
                                _serviceFee = value;
                              });
                            },
                            valueDisplay: (value) => '₱${value.toStringAsFixed(0)}',
                          ),

                          // Other Settings
                          _buildSectionTitle('Other Settings'),
                          _buildSlider(
                            label: 'Minimum Order Amount',
                            value: _minOrderAmount,
                            min: 0,
                            max: 50000,
                            divisions: 500,
                            onChanged: (value) {
                              setState(() {
                                _minOrderAmount = value;
                              });
                            },
                            valueDisplay: (value) => value == 0 ? 'No minimum' : '₱${value.toStringAsFixed(0)}',
                          ),
                          _buildSlider(
                            label: 'Maximum Order Amount',
                            value: _maxOrderAmount,
                            min: 0,
                            max: 500000,
                            divisions: 500,
                            onChanged: (value) {
                              setState(() {
                                _maxOrderAmount = value;
                              });
                            },
                            valueDisplay: (value) => value == 0 ? 'No maximum' : '₱${value.toStringAsFixed(0)}',
                          ),
                          _buildDropdown<int>(
                            label: 'Order Cancellation Time',
                            value: _orderCancellationTime,
                            items: _cancellationTimeOptions,
                            displayText: (value) => '$value minutes',
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _orderCancellationTime = value;
                                });
                              }
                            },
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
