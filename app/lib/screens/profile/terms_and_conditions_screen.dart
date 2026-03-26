import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/mysql_database_service.dart';
import '../../widgets/legal_content_renderer.dart';

/// Formal Terms & Conditions screen.
///
/// Loads content from the backend when available. Falls back to built-in
/// default when no custom content is set.
class TermsAndConditionsScreen extends StatefulWidget {
  const TermsAndConditionsScreen({super.key});

  static const String route = '/terms-and-conditions';

  @override
  State<TermsAndConditionsScreen> createState() => _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  String? _customContent;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      await _db.initialize();
      final content = await _db.getLegalContent('terms');
      if (!mounted) return;
      setState(() {
        _customContent = (content != null && content.trim().isNotEmpty) ? content : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const mediumBrown = Color(0xFF8D6E63);
    const dividerColor = Color(0xFFE0D4C8);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFFF4E6D4),
        border: const Border(
          bottom: BorderSide(
            color: Color(0x338D6E63),
            width: 0.5,
          ),
        ),
        leading: CupertinoNavigationBarBackButton(
          color: mediumBrown,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        middle: Text(
          'Terms & Conditions',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: mediumBrown,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFFBF7), Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.3],
            ),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _customContent != null
                  ? LegalContentRenderer(
                      content: _customContent!,
                      dividerColor: dividerColor,
                    )
                  : ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _sectionTitle('About SmartSpace'),
              const SizedBox(height: 6),
              _bodyText(
                'SmartSpace provides made‑to‑order and on‑hand furniture for personal and commercial use. '
                'By placing an order through the app, you confirm that you have read, understood, and agreed '
                'to these Terms & Conditions.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('1. Orders & Product Information'),
              const SizedBox(height: 6),
              _bullet(
                'Product details (sizes, materials, finishes, photos) are provided as accurately as possible. '
                'Minor variations in color, grain, and texture are normal for wood and handcrafted items.',
              ),
              _bullet(
                'If you provide your own measurements, you are responsible for accuracy. We build based on the '
                'approved specifications shown in your order summary.',
              ),
              _bullet(
                'Your order is considered confirmed once the required down payment has been received and you have '
                'reviewed the final order details in the app.',
              ),
              _bullet(
                'Where the app allows approvals (final dimensions, finish, and delivery details), your confirmation '
                'is treated as authorization to proceed.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('2. Payment Terms'),
              const SizedBox(height: 6),
              _label('Made to Order (Custom Items)'),
              _bullet('Down payment: ₱3,000 – ₱5,000 (non‑refundable).'),
              _bullet('Balance: payable upon delivery.'),
              const SizedBox(height: 10),
              _label('Installment / Lay‑Away Plan (3 Months)'),
              _bullet('Available for both on‑hand and made‑to‑order items.'),
              _bullet('Down payment: ₱3,000 – ₱5,000.'),
              _bullet('0% interest if fully paid within 3 months.'),
              _bullet('Requirement: 1 valid ID.'),
              _bullet('Delivery: item will be delivered once fully paid.'),
              _bullet('Late payment: items not paid within 3 months will incur a warehouse fee of ₱100/day.'),
              const SizedBox(height: 10),
              _label('On‑Hand Installment (Quick Delivery)'),
              _bullet('Down payment: 40% upfront.'),
              _bullet('Interest: 6% total interest.'),
              _bullet('Delivery: 10–12 days (delivery fees apply).'),
              _bullet(
                'Any bank transfer fees, payment processor fees, or similar charges are the responsibility of the customer unless stated otherwise.',
              ),
              _bullet(
                'Prices, fees, and schedules may be updated from time to time. The amount shown in your order summary at checkout is the amount that applies to your order.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('3. Production Timeline (Made to Order)'),
              const SizedBox(height: 6),
              _bodyText('Typical lead time is 6–7 weeks from confirmation of your down payment:'),
              const SizedBox(height: 6),
              _bullet('Week 1: wood treatment (anti‑pest / anti‑termite).'),
              _bullet('Weeks 2–6: item production.'),
              _bullet('Week 7: refurbishing and delivery scheduling.'),
              _bullet(
                'Timelines may shift due to weather, materials availability, or logistics. '
                'Any significant delay will be communicated to you.',
              ),
              _bullet(
                'Made‑to‑order timelines are estimates. SmartSpace is not liable for delays caused by events outside reasonable control (including supplier disruptions, weather, and transport constraints).',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('4. Down Payments & Cancellations'),
              const SizedBox(height: 6),
              _bullet(
                'Down payments for made‑to‑order and installment plans are non‑refundable, '
                'as materials and labor are reserved specifically for your order.',
              ),
              _bullet(
                'If you cancel a made‑to‑order item after payment, the down payment is forfeited.',
              ),
              _bullet(
                'Cancellations on installment/lay‑away items may result in storage and handling charges, depending on how long the item has been reserved.',
              ),
              _bullet(
                'If we are unable to fulfill your order and no reasonable alternative is acceptable, '
                'we will refund any payment collected for that order.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('5. Delivery & Acceptance'),
              const SizedBox(height: 6),
              _bullet('Delivery scheduling is coordinated with you based on your location and availability.'),
              _bullet('Delivery fees apply where applicable and are shown/confirmed before finalizing.'),
              _bullet(
                'Please inspect your item upon delivery. Marking the order as received means the item '
                'was delivered in acceptable condition, except for hidden defects not visible at the time.',
              ),
              _bullet(
                'You are responsible for ensuring the delivery location is accessible and that the item can fit through doorways, hallways, elevators, and stairwells. Additional handling may incur extra charges.',
              ),
              _bullet(
                'If delivery fails due to incorrect address, no recipient available, or access issues, delivery may be rescheduled and additional fees may apply.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('6. Quality & Security Guarantee'),
              const SizedBox(height: 6),
              _bullet('Quality assurance: every item undergoes a quality check before release.'),
              _bullet(
                'Secure transactions: you may visit our shop for walk‑in viewing, or request a video call '
                'with our staff to inspect items before sending your down payment.',
              ),
              _bullet(
                'If a manufacturing defect is discovered, contact support promptly with photos and order details so we can assess and arrange an appropriate remedy.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('7. Returns, Repairs & Warranty'),
              const SizedBox(height: 6),
              _bullet(
                'Made‑to‑order items are not eligible for returns due to change of mind.',
              ),
              _bullet(
                'For on‑hand items, returns or exchanges (if offered) are subject to inspection and approval. Items must be in the same condition as delivered.',
              ),
              _bullet(
                'For issues related to damage on delivery or clear manufacturing defects, report the concern as soon as possible through in‑app support and provide photos for assessment.',
              ),
              _bullet(
                'Warranty coverage, if any, is described on the product listing. Warranty does not cover misuse, accidents, exposure to moisture/heat beyond normal use, unauthorized repairs, or normal wear and tear.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('8. Customer Responsibilities'),
              const SizedBox(height: 6),
              _bullet(
                'You agree to provide accurate contact information and delivery details.',
              ),
              _bullet(
                'You agree to respond reasonably to scheduling messages to avoid delays in delivery and handover.',
              ),
              _bullet(
                'You agree not to misuse the Service or attempt to interfere with app operations.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('9. Changes to These Terms'),
              const SizedBox(height: 6),
              _bullet(
                'SmartSpace may update these Terms & Conditions from time to time. Updated terms will be posted in the app and apply going forward.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('10. Contact'),
              const SizedBox(height: 6),
              _bullet(
                'For questions, disputes, or support requests, contact SmartSpace through the in‑app support page and provide your Order ID when available.',
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF8D6E63),
      ),
    );
  }

  static Widget _bodyText(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 14,
        color: Colors.black87,
        height: 1.4,
      ),
    );
  }

  static Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  static Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14, height: 1.4)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

