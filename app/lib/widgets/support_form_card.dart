import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/support_form_request.dart';
import '../screens/support/support_form_fill_screen.dart';
import '../support/support_form_catalog.dart';
import '../support/support_form_link.dart';

/// Compact card for support form links — replaces long boilerplate chat bubbles.
class SupportFormCard extends StatelessWidget {
  const SupportFormCard({
    super.key,
    required this.body,
    required this.sentAt,
    required this.textColor,
    this.backgroundColor,
    this.formRequest,
    this.isAdminView = false,
    this.onAdminViewSubmission,
  });

  final String body;
  final DateTime sentAt;
  final Color textColor;
  final Color? backgroundColor;
  final SupportFormRequest? formRequest;
  final bool isAdminView;
  final VoidCallback? onAdminViewSubmission;

  static bool isFormLinkMessage(String body) =>
      SupportFormLink.tryParseFromText(body) != null;

  String _statusLabel() {
    if (formRequest?.isSubmitted == true) return 'Completed';
    if (formRequest != null) return 'Pending';
    return 'Sent';
  }

  /// Solid badge colors so status stays readable on brown admin bubbles.
  Color _statusBackground() {
    switch (_statusLabel()) {
      case 'Completed':
        return const Color(0xFF2E7D32);
      case 'Pending':
        return const Color(0xFFE65100);
      default:
        return const Color(0xFF1565C0);
    }
  }

  void _handleTap(BuildContext context, SupportFormLink link) {
    if (isAdminView && formRequest?.isSubmitted == true) {
      onAdminViewSubmission?.call();
      return;
    }
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportFormFillScreen(
          formType: link.formType,
          requestId: link.requestId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = SupportFormLink.tryParseFromText(body);
    if (link == null) {
      return Text(body, style: TextStyle(color: textColor));
    }

    final def = supportFormDefForType(link.formType);
    final title = def?.title ?? link.formType.replaceAll('_', ' ');
    final timeLabel = DateFormat('MMM d, h:mm a', 'en_US').format(sentAt.toLocal());
    final statusLabel = _statusLabel();
    final statusBg = _statusBackground();
    // Admin bubbles use a near-white inner card so title + badge stay legible.
    final cardBg = isAdminView
        ? Colors.white
        : (backgroundColor ?? Colors.white);
    final titleColor = isAdminView ? const Color(0xFF3E2723) : textColor;
    final metaColor = isAdminView ? Colors.black54 : textColor.withValues(alpha: 0.75);
    final actionColor = isAdminView ? const Color(0xFF8D6E63) : textColor;
    final completed = formRequest?.isSubmitted == true;
    final actionLabel = isAdminView && completed
        ? 'View responses'
        : completed
            ? 'View form'
            : 'Open form';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context, link),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isAdminView ? Colors.grey.shade300 : textColor.withValues(alpha: 0.2),
            ),
            boxShadow: isAdminView
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.assignment_outlined, size: 18, color: titleColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.poppins(
                        color: titleColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      statusLabel,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                completed && formRequest?.submittedAt != null
                    ? 'Completed · ${DateFormat('MMM d, h:mm a', 'en_US').format(formRequest!.submittedAt!.toLocal())}'
                    : 'Sent · $timeLabel',
                style: GoogleFonts.poppins(
                  color: metaColor,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                actionLabel,
                style: GoogleFonts.poppins(
                  color: actionColor,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: actionColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
