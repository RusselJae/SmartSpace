import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';

import '../../models/address_entry.dart';
import '../../services/auth_service.dart';
import '../../services/profile_storage.dart';

// Signature Wood Home Furniture Trading earth tones so the addresses page does not randomly fall back
// to the default Material red (which is what caused the screenshot issues).
// Updated color palette: removed dark brown, using medium brown and orange
const _coffeePrimary = Color(0xFF8D6E63); // Primary brown
const _inkTitle = Color(0xFF6D4C41); // Medium brown for text
const _inkBody = Color(0xFF5F5B56);
const _badgeAmber = Color(0xFFFFE0B2);
const _badgeAmberText = Color(0xFF8D6E63);
const _badgeRose = Color(0xFFF8D7DA);
const _badgeRoseText = Color(0xFFB23C17);
const _cardBackground = Color(0xFFFDFBF7);

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final AuthService _auth = AuthService();
  final ProfileStorage _storage = ProfileStorage();
  List<AddressEntry> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _addresses = [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final data = await _storage.loadAddresses(user.id);
      setState(() {
        _addresses = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _addresses = [];
        _loading = false;
      });
    }
  }

  Future<void> _save(List<AddressEntry> items) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _storage.saveAddresses(user.id, items);
    setState(() => _addresses = items);
  }

  void _openEditor({AddressEntry? entry}) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _AddressEditorSheet(
        entry: entry,
        onSubmit: (value) async {
          final list = [..._addresses];
          if (entry == null) {
            list.add(value.copyWith(id: _generateId(), isDefault: list.isEmpty));
          } else {
            final index = list.indexWhere((item) => item.id == entry.id);
            if (index != -1) {
              list[index] = value.copyWith(id: entry.id, isDefault: entry.isDefault);
            }
          }
          await _save(list);
        },
      ),
    );
  }

  String _generateId() => DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(9999).toString();

  Future<void> _delete(String id) async {
    final list = _addresses.where((item) => item.id != id).toList();
    if (list.isNotEmpty && !list.any((item) => item.isDefault)) {
      list[0] = list[0].copyWith(isDefault: true);
    }
    await _save(list);
  }

  Future<void> _setDefault(String id) async {
    final list = _addresses
        .map((item) => item.copyWith(isDefault: item.id == id))
        .toList();
    await _save(list);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: _coffeePrimary,
        ),
        middle: Text('My Addresses', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: CupertinoButton.filled(
                      onPressed: () => _openEditor(),
                      child: Text('Add New Address', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  Expanded(
                    child: _addresses.isEmpty
                        ? Center(
                            child: Text(
                              'No addresses yet. Add one to speed up checkout.',
                              style: GoogleFonts.poppins(color: _inkBody.withValues(alpha: 0.7), fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemBuilder: (context, index) {
                              final address = _addresses[index];
                              return _AddressCard(
                                entry: address,
                                onEdit: () => _openEditor(entry: address),
                                onDelete: () => _delete(address.id),
                                onSetDefault: address.isDefault ? null : () => _setDefault(address.id),
                              );
                            },
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemCount: _addresses.length,
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Compact dropdown field used inside the modal sheet so the PH
/// address cascade still feels like a native Apple form row.
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
      value: options.contains(value) ? value : null, // DropdownButtonFormField uses 'value' for controlled components
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: showError ? CupertinoColors.systemRed : _inkTitle,
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
            color: showError ? CupertinoColors.systemRed : _coffeePrimary,
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
                  color: _inkTitle,
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

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  final AddressEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSetDefault;

  @override
  Widget build(BuildContext context) {
    // Shared styles keep the typography tight and ensure there is zero
    // chance of Flutter switching to the default (bright red) accent color.
    final titleStyle = GoogleFonts.poppins(
      fontWeight: FontWeight.w600,
      fontSize: 15,
      color: _inkTitle,
      decoration: TextDecoration.none,
    );
    final bodyStyle = GoogleFonts.poppins(
      fontSize: 13,
      color: _inkBody,
      decoration: TextDecoration.none,
      height: 1.35,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _coffeePrimary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: _inkTitle.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.fullName,
                  style: titleStyle,
                ),
              ),
              Text(
                entry.phoneNumber,
                style: bodyStyle.copyWith(fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.region,
            style: bodyStyle,
          ),
          Text(
            '${entry.street}, ${entry.postalCode}',
            style: bodyStyle,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _badgeAmber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  entry.label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: _badgeAmberText,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (entry.isDefault) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _badgeRose,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Default',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: _badgeRoseText,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onEdit,
                child: Text(
                  'Edit',
                  style: GoogleFonts.poppins(
                    color: _coffeePrimary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onDelete,
                child: Text(
                  'Delete',
                  style: GoogleFonts.poppins(
                    color: CupertinoColors.systemRed,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: onSetDefault == null ? CupertinoColors.systemGrey4 : _coffeePrimary,
                onPressed: onSetDefault,
                child: Text(
                  entry.isDefault ? 'Default' : 'Set as default',
                  style: GoogleFonts.poppins(
                    color: entry.isDefault ? _inkBody.withValues(alpha: 0.7) : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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

  // =============================================================
  // Cascading PH address selection state
  // -------------------------------------------------------------
  // Backed by the same JSON asset used in checkout so we have a
  // single source of truth for Province → City → Barangay.
  // We keep a flat `region` string in `AddressEntry` so existing
  // storage / backend contracts do not change.
  // =============================================================
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
      // Shape:
      // { "Metro Manila": { "Quezon City": ["Bagong Pag-asa", ...] } }
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
      // (format assumed to be "Province, City, Barangay" if present).
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
      color: _inkTitle.withValues(alpha: 0.5),
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
                          GoogleFonts.poppins(color: selected ? Colors.white : _inkTitle, fontSize: 12),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        // Light beige background for cancel button - matches form background
                        color: const Color(0xFFF4E6D4), // Light beige, same as label buttons
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            color: _coffeePrimary, // Brown text to match design system
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        // Primary brown color for submit button - more prominent
                        color: _coffeePrimary,
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
              color: showError ? CupertinoColors.systemRed : _inkTitle,
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

