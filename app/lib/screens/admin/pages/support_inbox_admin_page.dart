import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/support_conversation.dart';
import '../../../models/support_message.dart';
import '../../../services/admin_auth_service.dart';
import '../../../utils/file_mime_utils.dart';
import '../../../services/admin_notifications_service.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';

class SupportInboxAdminPage extends StatefulWidget {
  const SupportInboxAdminPage({super.key});

  @override
  State<SupportInboxAdminPage> createState() => _SupportInboxAdminPageState();
}

class _SupportInboxAdminPageState extends State<SupportInboxAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AdminAuthService _adminAuth = AdminAuthService();
  final AdminNotificationsService _notifications = AdminNotificationsService.instance;

  bool _loading = true;
  String? _error;
  List<SupportConversation> _conversations = [];
  final Map<String, String> _userNameById = {};
  final TextEditingController _conversationSearchController = TextEditingController();
  String _conversationSearchQuery = '';

  SupportConversation? _selected;
  List<SupportMessage> _messages = [];
  bool _loadingMessages = false;

  SharedPreferences? _prefs;
  String? _adminId;

  @override
  void initState() {
    super.initState();
    _conversationSearchController.addListener(() {
      final next = _conversationSearchController.text.trim().toLowerCase();
      if (next == _conversationSearchQuery) return;
      setState(() => _conversationSearchQuery = next);
    });
    _primeUnreadContext();
    _loadConversations();
  }

  /// Loads prefs + admin id so per-row unread dots match [AdminNotificationsService] rules.
  Future<void> _primeUnreadContext() async {
    await _adminAuth.initialize();
    if (!mounted) return;
    _adminId = _adminAuth.currentAdminId ?? _adminAuth.currentEmail;
    _prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _conversationSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _db.initialize();
      final convs = await _db.getSupportConversationsForAdmin(status: 'open');
      if (!mounted) return;
      setState(() {
        _conversations = convs;
        _loading = false;
        if (_selected != null) {
          _selected =
              convs.firstWhere((c) => c.id == _selected!.id, orElse: () => _selected!);
        }
      });

      await _primeUserNames(convs);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load conversations: $e';
      });
    }
  }

  Future<void> _primeUserNames(List<SupportConversation> convs) async {
    final missingIds = convs
        .map((c) => c.userId)
        .where((id) => id.trim().isNotEmpty && !_userNameById.containsKey(id))
        .toSet()
        .toList();

    if (missingIds.isEmpty) return;

    final futures = missingIds.map((id) async {
      final user = await _db.getUserById(id);
      final name = (user?.fullName ?? '').trim();
      if (name.isNotEmpty) {
        _userNameById[id] = name;
      }
    });

    await Future.wait(futures);
    if (!mounted) return;
    setState(() {});
  }

  String _displayNameForUserId(String userId) {
    final name = _userNameById[userId];
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return userId;
  }

  /// Recent activity within this window is treated as "online" (no realtime presence API).
  bool _userLikelyOnline(SupportConversation conv) {
    final t = conv.lastMessageAt ?? conv.updatedAt;
    return DateTime.now().difference(t) <= const Duration(minutes: 3);
  }

  bool _conversationShowsUnread(SupportConversation conv) {
    final prefs = _prefs;
    final adminId = _adminId;
    if (prefs == null || adminId == null || adminId.trim().isEmpty) return false;
    return AdminNotificationsService.computeConversationUnread(conv, prefs, adminId);
  }

  Future<void> _loadMessages(SupportConversation conv) async {
    setState(() {
      _selected = conv;
      _loadingMessages = true;
    });
    try {
      final msgs = await _db.getSupportMessagesForAdmin(conversationId: conv.id, limit: 100);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loadingMessages = false;
      });
      // Mark as read for notification/badge purposes as soon as the admin opens it.
      await _notifications.markConversationRead(conv.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMessages = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load messages: $e')),
      );
    }
  }

  Future<void> _sendAdminMessage(String body, PlatformFile? attachment) async {
    final conv = _selected;
    final adminId = _adminAuth.currentAdminId;
    if (conv == null || adminId == null) return;
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty && attachment == null) return;

    try {
      final msg = attachment == null
          ? await _db.sendSupportMessageAsAdmin(
              conversationId: conv.id,
              adminId: adminId,
              body: trimmedBody,
            )
          : await _db.sendSupportMessageAsAdminWithAttachment(
              conversationId: conv.id,
              adminId: adminId,
              body: trimmedBody,
              attachmentBytes: attachment.bytes!,
              fileName: attachment.name.isNotEmpty ? attachment.name : 'attachment',
              mimeType: mimeTypeFromFileName(attachment.name, attachment.extension),
            );
      if (!mounted) return;
      setState(() => _messages = [..._messages, msg]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Column(
        children: [
          const AdminToolbar(title: 'Support Inbox', actions: []),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _loadConversations, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final wide = MediaQuery.of(context).size.width > 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminToolbar(
          title: 'Support Inbox',
          actions: [],
        ),
        Expanded(
          child: wide
              ? Row(
                  children: [
                    SizedBox(
                      width: 340,
                      child: _buildConversationList(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildConversationDetail()),
                  ],
                )
              : _selected == null
                  ? _buildConversationList()
                  : _buildConversationDetail(),
        ),
      ],
    );
  }

  Widget _buildConversationList() {
    final filteredConversations = _conversations.where((conv) {
      if (_conversationSearchQuery.isEmpty) return true;
      final name = _displayNameForUserId(conv.userId).toLowerCase();
      final preview = (conv.lastMessagePreview ?? '').toLowerCase();
      final userId = conv.userId.toLowerCase();
      return name.contains(_conversationSearchQuery) ||
          preview.contains(_conversationSearchQuery) ||
          userId.contains(_conversationSearchQuery);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Conversations',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            controller: _conversationSearchController,
            decoration: InputDecoration(
              hintText: 'Search user',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _conversationSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _conversationSearchController.clear(),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.brown.shade300, width: 1.2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<AdminNotificationSnapshot>(
            valueListenable: _notifications.snapshot,
            builder: (context, _, __) {
              if (filteredConversations.isEmpty) {
                return const Center(child: Text('No open conversations'));
              }
              return ListView.separated(
                itemCount: filteredConversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final conv = filteredConversations[index];
                  final selected = _selected?.id == conv.id;
                  return _buildConversationRow(conv, selected);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Name on top, last message below; online/offline on the right; red dot when unread.
  Widget _buildConversationRow(SupportConversation conv, bool selected) {
    final name = _displayNameForUserId(conv.userId);
    final preview = conv.lastMessagePreview?.trim().isNotEmpty == true
        ? conv.lastMessagePreview!.trim()
        : 'No messages yet';
    final unread = _conversationShowsUnread(conv);
    final online = _userLikelyOnline(conv);

    return Material(
      color: selected ? Colors.grey.shade100 : Colors.transparent,
      child: InkWell(
        onTap: () => _loadMessages(conv),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[900],
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    online ? 'online' : 'offline',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: online ? Colors.green[700] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (unread)
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 8),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: unread ? Colors.grey[900] : Colors.grey[700],
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            height: 1.35,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationDetail() {
    final conv = _selected;

    if (conv == null) {
      return Center(
        child: Text(
          'Select a conversation to reply.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
      );
    }

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  _displayNameForUserId(conv.userId),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                _userLikelyOnline(conv) ? 'online' : 'offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _userLikelyOnline(conv) ? Colors.green[700] : Colors.grey[600],
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadingMessages ? null : () => _loadMessages(conv),
            tooltip: 'Refresh conversation',
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loadingMessages
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const Center(child: Text('No messages yet'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isAdmin = msg.senderType == 'admin';
                        return Align(
                          alignment:
                              isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            constraints: const BoxConstraints(maxWidth: 420),
                            decoration: BoxDecoration(
                              color: isAdmin
                                  ? const Color(0xFF8D6E63)
                                  : const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: isAdmin
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
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
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color:
                                                    isAdmin ? Colors.white : Colors.black,
                                                fontWeight: FontWeight.w600,
                                              ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                if (msg.body.trim().isNotEmpty) ...[
                                  if (msg.attachmentUrl != null) const SizedBox(height: 8),
                                  Text(
                                    msg.body,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: isAdmin ? Colors.white : Colors.black,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        _AdminReplyComposer(onSend: _sendAdminMessage),
      ],
    );
  }
}

class _AdminReplyComposer extends StatefulWidget {
  const _AdminReplyComposer({required this.onSend});

  final Future<void> Function(String body, PlatformFile? attachment) onSend;

  @override
  State<_AdminReplyComposer> createState() => _AdminReplyComposerState();
}

class _AdminReplyComposerState extends State<_AdminReplyComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  PlatformFile? _attachment;

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attachment data not available')),
      );
      return;
    }

    setState(() => _attachment = file);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachment == null) return;
    if (_sending) return;

    setState(() => _sending = true);
    try {
      await widget.onSend(text, _attachment);
      _controller.clear();
      setState(() => _attachment = null);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachment != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _attachment!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Reply to customer…',
                      filled: true,
                      fillColor: const Color(0xFFF8F8F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _pickAttachment,
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'Attach file',
                ),
                FilledButton(
                  onPressed: _sending ? null : _handleSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8D6E63),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

