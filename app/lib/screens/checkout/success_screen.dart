import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../shell/tab_shell.dart';

/// Order confirmation (thank-you or PayMongo cancel).
class SuccessScreen extends StatelessWidget {
  const SuccessScreen({
    super.key,
    /// When set (e.g. PayMongo test flow), replaces the default body copy.
    this.subtitle,
    /// After PayMongo cancel redirect — neutral screen (not “Thank you”).
    this.paymentCancelled = false,
    /// When set, enables "View invoice" + "Download" actions.
    this.invoiceOrderId,
    /// Optional override. When omitted, the current signed-in user is used.
    this.invoiceUserId,
  });

  /// Optional second line under the title (e.g. PayMongo instructions).
  final String? subtitle;

  final bool paymentCancelled;

  final String? invoiceOrderId;
  final String? invoiceUserId;

  Future<void> _openInvoice(BuildContext context, {required bool download}) async {
    final orderId = invoiceOrderId;
    if (orderId == null || orderId.trim().isEmpty) return;

    final auth = AuthService();
    final userId = (invoiceUserId ?? auth.currentUser?.id)?.trim();
    if (userId == null || userId.isEmpty) return;

    final db = MySQLDatabaseService();
    final url = db.getOrderInvoiceUrl(orderId: orderId.trim(), userId: userId);
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    await launchUrl(
      uri,
      mode: download ? LaunchMode.externalApplication : LaunchMode.inAppWebView,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSubtitle = subtitle ??
        'Your order has been confirmed and will be processed shortly.';
    final canShowInvoice =
        !paymentCancelled && (invoiceOrderId != null && invoiceOrderId!.trim().isNotEmpty);

    return CupertinoPageScaffold(
      // Match the screenshot: no top nav chrome; just the success card centered.
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      paymentCancelled
                          ? CupertinoIcons.xmark_circle
                          : CupertinoIcons.check_mark_circled,
                      size: 82,
                      color: paymentCancelled
                          ? const Color(0xFFC62828)
                          : CupertinoColors.activeGreen,
                    ),
                    const SizedBox(height: 10),

                    Text(
                      paymentCancelled ? 'Checkout cancelled' : 'Thank You!',
                      style: paymentCancelled
                          ? GoogleFonts.poppins(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              decoration: TextDecoration.none,
                            )
                          : GoogleFonts.dancingScript(
                              fontSize: 44,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                              decoration: TextDecoration.none,
                            ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 10),

                    // Small "processing" illustration (store + arrow).
                    SizedBox(
                      height: 68,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 2,
                            child: Icon(
                              Icons.arrow_drop_down,
                              size: 28,
                              color: Colors.black.withValues(alpha: 0.7),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            child: Icon(
                              Icons.storefront_outlined,
                              size: 46,
                              color: Colors.black.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Body copy under the illustration.
                    Text(
                      effectiveSubtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF5F5B56),
                        decoration: TextDecoration.none,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 22),

                    if (canShowInvoice) ...[
                      SizedBox(
                        width: 240,
                        child: ElevatedButton(
                          onPressed: () => _openInvoice(context, download: false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5C4033),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'View invoice',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => _openInvoice(context, download: true),
                        child: Text(
                          'Download invoice',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: const Color(0xFF5C4033),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Screenshot-like pill button.
                    SizedBox(
                      width: 190,
                      child: ElevatedButton(
                        onPressed: () {
                          // Preserve existing behavior: go back to the app's home shell.
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).popUntil((route) => route.isFirst);
                          } else {
                            Navigator.of(context, rootNavigator: true)
                                .pushNamedAndRemoveUntil(
                              TabShell.route,
                              (route) => false,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5EFEA),
                          foregroundColor: const Color(0xFF5C4033),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: const BorderSide(
                              color: Color(0xFFE2D6CC),
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Back to Home',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


