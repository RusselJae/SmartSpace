import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../../../models/admin_activity_log.dart';
import '../../../models/admin.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/admin_notifications_service.dart';
import '../../../services/mysql_database_service.dart';
import '../../../utils/report_file_saver.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  static const String title = 'Notifications';

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final AdminNotificationsService _service = AdminNotificationsService.instance;
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AdminAuthService _adminAuth = AdminAuthService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final ValueNotifier<String> _broadcastType = ValueNotifier<String>(
    'maintenance_alert',
  );
  final TextEditingController _logSearchController = TextEditingController();
  List<AdminActivityLog> _activityLogs = const [];
  List<Admin> _admins = const [];
  String _logActionFilter = 'all';
  String _logAdminFilter = 'all';
  DateTime? _logDateFrom;
  DateTime? _logDateTo;
  bool _exportingLogs = false;
  bool _sending = false;
  bool _loadingLogs = false;

  String _relativeDay(DateTime when) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfTarget = DateTime(when.year, when.month, when.day);
    final diff = startOfToday.difference(startOfTarget).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'Last 7 Days';
    return 'Older';
  }

  String _shortDate(DateTime when) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[when.month - 1]} ${when.day}';
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'support':
        return Icons.chat_bubble_outline_rounded;
      case 'system':
        return Icons.account_tree_outlined;
      case 'inventory':
        return Icons.inventory_2_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  @override
  void initState() {
    super.initState();
    _service.refresh();
    _primeAdminTools();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _logSearchController.dispose();
    _broadcastType.dispose();
    super.dispose();
  }

  Future<void> _primeAdminTools() async {
    await _adminAuth.initialize();
    await _loadAdmins();
    await _loadLogs();
  }

  Future<void> _loadAdmins() async {
    try {
      final admins = await _db.getAllAdmins();
      if (!mounted) return;
      setState(() => _admins = admins);
    } catch (_) {
      if (!mounted) return;
      setState(() => _admins = const []);
    }
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    setState(() => _loadingLogs = true);
    try {
      final from = _logDateFrom != null
          ? DateTime(_logDateFrom!.year, _logDateFrom!.month, _logDateFrom!.day)
          : null;
      final to = _logDateTo != null
          ? DateTime(
              _logDateTo!.year,
              _logDateTo!.month,
              _logDateTo!.day,
              23,
              59,
              59,
            )
          : null;
      final logs = await _db.getAdminActivityLogs(
        limit: 120,
        adminId: _logAdminFilter == 'all' ? null : _logAdminFilter,
        action: _logActionFilter == 'all' ? null : _logActionFilter,
        from: from,
        to: to,
      );
      if (!mounted) return;
      setState(() => _activityLogs = logs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _activityLogs = const []);
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _sendBroadcast() async {
    final adminId = _adminAuth.currentAdminId;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (adminId == null || adminId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in as admin again to send broadcasts.'),
        ),
      );
      return;
    }
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and message are required.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await _db.sendAdminBroadcastNotification(
        adminId: adminId,
        type: _broadcastType.value,
        title: title,
        body: body,
      );
      _titleController.clear();
      _bodyController.clear();
      await _service.refresh();
      await _loadLogs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Broadcast sent to all users.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send broadcast.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatLog(AdminActivityLog log) {
    final label = log.action.replaceAll('_', ' ');
    return '${label[0].toUpperCase()}${label.substring(1)}';
  }

  String _formatActionLabel(String action) {
    final label = action.replaceAll('_', ' ');
    return '${label[0].toUpperCase()}${label.substring(1)}';
  }

  String _adminLabel(AdminActivityLog log) {
    if (log.adminFullName != null && log.adminFullName!.isNotEmpty)
      return log.adminFullName!;
    if (log.adminEmail != null && log.adminEmail!.isNotEmpty)
      return log.adminEmail!;
    return log.adminId ?? 'System';
  }

  List<AdminActivityLog> get _visibleLogs {
    final query = _logSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _activityLogs;
    return _activityLogs
        .where((log) {
          final detailsText = log.details.entries
              .map((e) => '${e.key}:${e.value}')
              .join(' ');
          return log.action.toLowerCase().contains(query) ||
              log.entityType.toLowerCase().contains(query) ||
              (log.entityId?.toLowerCase().contains(query) ?? false) ||
              _adminLabel(log).toLowerCase().contains(query) ||
              detailsText.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _logDateFrom ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _logDateFrom = picked);
    await _loadLogs();
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _logDateTo ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _logDateTo = picked);
    await _loadLogs();
  }

  Future<void> _exportLogsCsv() async {
    if (_visibleLogs.isEmpty) return;
    setState(() => _exportingLogs = true);
    try {
      String esc(String value) => '"${value.replaceAll('"', '""')}"';
      final lines = <String>[
        'created_at,action,entity_type,entity_id,admin,admin_id,details',
        ..._visibleLogs.map(
          (log) => [
            esc(log.createdAt.toIso8601String()),
            esc(log.action),
            esc(log.entityType),
            esc(log.entityId ?? ''),
            esc(_adminLabel(log)),
            esc(log.adminId ?? ''),
            esc(jsonEncode(log.details)),
          ].join(','),
        ),
      ];
      final bytes = Uint8List.fromList(utf8.encode(lines.join('\n')));
      final filePath = await saveReportFile(
        filename:
            'admin_activity_logs_${DateTime.now().millisecondsSinceEpoch}.csv',
        bytes: bytes,
        mimeType: 'text/csv',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logs exported to $filePath')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to export logs.')));
    } finally {
      if (mounted) setState(() => _exportingLogs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AdminNotificationsPage.title),
        actions: [
          TextButton(
            onPressed: () async {
              await _service.clearAllNotifications();
            },
            child: const Text('Clear All'),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _service.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ValueListenableBuilder<AdminNotificationSnapshot>(
        valueListenable: _service.snapshot,
        builder: (context, snap, _) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Broadcast message',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Send maintenance alerts or promo pushes to all customers.',
                          ),
                          const SizedBox(height: 12),
                          ValueListenableBuilder<String>(
                            valueListenable: _broadcastType,
                            builder: (_, value, __) {
                              return DropdownButtonFormField<String>(
                                initialValue: value,
                                decoration: const InputDecoration(
                                  labelText: 'Type',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'maintenance_alert',
                                    child: Text('Maintenance alert'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'promo',
                                    child: Text('Promo'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'admin_broadcast',
                                    child: Text('General broadcast'),
                                  ),
                                ],
                                onChanged: (next) {
                                  if (next != null) _broadcastType.value = next;
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: 'Title',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _bodyController,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Message',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _sending ? null : _sendBroadcast,
                            icon: _sending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.campaign_outlined),
                            label: const Text('Send broadcast'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Notifications',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await _service.clearAllNotifications();
                        },
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (snap.items.isEmpty)
                    Card(
                      color: const Color(0xFFF7F7F8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'All quiet.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ),
                    )
                  else ...[
                    ...(() {
                      final grouped = <String, List<AdminNotificationItem>>{};
                      for (final item in snap.items) {
                        final key = _relativeDay(item.createdAt);
                        grouped
                            .putIfAbsent(key, () => <AdminNotificationItem>[])
                            .add(item);
                      }
                      const sectionOrder = <String>[
                        'Today',
                        'Yesterday',
                        'Last 7 Days',
                        'Older',
                      ];
                      return sectionOrder
                          .where(
                            (section) =>
                                (grouped[section] ?? const []).isNotEmpty,
                          )
                          .map((section) {
                            final items = grouped[section]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    10,
                                    4,
                                    6,
                                  ),
                                  child: Text(
                                    section,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF6B7280),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                ...items.map((item) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF7F7F8),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFDCDCFB),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            _iconForType(item.type),
                                            color: const Color(0xFF3730A3),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                  color: Color(0xFF111827),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                item.subtitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Color(0xFF6B7280),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _shortDate(item.createdAt),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF6B7280),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            );
                          });
                    })(),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Activity log',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Export CSV',
                        onPressed: _exportingLogs ? null : _exportLogsCsv,
                        icon: _exportingLogs
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_outlined),
                      ),
                      IconButton(
                        tooltip: 'Refresh logs',
                        onPressed: _loadingLogs ? null : _loadLogs,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          initialValue: _logAdminFilter,
                          decoration: const InputDecoration(labelText: 'Admin'),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('All admins'),
                            ),
                            if (_logAdminFilter != 'all' &&
                                !_admins.any(
                                  (admin) => admin.id == _logAdminFilter,
                                ))
                              DropdownMenuItem(
                                value: _logAdminFilter,
                                child: Text(_logAdminFilter),
                              ),
                            ..._admins.map(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(
                                  a.fullName.isNotEmpty ? a.fullName : a.email,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _logAdminFilter = value);
                            await _loadLogs();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          initialValue: _logActionFilter,
                          decoration: const InputDecoration(
                            labelText: 'Action',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('All actions'),
                            ),
                            ...{
                              ..._activityLogs.map((log) => log.action),
                              if (_logActionFilter != 'all') _logActionFilter,
                            }.map(
                              (action) => DropdownMenuItem(
                                value: action,
                                child: Text(_formatActionLabel(action)),
                              ),
                            ),
                          ],
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _logActionFilter = value);
                            await _loadLogs();
                          },
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickFromDate,
                        icon: const Icon(Icons.event),
                        label: Text(
                          _logDateFrom == null
                              ? 'From date'
                              : 'From ${_logDateFrom!.toIso8601String().split('T').first}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickToDate,
                        icon: const Icon(Icons.event_available),
                        label: Text(
                          _logDateTo == null
                              ? 'To date'
                              : 'To ${_logDateTo!.toIso8601String().split('T').first}',
                        ),
                      ),
                      if (_logDateFrom != null || _logDateTo != null)
                        TextButton(
                          onPressed: () async {
                            setState(() {
                              _logDateFrom = null;
                              _logDateTo = null;
                            });
                            await _loadLogs();
                          },
                          child: const Text('Clear dates'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _logSearchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search logs by action/admin/entity/details...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingLogs)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_visibleLogs.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('No activity records yet.'),
                        subtitle: Text(
                          'Critical admin actions will appear here.',
                        ),
                      ),
                    )
                  else
                    ..._visibleLogs.map(
                      (log) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.shield_outlined),
                          title: Text(_formatLog(log)),
                          subtitle: Text(
                            '${_adminLabel(log)}\n'
                            '${log.entityType}${log.entityId != null ? ' • ${log.entityId}' : ''}\n'
                            '${log.createdAt.toLocal()}',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
