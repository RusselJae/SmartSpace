import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../models/support_conversation.dart';
import '../../../models/support_message.dart';
import '../../../models/support_form_request.dart';
import '../../../models/order_record.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/admin_support_inbox_navigation_service.dart';
import '../../../utils/file_mime_utils.dart';
import '../../../services/admin_notifications_service.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';
import '../support/support_form_helpers.dart';
import '../support/support_form_submission_dialog.dart';
import '../support/support_quick_actions_sheet.dart';
import '../support/support_conversation_tags.dart';
import '../widgets/admin_anchored_popover.dart';
import '../../../support/support_form_link.dart';
import '../../../widgets/support_message_body.dart';
import '../../../widgets/support_form_card.dart';

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
  final Map<String, String?> _userAvatarById = {};
  final TextEditingController _conversationSearchController = TextEditingController();
  String _conversationSearchQuery = '';

  SupportConversation? _selected;
  List<SupportMessage> _messages = [];
  bool _loadingMessages = false;
  Map<String, SupportFormRequest> _formRequestsById = {};
  OrderRecord? _latestOrder;
  Map<String, String> _productNames = {};
  bool _loadingOrderContext = false;
  bool _savingTags = false;
  List<String> _activeTags = [];
  Timer? _formPollTimer;

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
    _formPollTimer?.cancel();
    _conversationSearchController.dispose();
    super.dispose();
  }

  void _stopFormPolling() {
    _formPollTimer?.cancel();
    _formPollTimer = null;
  }

  void _startFormPolling() {
    _stopFormPolling();
    _formPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshFormRequestsSilent();
    });
  }

  /// Polls form request status so cards flip Pending → Completed without manual refresh.
  Future<void> _refreshFormRequestsSilent() async {
    final conv = _selected;
    if (conv == null || _loadingMessages) return;
    try {
      final forms = await _db.listSupportFormRequestsForConversation(conversationId: conv.id);
      if (!mounted) return;
      setState(() {
        _formRequestsById = {for (final f in forms) f.id: f};
      });
    } catch (_) {
      // Silent — polling should not interrupt the admin.
    }
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _db.initialize();
      final convs = await _db.getSupportConversationsForAdmin();
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

      final pendingUserId = AdminSupportInboxNavigationService.instance.pendingUserId;
      if (pendingUserId != null && pendingUserId.trim().isNotEmpty) {
        AdminSupportInboxNavigationService.instance.pendingUserId = null;
        final target = convs.where((c) => c.userId == pendingUserId).toList();
        if (target.isNotEmpty) {
          await _loadMessages(target.first);
        }
      }
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
      _userAvatarById[id] = user?.avatarUrl;
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

  Widget _userAvatar(String userId, {double radius = 18}) {
    final avatarUrl = _userAvatarById[userId];
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl),
      );
    }
    final initials = _displayNameForUserId(userId).trim();
    final letter = initials.isEmpty ? 'U' : initials[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade300,
      child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
    );
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
      _loadingOrderContext = true;
      _activeTags = List<String>.from(conv.tags);
    });
    try {
      final msgsFuture = _db.getSupportMessagesForAdmin(conversationId: conv.id, limit: 100);
      final formsFuture = _db.listSupportFormRequestsForConversation(conversationId: conv.id);
      final ordersFuture = _db.getAllOrders(forUserId: conv.userId);
      final productsFuture = _db.getAllProducts();

      final msgs = await msgsFuture;
      final forms = await formsFuture;
      final orders = await ordersFuture;
      final products = await productsFuture;

      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final productNameMap = <String, String>{
        for (final p in products) p.id: p.name,
      };
      final formMap = <String, SupportFormRequest>{
        for (final f in forms) f.id: f,
      };

      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _formRequestsById = formMap;
        _latestOrder = orders.isNotEmpty ? orders.first : null;
        _productNames = productNameMap;
        _loadingMessages = false;
        _loadingOrderContext = false;
      });
      _startFormPolling();
      // Mark as read for notification/badge purposes as soon as the admin opens it.
      await _notifications.markConversationRead(conv.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMessages = false;
        _loadingOrderContext = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load messages: $e')),
      );
    }
  }

  Future<void> _saveConversationTags(List<String> tags) async {
    final conv = _selected;
    if (conv == null || _savingTags) return;
    setState(() => _savingTags = true);
    try {
      final updated = await _db.updateSupportConversationTags(
        conversationId: conv.id,
        tags: tags,
      );
      if (!mounted) return;
      setState(() {
        _activeTags = List<String>.from(updated.tags);
        _selected = updated;
        final idx = _conversations.indexWhere((c) => c.id == updated.id);
        if (idx >= 0) {
          _conversations[idx] = updated;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save tags: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingTags = false);
    }
  }

  void _toggleConversationTag(String tag) {
    final next = List<String>.from(_activeTags);
    if (next.contains(tag)) {
      next.remove(tag);
    } else {
      next.add(tag);
    }
    _saveConversationTags(next);
  }

  String _paymentMethodLabel(String? raw) {
    final pm = raw?.trim().toLowerCase() ?? '';
    if (pm.isEmpty) return '—';
    switch (pm) {
      case 'paymongo':
      case 'gcash':
        return 'GCash';
      case 'cod':
        return 'COD';
      default:
        return raw!;
    }
  }

  String _deliveryDateLabel(OrderRecord order) {
    final raw = order.shippingAddress['estimatedDeliveryAt']?.toString();
    if (raw == null || raw.trim().isEmpty) return '—';
    try {
      return DateFormat('MMM d, yyyy', 'en_US').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  Future<void> _sendFormLink(String formType) async {
    final conv = _selected;
    if (conv == null ||
        _adminAuth.adminAccessToken == null ||
        _adminAuth.adminAccessToken!.isEmpty) {
      return;
    }
    if (!isSupportFormAvailable(formType, _latestOrder)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This form does not apply to a cancelled order')),
      );
      return;
    }
    try {
      final result = await _db.sendSupportFormLinkAsAdmin(
        conversationId: conv.id,
        formType: formType,
      );
      if (!mounted) return;

      // Sync auto-tag from backend (also merged locally as fallback).
      final mergedTags = result.conversation != null
          ? List<String>.from(result.conversation!.tags)
          : mergeAutoTag(_activeTags, formType);

      final forms = await _db.listSupportFormRequestsForConversation(conversationId: conv.id);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, result.message];
        _formRequestsById = {for (final f in forms) f.id: f};
        _activeTags = mergedTags;
        _selected = result.conversation ?? _selected?.copyWith(tags: mergedTags) ?? _selected;
        final idx = _conversations.indexWhere((c) => c.id == conv.id);
        if (idx >= 0 && _selected != null) {
          _conversations[idx] = _selected!;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form sent — tag applied automatically')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send form: $e')),
      );
    }
  }

  void _showFormSubmission(SupportFormRequest request) {
    showSupportFormSubmissionDialog(context: context, request: request);
  }

  Future<void> _sendAdminMessage(String body, PlatformFile? attachment) async {
    final conv = _selected;
    if (conv == null ||
        _adminAuth.adminAccessToken == null ||
        _adminAuth.adminAccessToken!.isEmpty) {
      return;
    }
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty && attachment == null) return;

    try {
      final msg = attachment == null
          ? await _db.sendSupportMessageAsAdmin(
              conversationId: conv.id,
              body: trimmedBody,
            )
          : await _db.sendSupportMessageAsAdminWithAttachment(
              conversationId: conv.id,
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

  Widget _buildOrderContextSidebar() {
    if (_loadingOrderContext) {
      return const SizedBox(
        width: 280,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final order = _latestOrder;
    final sidebar = buildSupportOrderSidebar(
      order: order,
      productNames: _productNames,
      formRequests: _formRequestsById.values,
      paymentMethodLabel: _paymentMethodLabel,
      deliveryFromOrder: _deliveryDateLabel,
    );

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Latest order',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (isOrderCancelled(order)) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: Text(
                'Order cancelled',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (order == null)
            Text(
              'No orders on file for this customer.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            )
          else ...[
            _orderContextRow('Order ID', sidebar.orderId),
            _orderContextRow('Status', sidebar.status),
            _orderContextRow('Items', sidebar.items),
            _orderContextRow(
              'Delivery',
              sidebar.delivery,
              hint: sidebar.deliveryFromForm ? 'Updated from form' : null,
            ),
            if (sidebar.address != null)
              _orderContextRow(
                'Address',
                sidebar.address!,
                hint: sidebar.addressFromForm ? 'Updated from form' : null,
              ),
            _orderContextRow('Payment', sidebar.payment),
            _orderContextRow('Total', sidebar.total),
          ],
        ],
      ),
    );
  }

  Widget _orderContextRow(String label, String value, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
              ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: hint,
                  child: Icon(Icons.edit_note, size: 14, color: Colors.green.shade700),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
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
        const SizedBox(height: 8),
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
                return const Center(child: Text('No conversations'));
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _userAvatar(conv.userId),
              const SizedBox(width: 10),
              Expanded(
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
                        Tooltip(
                          message: online ? 'Online' : 'Offline',
                          child: Icon(
                            Icons.circle,
                            size: 10,
                            color: online ? Colors.green[600] : Colors.grey[500],
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
            ],
          ),
        ),
      ),
    );
  }

  String _formatMessageTimestamp(DateTime dt) {
    final local = dt.toLocal();
    return DateFormat('MMM d, h:mm a', 'en_US').format(local);
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Row(
                  children: [
                    _userAvatar(conv.userId, radius: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _displayNameForUserId(conv.userId),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Tooltip(
                      message: _userLikelyOnline(conv) ? 'Customer online' : 'Customer offline',
                      child: Icon(
                        Icons.circle,
                        size: 12,
                        color: _userLikelyOnline(conv) ? Colors.green[600] : Colors.grey[500],
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
              _CompactConversationTagsRow(
                activeTags: _activeTags,
                saving: _savingTags,
                onToggle: _toggleConversationTag,
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
                              final link = SupportFormLink.tryParseFromText(msg.body);
                              final formRequest =
                                  link != null ? _formRequestsById[link.requestId] : null;
                              final isFormCard = SupportFormCard.isFormLinkMessage(msg.body);

                              final bubble = Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: isFormCard
                                    ? const EdgeInsets.all(4)
                                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                constraints: const BoxConstraints(maxWidth: 420),
                                decoration: BoxDecoration(
                                  color: isAdmin ? const Color(0xFF8D6E63) : const Color(0xFFF2F2F7),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: isAdmin ? Colors.white : Colors.black,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                    if (msg.body.trim().isNotEmpty) ...[
                                      if (msg.attachmentUrl != null) const SizedBox(height: 8),
                                      if (isFormCard)
                                        SupportFormCard(
                                          body: msg.body,
                                          sentAt: msg.createdAt,
                                          textColor: isAdmin ? Colors.white : Colors.black87,
                                          backgroundColor: isAdmin
                                              ? Colors.white.withValues(alpha: 0.08)
                                              : Colors.white,
                                          formRequest: formRequest,
                                          isAdminView: true,
                                          onAdminViewSubmission: formRequest != null &&
                                                  formRequest.isSubmitted
                                              ? () => _showFormSubmission(formRequest)
                                              : null,
                                        )
                                      else
                                        SupportMessageBody(
                                          body: msg.body,
                                          textColor: isAdmin ? Colors.white : Colors.black,
                                        ),
                                    ],
                                  ],
                                ),
                              );

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        _formatMessageTimestamp(msg.createdAt),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Colors.grey[600],
                                              fontSize: 11,
                                            ),
                                      ),
                                    ),
                                    Align(
                                      alignment:
                                          isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                                      child: bubble,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              _AdminReplyComposer(
                onSend: _sendAdminMessage,
                onSendFormLink: _sendFormLink,
                latestOrder: _latestOrder,
              ),
            ],
          ),
        ),
        if (MediaQuery.of(context).size.width > 1100) _buildOrderContextSidebar(),
      ],
    );
  }
}

class _AdminReplyComposer extends StatefulWidget {
  const _AdminReplyComposer({
    required this.onSend,
    required this.onSendFormLink,
    required this.latestOrder,
  });

  final Future<void> Function(String body, PlatformFile? attachment) onSend;
  final Future<void> Function(String formType) onSendFormLink;
  final OrderRecord? latestOrder;

  @override
  State<_AdminReplyComposer> createState() => _AdminReplyComposerState();
}

class _AdminReplyComposerState extends State<_AdminReplyComposer> {
  static const int _maxAttachmentBytes = 30 * 1024 * 1024;
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  bool _sendingForm = false;
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
    if (file.bytes!.length > _maxAttachmentBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attachment exceeds 30MB limit')),
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: (_sending || _sendingForm)
                      ? null
                      : () {
                          showSupportQuickActionsSheet(
                            context: context,
                            latestOrder: widget.latestOrder,
                            onQuickReply: (body) {
                              _controller.text = body;
                              _controller.selection = TextSelection.collapsed(
                                offset: _controller.text.length,
                              );
                            },
                            onSendForm: (type) async {
                              setState(() => _sendingForm = true);
                              try {
                                await widget.onSendFormLink(type);
                              } finally {
                                if (mounted) setState(() => _sendingForm = false);
                              }
                            },
                          );
                        },
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Quick actions',
                  color: const Color(0xFF8D6E63),
                ),
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
                const SizedBox(width: 4),
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

/// Shows only applied tags plus a "+" popover for the full tag list.
class _CompactConversationTagsRow extends StatefulWidget {
  const _CompactConversationTagsRow({
    required this.activeTags,
    required this.saving,
    required this.onToggle,
  });

  final List<String> activeTags;
  final bool saving;
  final void Function(String tag) onToggle;

  @override
  State<_CompactConversationTagsRow> createState() => _CompactConversationTagsRowState();
}

class _CompactConversationTagsRowState extends State<_CompactConversationTagsRow> {
  final GlobalKey _addTagAnchorKey = GlobalKey();

  Future<void> _openTagPicker() async {
    await AdminAnchoredPopover.show<void>(
      context: context,
      anchorKey: _addTagAnchorKey,
      width: 280,
      height: 320,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: _TagPickerPanel(
          initialTags: widget.activeTags,
          saving: widget.saving,
          onToggle: widget.onToggle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Tags',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...widget.activeTags.map((tag) {
                  return InputChip(
                    label: Text(tag, style: const TextStyle(fontSize: 12)),
                    avatar: const Icon(Icons.check, size: 16, color: Colors.white),
                    backgroundColor: const Color(0xFF8D6E63),
                    labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white70),
                    onDeleted: widget.saving ? null : () => widget.onToggle(tag),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }),
                if (widget.activeTags.isEmpty)
                  Text(
                    'None',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
          IconButton(
            key: _addTagAnchorKey,
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Manage tags',
            onPressed: widget.saving ? null : _openTagPicker,
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              foregroundColor: const Color(0xFF8D6E63),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagPickerPanel extends StatefulWidget {
  const _TagPickerPanel({
    required this.initialTags,
    required this.saving,
    required this.onToggle,
  });

  final List<String> initialTags;
  final bool saving;
  final void Function(String tag) onToggle;

  @override
  State<_TagPickerPanel> createState() => _TagPickerPanelState();
}

class _TagPickerPanelState extends State<_TagPickerPanel> {
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'Add or remove tags',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            children: kSupportConversationTags.map((tag) {
              final selected = _tags.contains(tag);
              return ListTile(
                dense: true,
                leading: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? const Color(0xFF8D6E63) : Colors.grey,
                  size: 20,
                ),
                title: Text(tag, style: const TextStyle(fontSize: 13)),
                tileColor: selected ? const Color(0xFF8D6E63).withValues(alpha: 0.08) : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                onTap: widget.saving
                    ? null
                    : () {
                        setState(() {
                          if (selected) {
                            _tags.remove(tag);
                          } else {
                            _tags.add(tag);
                          }
                        });
                        widget.onToggle(tag);
                      },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

