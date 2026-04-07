import 'dart:async';

import 'package:characters/characters.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/support_conversation.dart';
import '../../models/support_message.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../services/support_notifications_service.dart';
import '../../utils/file_mime_utils.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  static const int _maxAttachmentBytes = 30 * 1024 * 1024;
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AuthService _auth = AuthService();
  final SupportNotificationsService _supportNotifications = SupportNotificationsService.instance;
  final TextEditingController _input = TextEditingController();

  SupportConversation? _conversation;
  List<SupportMessage> _messages = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  int _lastSeenMessageCount = 0;
  PlatformFile? _attachment;
  /// Index of expanded FAQ in modal (-1 = none).
  int _expandedFaqIndex = -1;

  /// FAQs from API, or default list when API unavailable/empty.
  List<Map<String, String>> _faqs = const [
    {'q': 'Where is my order?', 'a': 'You can track your order in the Orders tab. If your status has not changed for over 48 hours, send your order ID and we will check it manually.'},
    {'q': 'How do I request a refund or cancellation?', 'a': 'Send your order ID and reason for refund/cancellation here. Our team will review and respond with next steps.'},
    {'q': 'Can I change my delivery address?', 'a': 'If the order is not yet shipped, we can still update your delivery address. Send your order ID and your updated address.'},
    {'q': 'How can I report a damaged item?', 'a': 'Please attach photos of the damaged item and packaging, and include your order ID so we can help you quickly.'},
  ];

  String _formatTimestamp(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final tod = TimeOfDay.fromDateTime(dt.toLocal());
    return loc.formatTimeOfDay(tod, alwaysUse24HourFormat: false);
  }

  Widget _buildAvatar({
    required bool isMe,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    final user = _auth.currentUser;
    final avatarUrl = user?.avatarUrl;

    if (isMe && avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: backgroundColor,
        backgroundImage: NetworkImage(avatarUrl),
      );
    }

    String fallbackText;
    if (isMe) {
      final base = (user?.fullName.isNotEmpty == true ? user!.fullName : user?.username) ?? 'You';
      fallbackText = base.trim().isNotEmpty ? base.trim().characters.first.toUpperCase() : 'U';
    } else {
      fallbackText = 'A';
    }

    return CircleAvatar(
      radius: 14,
      backgroundColor: backgroundColor,
      child: Text(
        fallbackText,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _input.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initChat() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'You need to be signed in to contact support.';
      });
      return;
    }

    try {
      await _db.initialize();
      // Load FAQs from API in parallel with conversation
      final faqFuture = _db.getFaqs();
      final conv = await _db.getOrCreateSupportConversation(user.id);
      final msgs = await _db.getSupportMessages(conversationId: conv.id, limit: 50);
      final faqs = await faqFuture;
      if (!mounted) return;
      final faqMaps = faqs.isNotEmpty
          ? faqs.map((f) => f.toSupportChatMap()).toList()
          : _faqs; // Keep default if API returned empty
      setState(() {
        _conversation = conv;
        _messages = msgs;
        _faqs = faqMaps;
        _loading = false;
        _lastSeenMessageCount = msgs.length;
      });
      await _supportNotifications.markConversationRead(
        userId: user.id,
        conversationId: conv.id,
        lastMessageAt: conv.lastMessageAt ?? conv.updatedAt,
      );
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load support chat: $e';
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _conversation == null) return;
      try {
        final msgs = await _db.getSupportMessages(
          conversationId: _conversation!.id,
          limit: 50,
        );
        if (!mounted) return;
        // Detect fresh admin replies so we can show a subtle banner/snack
        // instead of silently updating the list – keeps the experience closer
        // to a modern chat app without changing any backend schema.
        final previousCount = _lastSeenMessageCount;
        final newCount = msgs.length;
        final hasNewAdminReply = newCount > previousCount &&
            msgs.isNotEmpty &&
            msgs.last.senderType == 'admin';

        setState(() {
          _messages = msgs;
          _lastSeenMessageCount = newCount;
        });

        if (hasNewAdminReply) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('New reply from support'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        final user = _auth.currentUser;
        final conv = _conversation;
        if (user != null && conv != null) {
          await _supportNotifications.markConversationRead(
            userId: user.id,
            conversationId: conv.id,
            lastMessageAt: conv.lastMessageAt ?? conv.updatedAt,
          );
        }
      } catch (_) {}
    });
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'pdf',
        'txt',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'zip',
        'rar',
      ],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attachment data not available')),
      );
      return;
    }
    if (file.bytes!.length > _maxAttachmentBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attachment exceeds 30MB limit')),
      );
      return;
    }

    setState(() => _attachment = file);
  }

  Future<void> _sendMessage() async {
    final text = _input.text.trim();
    if (_conversation == null || _auth.currentUser == null) return;
    if (text.isEmpty && _attachment == null) return;

    final userId = _auth.currentUser!.id;
    _input.clear();

    final attachment = _attachment;
    setState(() => _attachment = null);

    try {
      final msg = attachment == null
          ? await _db.sendSupportMessageAsUser(
              conversationId: _conversation!.id,
              userId: userId,
              body: text,
            )
          : await _db.sendSupportMessageAsUserWithAttachment(
              conversationId: _conversation!.id,
              userId: userId,
              body: text,
              attachmentBytes: attachment.bytes!,
              fileName: attachment.name ?? 'attachment',
              mimeType: mimeTypeFromFileName(attachment.name, attachment.extension),
            );
      setState(() => _messages = [..._messages, msg]);
    } catch (e) {
      if (!mounted) return;
      if (attachment != null) {
        setState(() => _attachment = attachment);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
    }
  }

  void _useFaqQuestion(String question) {
    _input.text = question;
    _input.selection = TextSelection.fromPosition(
      TextPosition(offset: _input.text.length),
    );
  }

  void _showFaqModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FaqModalSheet(faqs: _faqs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const lightBrown = Color(0xFFF4E6D4);
    const mediumBrown = Color(0xFF8D6E63);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return CupertinoPageScaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        navigationBar: CupertinoNavigationBar(
          backgroundColor: lightBrown,
          border: Border(
            bottom: BorderSide(
              color: mediumBrown.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          leading: CupertinoNavigationBarBackButton(
            color: mediumBrown,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          middle: Text(
            'Support',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: mediumBrown,
            ),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.black87),
              ),
            ),
          ),
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: lightBrown,
        border: Border(
          bottom: BorderSide(
            color: mediumBrown.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        leading: CupertinoNavigationBarBackButton(
          color: mediumBrown,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        middle: Text(
          'Support',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: mediumBrown,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: TextButton.icon(
                  onPressed: _showFaqModal,
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('Show FAQs'),
                ),
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Tell us what you need. This is your direct line to the team.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(color: Colors.grey[600]),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg.senderType == 'user';
                        final bubbleColor =
                            isMe ? mediumBrown : const Color(0xFFF2F2F7);
                        final bubbleTextColor = isMe ? Colors.white : Colors.black;
                        final timeTextColor = Colors.grey[600];
                        final avatarBg = isMe ? mediumBrown : const Color(0xFFB0B0B0);
                        final avatarFg = Colors.white;

                        final bubble = Column(
                          crossAxisAlignment:
                              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: const BoxConstraints(maxWidth: 320),
                              decoration: BoxDecoration(
                                color: bubbleColor,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (msg.attachmentUrl != null)
                                    if (msg.attachmentType == 'image')
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          msg.attachmentUrl!,
                                          width: 220,
                                          height: 160,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              width: 220,
                                              height: 160,
                                              color: Colors.black12,
                                              alignment: Alignment.center,
                                              child: const Icon(Icons.broken_image),
                                            );
                                          },
                                        ),
                                      )
                                    else
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.attach_file, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            msg.attachmentFilename ?? 'Attachment',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: bubbleTextColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                  if (msg.body.trim().isNotEmpty) ...[
                                    if (msg.attachmentUrl != null)
                                      const SizedBox(height: 8),
                                    Text(
                                      msg.body,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: bubbleTextColor,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );

                        final avatar = _buildAvatar(
                          isMe: isMe,
                          backgroundColor: avatarBg,
                          foregroundColor: avatarFg,
                        );

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  _formatTimestamp(context, msg.createdAt),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: timeTextColor,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: isMe
                                    ? [
                                        Flexible(child: bubble),
                                        const SizedBox(width: 8),
                                        avatar,
                                      ]
                                    : [
                                        avatar,
                                        const SizedBox(width: 8),
                                        Flexible(child: bubble),
                                      ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            if (_attachment != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _attachment!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove attachment',
                      onPressed: () => setState(() => _attachment = null),
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.all(8),
                      color: const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(20),
                      onPressed: _pickAttachment,
                      child: const Icon(Icons.attach_file, size: 20, color: Color(0xFF8D6E63)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CupertinoTextField(
                        controller: _input,
                        placeholder: 'Type a message…',
                        placeholderStyle: TextStyle(
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                        minLines: 1,
                        maxLines: 4,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: const EdgeInsets.all(8),
                      color: mediumBrown,
                      borderRadius: BorderRadius.circular(20),
                      onPressed: _sendMessage,
                      child: const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// FAQ modal sheet with accordion-style expand/collapse.
class _FaqModalSheet extends StatefulWidget {
  const _FaqModalSheet({required this.faqs});

  final List<Map<String, String>> faqs;

  @override
  State<_FaqModalSheet> createState() => _FaqModalSheetState();
}

class _FaqModalSheetState extends State<_FaqModalSheet> {
  int _expandedIndex = -1;

  static const _mediumBrown = Color(0xFF8D6E63);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 18, color: _mediumBrown),
                  const SizedBox(width: 8),
                  Text(
                    'FAQs',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: _mediumBrown,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: widget.faqs.length,
                itemBuilder: (context, index) {
                  final item = widget.faqs[index];
                  final isExpanded = _expandedIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBF7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _mediumBrown.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _expandedIndex = isExpanded ? -1 : index;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item['q']!,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  AnimatedRotation(
                                    turns: isExpanded ? 0.5 : 0,
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      Icons.expand_more,
                                      size: 20,
                                      color: _mediumBrown,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                              child: Text(
                                item['a']!,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.black87,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            crossFadeState: isExpanded
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 200),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

