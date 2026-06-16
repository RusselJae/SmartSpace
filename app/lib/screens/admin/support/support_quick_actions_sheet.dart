import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/order_record.dart';
import '../../../support/support_form_catalog.dart';
import 'support_form_helpers.dart';
import 'support_quick_replies.dart';

/// Centered modal with Quick Replies and Send Form tabs — replaces cluttered pill rows.
Future<void> showSupportQuickActionsSheet({
  required BuildContext context,
  required OrderRecord? latestOrder,
  required void Function(String replyBody) onQuickReply,
  required Future<void> Function(String formType) onSendForm,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) {
      final cancelled = isOrderCancelled(latestOrder);

      final quickReplies = [
        ...kSupportQuickReplies.where((r) => isQuickReplyAvailable(r, latestOrder)),
        if (cancelled) ...kCancelledOrderQuickReplies,
      ];

      final forms = kSupportFormCatalog
          .where((f) => isSupportFormAvailable(f.type, latestOrder))
          .toList();

      return Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: DefaultTabController(
            length: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
                  child: Row(
                    children: [
                      Text(
                        'Quick actions',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                if (cancelled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade100),
                      ),
                      child: Text(
                        'Latest order is cancelled — delivery and damage forms are hidden. Refund / reorder options are available under Quick Replies.',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange.shade900),
                      ),
                    ),
                  ),
                TabBar(
                  labelColor: const Color(0xFF8D6E63),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF8D6E63),
                  labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Quick Replies'),
                    Tab(text: 'Send Form'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: quickReplies.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final reply = quickReplies[index];
                          return Material(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              title: Text(
                                reply.label,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                reply.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(fontSize: 12, color: Colors.black54),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                onQuickReply(reply.body);
                              },
                            ),
                          );
                        },
                      ),
                      ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: forms.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final def = forms[index];
                          return Material(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF8D6E63).withValues(alpha: 0.12),
                                child: const Icon(Icons.assignment_outlined, color: Color(0xFF8D6E63)),
                              ),
                              title: Text(
                                def.title,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                def.description,
                                style: GoogleFonts.poppins(fontSize: 12, color: Colors.black54),
                              ),
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                await onSendForm(def.type);
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
