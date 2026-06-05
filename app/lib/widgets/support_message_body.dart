import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/support/support_form_fill_screen.dart';
import '../support/support_form_link.dart';

/// Renders support message text with tappable form links when present.
class SupportMessageBody extends StatelessWidget {
  const SupportMessageBody({
    super.key,
    required this.body,
    required this.textColor,
  });

  final String body;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final link = SupportFormLink.tryParseFromText(body);
    if (link == null) {
      return Text(
        body,
        style: TextStyle(color: textColor),
      );
    }

    final lines = body.split('\n');
    final children = <InlineSpan>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineLink = SupportFormLink.tryParseFromText(line);
      if (lineLink != null) {
        children.add(
          TextSpan(
            text: 'Open form',
            style: GoogleFonts.poppins(
              color: textColor,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: textColor,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SupportFormFillScreen(
                      formType: lineLink.formType,
                      requestId: lineLink.requestId,
                    ),
                  ),
                );
              },
          ),
        );
      } else if (line.trim().isNotEmpty) {
        children.add(TextSpan(text: line, style: TextStyle(color: textColor)));
      }
      if (i < lines.length - 1) {
        children.add(const TextSpan(text: '\n'));
      }
    }

    return RichText(text: TextSpan(children: children));
  }
}
