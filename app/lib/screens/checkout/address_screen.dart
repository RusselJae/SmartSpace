import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';
import 'delivery_screen.dart';

// Color constants matching the app's design system
const _inkTitle = Color(0xFF6D4C41); // Medium brown for text

/// Address entry screen
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  // =============================================================
  // Core text controllers
  // -------------------------------------------------------------
  // We keep the original semantic fields but align them with the
  // new “City / Barangay dropdown + Block & Lot + Street” format.
  // The mapping is:
  //   - _line1  -> "Block and Lot" (free text)
  //   - _line2  -> "Street" (free text, still optional)
  //   - _city   -> Selected city from dropdown
  //   - _barangay -> Selected barangay from dropdown (NEW, kept
  //                  local to this screen so we don’t break
  //                  existing backend models)
  //   - _postal -> Postal code (kept as-is for now)
  //   - _name / _phone -> unchanged
  // =============================================================
  final TextEditingController _name = TextEditingController();
  final TextEditingController _line1 = TextEditingController();
  final TextEditingController _line2 = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _postal = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  // -------------------------------------------------------------
  // Cascading dropdown data source
  // -------------------------------------------------------------
  // We keep a simple 3-level hierarchy:
  //   Province -> City/Municipality -> Barangay
  // Backed by a JSON asset (`assets/philippines_addresses_sample.json`)
  // so you can drop in a full PH dataset later without touching
  // widget code. This keeps the UX Apple‑HIG‑style while avoiding
  // free‑text for location selection.
  final Map<String, List<String>> _provinceToCities = {};
  final Map<String, List<String>> _cityToBarangays = {};

  List<String> _allProvinces = [];
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedBarangay;

  String? _error;

  // Removed unused _loadingLocations field

  @override
  void initState() {
    super.initState();
    _loadPhilippinesLocationData();
  }

  Future<void> _loadPhilippinesLocationData() async {
    try {
      // Load the JSON file declared in pubspec. The shape expected is:
      // {
      //   "Metro Manila": {
      //     "Quezon City": ["Bagong Pag-asa", "Commonwealth"],
      //     "Makati": ["Bel-Air"]
      //   },
      //   "Cebu": {
      //     "Cebu City": ["Lahug"]
      //   }
      // }
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
        _allProvinces = _provinceToCities.keys.toList()..sort();
        // Location loading completed
      });
    } catch (e) {
      // If anything goes wrong we keep the screen usable by simply
      // disabling the dropdowns; the user can still see the form
      // but will get validation feedback instead of a crash.
      setState(() {
        // Location loading completed
        _error = 'Unable to load PH address list. Please try again later.';
      });
    }
  }

  bool get _hasValidationError =>
      _name.text.isEmpty ||
      _line1.text.isEmpty ||
      _selectedProvince == null ||
      _selectedCity == null ||
      _selectedBarangay == null ||
      _postal.text.isEmpty ||
      _phone.text.isEmpty;

  void _next() {
    // Reset any previous error before validating again so the user
    // clearly sees the most recent result of their action.
    setState(() => _error = null);

    if (_hasValidationError) {
      setState(() => _error = 'Please fill in all required fields');
      return;
    }

    // NOTE: We keep the outbound data contract untouched so the
    // downstream checkout flow keeps working:
    //   - addressLine1 still carries the primary address text. We
    //     now combine “Block & Lot” + “Street” into a single line
    //     to avoid schema changes.
    //   - city continues to represent the City value, even though
    //     we also have a Barangay internally for UI purposes.
    final mergedLine1 = [
      _line1.text.trim(), // Block & Lot
      if (_line2.text.trim().isNotEmpty) _line2.text.trim(), // Street
    ].join(', ');

    final address = AddressData(
      fullName: _name.text,
      addressLine1: mergedLine1,
      addressLine2: '$_selectedBarangay, $_selectedCity', // lightweight hint
      city: _selectedCity ?? '',
      postalCode: _postal.text,
      phone: _phone.text,
    );
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => DeliveryScreen(address: address)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: const Color(0xFF8D6E63),
        ),
        middle: Text(
          'Delivery Address',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                    color: _inkTitle,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // ---------------------------------------------------
            // Contact information
            // Required label markers are rendered in red to make
            // them visually unambiguous, as requested.
            // ---------------------------------------------------
            _SectionTitle('Contact Information', isRequired: true),
            const SizedBox(height: 8),
            _CupertinoField(
              controller: _name,
              placeholder: 'Full name',
              isRequired: true,
              showError: _error != null && _name.text.isEmpty,
            ),
            const SizedBox(height: 12),
            _CupertinoField(
              controller: _phone,
              placeholder: 'Phone number',
              keyboardType: TextInputType.phone,
              isRequired: true,
              showError: _error != null && _phone.text.isEmpty,
            ),
            const SizedBox(height: 20),
            // ---------------------------------------------------
            // Address section
            // City / Barangay are now dropdown‑driven while the
            // only free‑text address fields are:
            //   - Block and Lot
            //   - Street
            // ---------------------------------------------------
            _SectionTitle('Address', isRequired: true),
            const SizedBox(height: 8),
            _CupertinoField(
              controller: _line1,
              placeholder: 'Block and Lot',
              isRequired: true,
              showError: _error != null && _line1.text.isEmpty,
            ),
            const SizedBox(height: 12),
            _CupertinoField(
              controller: _line2,
              placeholder: 'Street (optional but recommended)',
            ),
            const SizedBox(height: 12),
            // Province dropdown (first level in the cascade).
            _DropdownField(
              label: 'Province',
              isRequired: true,
              value: _selectedProvince,
              options: _allProvinces,
              showError: _error != null && _selectedProvince == null,
              onChanged: (value) {
                setState(() {
                  _selectedProvince = value;
                  // When province changes, reset the downstream picks.
                  _selectedCity = null;
                  _selectedBarangay = null;
                  _city.text = '';
                });
              },
            ),
            const SizedBox(height: 12),
            _DropdownField(
              label: 'City',
              isRequired: true,
              value: _selectedCity,
              options: _selectedProvince == null
                  ? const []
                  : (_provinceToCities[_selectedProvince] ?? const []),
              showError: _error != null && _selectedCity == null,
              onChanged: (value) {
                setState(() {
                  _selectedCity = value;
                  // Reset barangay whenever the city changes so we
                  // never end up with a mismatched pair.
                  _selectedBarangay = null;
                  _city.text = value ?? '';
                });
              },
            ),
            const SizedBox(height: 12),
            _DropdownField(
              label: 'Barangay',
              isRequired: true,
              value: _selectedBarangay,
              options: _selectedCity == null
                  ? const []
                  : _cityToBarangays[_selectedCity] ?? const [],
              showError: _error != null && _selectedBarangay == null,
              onChanged: (value) {
                setState(() {
                  _selectedBarangay = value;
                });
              },
            ),
            const SizedBox(height: 12),
            _CupertinoField(
              controller: _postal,
              placeholder: 'Postal code',
              keyboardType: TextInputType.number,
              isRequired: true,
              showError: _error != null && _postal.text.isEmpty,
            ),
            const SizedBox(height: 20),
            Text(
              'Summary',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _inkTitle,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryRow(label: 'Recipient', value: _name.text.isEmpty ? '-' : _name.text),
                  const SizedBox(height: 6),
                  _SummaryRow(label: 'Phone', value: _phone.text.isEmpty ? '-' : _phone.text),
                  const SizedBox(height: 6),
                  _SummaryRow(
                    label: 'Block & Lot',
                    value: _line1.text.isEmpty ? '-' : _line1.text,
                  ),
                  if (_line2.text.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _SummaryRow(label: 'Street', value: _line2.text),
                  ],
                  const SizedBox(height: 6),
                  _SummaryRow(
                    label: 'City',
                    value: _selectedCity ?? '-',
                  ),
                  const SizedBox(height: 6),
                  _SummaryRow(
                    label: 'Barangay',
                    value: _selectedBarangay ?? '-',
                  ),
                  const SizedBox(height: 6),
                  _SummaryRow(
                    label: 'Postal',
                    value: _postal.text.isEmpty ? '-' : _postal.text,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: _next,
              child: Text(
                'Continue',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight Cupertino text field wrapper that:
/// - Aligns with the rest of the app’s glassy card aesthetic
/// - Knows whether it is a required field and can tint the border
///   red when the form is submitted with missing data.
class _CupertinoField extends StatelessWidget {
  const _CupertinoField({
    required this.controller,
    required this.placeholder,
    this.keyboardType,
    this.isRequired = false,
    this.showError = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;
  final bool isRequired;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final baseBorderColor = CupertinoColors.separator.withValues(alpha: 0.1);
    final effectiveBorderColor = showError ? CupertinoColors.systemRed : baseBorderColor;

    final effectivePlaceholder = isRequired ? '$placeholder *' : placeholder;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: effectiveBorderColor,
          width: showError ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: CupertinoTextField(
        controller: controller,
        placeholder: effectivePlaceholder,
        placeholderStyle: GoogleFonts.poppins(
          color: CupertinoColors.placeholderText,
          fontSize: 15,
          decoration: TextDecoration.none,
        ),
        style: const TextStyle(color: Color(0xFF6D4C41)),
        keyboardType: keyboardType,
        decoration: null,
        onChanged: (_) {
          // trigger rebuild for summary
          // ignore: invalid_use_of_protected_member
          (context as Element).markNeedsBuild();
        },
      ),
    );
  }
}

/// Small section header widget that appends a red asterisk when
/// `isRequired` is true. This keeps typography consistent while
/// satisfying the “required fields must be marked in red” rule.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label, {this.isRequired = false});

  final String label;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _inkTitle,
            decoration: TextDecoration.none,
          ),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.systemRed,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ],
    );
  }
}

/// Generic dropdown “pill” that behaves like a Cupertino form row
/// backed by a standard Flutter dropdown. We intentionally lean on
/// `DropdownButtonFormField` here so the interaction feels familiar
/// and consistent with other apps that use the default Flutter
/// selection field pattern.
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
    this.isRequired = false,
    this.showError = false,
  });

  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool isRequired;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: options.contains(value) ? value : null, // DropdownButtonFormField uses 'value' for controlled components
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        labelStyle: GoogleFonts.poppins(
          fontSize: 15,
          color: showError ? CupertinoColors.systemRed : _inkTitle,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        filled: true,
        fillColor: CupertinoColors.secondarySystemGroupedBackground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: CupertinoColors.separator.withValues(alpha: 0.1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: CupertinoColors.separator.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
                  fontSize: 15,
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: _inkTitle,
              fontSize: 14,
              fontWeight: FontWeight.normal,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              color: _inkTitle,
              fontSize: 14,
              fontWeight: FontWeight.normal,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}


