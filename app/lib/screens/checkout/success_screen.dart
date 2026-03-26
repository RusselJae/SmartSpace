import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../shell/tab_shell.dart';

/// Order confirmation
class SuccessScreen extends StatelessWidget {
  const SuccessScreen({
    super.key,
    /// When set (e.g. PayMongo test flow), replaces the default body copy.
    this.subtitle,
  });

  /// Optional second line under the title (e.g. PayMongo instructions).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          'Order Placed',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.check_mark_circled_solid,
                size: 80,
                color: CupertinoColors.activeGreen,
              ),
              const SizedBox(height: 24),
              Text(
                'Thanks for your order!',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                subtitle ??
                    'Your order has been confirmed and will be processed shortly.',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black,
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              CupertinoButton.filled(
                onPressed: () {
                  // Check if we can pop before trying to navigate
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  } else {
                    // If we can't pop, navigate to home using root navigator
                    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
                      TabShell.route,
                      (route) => false,
                    );
                  }
                },
                child: Text(
                  'Back to Home',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


