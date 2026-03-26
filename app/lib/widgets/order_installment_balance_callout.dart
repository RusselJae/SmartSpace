import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/order_record.dart';
import '../utils/order_payment_balance.dart';

/// Apple-style grouped callout: remaining balance + countdown to late-fee window.
///
/// Shown only for PayMongo **down payment** orders that still owe a balance.
class OrderInstallmentBalanceCallout extends StatelessWidget {
  const OrderInstallmentBalanceCallout({
    super.key,
    required this.order,
    this.accentColor = const Color(0xFF5C4033),
    this.backgroundColor,
    /// When false, hides the bold “Remaining balance” row (e.g. order cards
    /// that already print balance above); keeps the **0% window** countdown only.
    this.showAmountLine = true,
  });

  final OrderRecord order;
  final Color accentColor;
  final Color? backgroundColor;
  final bool showAmountLine;

  @override
  Widget build(BuildContext context) {
    if (!shouldShowInstallmentBalanceUi(order)) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final line = installmentInterestCountdownLine(order, now);
    final bg = backgroundColor ?? accentColor.withValues(alpha: 0.08);

    // Avoid an empty tinted box when the card already shows the peso amount elsewhere.
    if (!showAmountLine && line.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAmountLine)
            Row(
              children: [
                Icon(CupertinoIcons.money_dollar_circle, size: 18, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Remaining balance: ${formatRemainingBalancePesos(order)}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          if (line.isNotEmpty) ...[
            if (showAmountLine) const SizedBox(height: 8),
            Text(
              line,
              style: GoogleFonts.poppins(
                fontSize: 12,
                height: 1.35,
                color: accentColor.withValues(alpha: 0.92),
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
