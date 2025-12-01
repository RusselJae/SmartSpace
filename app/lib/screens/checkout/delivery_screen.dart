import 'package:flutter/cupertino.dart';

import 'models.dart';
import 'payment_screen.dart';

/// Delivery date & time selection
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.address});
  final AddressData address;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  int _selectedDateIndex = 0;
  int _selectedSlotIndex = 0;

  final List<String> _dates = const ['Oct 10', 'Oct 11', 'Oct 12'];
  final List<String> _slots = const ['10:00-12:00', '12:00-14:00', '16:00-18:00'];

  void _next() {
    final d = DeliveryData(
      dateLabel: _dates[_selectedDateIndex],
      slotLabel: _slots[_selectedSlotIndex],
    );
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => PaymentScreen(address: widget.address, delivery: d)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Delivery')), 
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Choose a date'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List<Widget>.generate(_dates.length, (i) {
                final selected = i == _selectedDateIndex;
                return CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  // Light brown when inactive, normal brown when active
                  color: selected ? const Color(0xFF8D6E63) : const Color(0xFFBCAAA4),
                  onPressed: () => setState(() => _selectedDateIndex = i),
                  child: Text(_dates[i]),
                );
              }),
            ),
            const SizedBox(height: 16),
            const Text('Choose a time slot'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List<Widget>.generate(_slots.length, (i) {
                final selected = i == _selectedSlotIndex;
                return CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  // Light brown when inactive, normal brown when active
                  color: selected ? const Color(0xFF8D6E63) : const Color(0xFFBCAAA4),
                  onPressed: () => setState(() => _selectedSlotIndex = i),
                  child: Text(_slots[i]),
                );
              }),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(onPressed: _next, child: const Text('Continue')),
          ],
        ),
      ),
    );
  }
}


