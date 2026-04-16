import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/customer_notification.dart';
import '../../services/customer_notifications_service.dart';

class NotificationsCenterScreen extends StatefulWidget {
  const NotificationsCenterScreen({super.key});

  static const String route = '/notifications-center';

  @override
  State<NotificationsCenterScreen> createState() => _NotificationsCenterScreenState();
}

class _NotificationsCenterScreenState extends State<NotificationsCenterScreen> {
  final CustomerNotificationsService _service = CustomerNotificationsService.instance;

  @override
  void initState() {
    super.initState();
    _service.startPolling(interval: const Duration(seconds: 15));
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'new_arrival':
        return CupertinoIcons.sparkles;
      case 'admin_message':
        return CupertinoIcons.chat_bubble_2_fill;
      case 'terms_update':
        return CupertinoIcons.doc_text_fill;
      default:
        return CupertinoIcons.bell_fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: const Color(0xFF5C4033),
        ),
        middle: Text('Notifications', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _service.markAllRead,
          child: Text('Mark all', style: GoogleFonts.poppins(fontSize: 13)),
        ),
      ),
      child: SafeArea(
        child: ValueListenableBuilder<List<CustomerNotification>>(
          valueListenable: _service.notifications,
          builder: (context, items, _) {
            if (items.isEmpty) {
              return Center(
                child: Text('No notifications yet.', style: GoogleFonts.poppins()),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final item = items[index];
                return GestureDetector(
                  onTap: () => _service.markRead(item.id),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: item.isRead ? const Color(0xFFF7F7F7) : const Color(0xFFF4E6D4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD7CCC8)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_iconForType(item.type), color: const Color(0xFF5C4033)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(item.body, style: GoogleFonts.poppins(fontSize: 12)),
                              const SizedBox(height: 6),
                              Text(
                                item.createdAt.toLocal().toString(),
                                style: GoogleFonts.poppins(fontSize: 11, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: items.length,
            );
          },
        ),
      ),
    );
  }
}

