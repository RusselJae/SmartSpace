import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';
import 'delivery_screen.dart';

/// Address entry screen
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _line1 = TextEditingController();
  final TextEditingController _line2 = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _postal = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  String? _error;

  void _next() {
    setState(() => _error = null);
    if (_name.text.isEmpty || _line1.text.isEmpty || _city.text.isEmpty || _postal.text.isEmpty || _phone.text.isEmpty) {
      setState(() => _error = 'Please fill in all required fields');
      return;
    }

    final address = AddressData(
      fullName: _name.text,
      addressLine1: _line1.text,
      addressLine2: _line2.text.isEmpty ? null : _line2.text,
      city: _city.text,
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
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
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
            _CupertinoField(controller: _name, placeholder: 'Full name *'),
            const SizedBox(height: 12),
            _CupertinoField(controller: _phone, placeholder: 'Phone number *', keyboardType: TextInputType.phone),
            const SizedBox(height: 20),
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
            _CupertinoField(controller: _line1, placeholder: 'Address line 1 *'),
            const SizedBox(height: 12),
            _CupertinoField(controller: _line2, placeholder: 'Address line 2 (optional)'),
            const SizedBox(height: 12),
            _CupertinoField(controller: _city, placeholder: 'City *'),
            const SizedBox(height: 12),
            _CupertinoField(controller: _postal, placeholder: 'Postal code *'),
            const SizedBox(height: 20),
            Text(
              'Summary',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
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
                  _SummaryRow(label: 'Address', value: _line1.text.isEmpty ? '-' : _line1.text),
                  if (_line2.text.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _SummaryRow(label: 'Line 2', value: _line2.text),
                  ],
                  const SizedBox(height: 6),
                  _SummaryRow(label: 'City', value: _city.text.isEmpty ? '-' : _city.text),
                  const SizedBox(height: 6),
                  _SummaryRow(label: 'Postal', value: _postal.text.isEmpty ? '-' : _postal.text),
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
              color: Colors.black,
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
              color: Colors.black,
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


