import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Surfaces and building blocks aligned with [AdminProfilePage]: cream shell,
/// white elevated panels, walnut typography, left-aligned headers.
class AdminConsoleSurfaces {
  AdminConsoleSurfaces._();

  /// Same cream as the full-screen admin profile scaffold.
  static const Color cream = Color(0xFFFFFBF7);

  /// Primary brown for headings and key values (profile “Details” / legal name).
  static const Color walnutText = Color(0xFF5C4033);

  /// Accent for controls and focus rings.
  static const Color accentBrown = Color(0xFF8D6E63);

  static const double detailCardRadius = 24;

  static const EdgeInsets detailCardPadding = EdgeInsets.fromLTRB(22, 20, 22, 22);

  /// White panel: light border + soft shadow (reads closer to profile cards than flat grey).
  static BoxDecoration profilePanelDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(detailCardRadius),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  /// Backwards-compatible name used across admin orders / quote flows.
  static BoxDecoration detailCardDecoration() => profilePanelDecoration();

  static Widget detailCard({required Widget child}) {
    return Container(
      decoration: profilePanelDecoration(),
      padding: detailCardPadding,
      alignment: Alignment.topLeft,
      child: DefaultTextStyle.merge(
        textAlign: TextAlign.start,
        child: child,
      ),
    );
  }
}

/// One label/value block matching profile rows (grey caption, walnut value).
class AdminProfileStyleDetailRow extends StatelessWidget {
  const AdminProfileStyleDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.fontSize = 15,
    this.dense = false,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final double fontSize;
  final bool dense;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final vPad = dense ? 8.0 : 12.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: vPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value.trim(),
                style: GoogleFonts.poppins(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: AdminConsoleSurfaces.walnutText,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      ],
    );
  }
}

/// Modal shell: cream frame, profile-like header (title + subtitle left, optional
/// trailing e.g. avatar, close), divider, then scrollable or expanding body.
class AdminProfileStyleDetailDialog extends StatelessWidget {
  const AdminProfileStyleDetailDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.headerTrailing,
    required this.body,
    this.bodyExpands = false,
    this.maxWidth = 760,
    this.maxHeight = 820,
  });

  final String title;
  final String? subtitle;
  final Widget? headerTrailing;
  final Widget body;
  final bool bodyExpands;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          color: AdminConsoleSurfaces.cream,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 4, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AdminConsoleSurfaces.walnutText,
                              height: 1.2,
                            ),
                          ),
                          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle!,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (headerTrailing != null) ...[
                      const SizedBox(width: 10),
                      headerTrailing!,
                    ],
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: AdminConsoleSurfaces.walnutText,
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
              if (bodyExpands)
                Expanded(child: body)
              else
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                    child: body,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
