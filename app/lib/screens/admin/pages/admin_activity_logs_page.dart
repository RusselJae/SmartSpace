import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../models/admin.dart';
import '../../../models/admin_activity_log.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/mysql_database_service.dart';
import '../../../utils/report_file_saver.dart';

class AdminActivityLogsPage extends StatefulWidget {
  const AdminActivityLogsPage({super.key});

  static const String title = 'Activity Logs';

  @override
  State<AdminActivityLogsPage> createState() => _AdminActivityLogsPageState();
}

class _AdminActivityLogsPageState extends State<AdminActivityLogsPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AdminAuthService _adminAuth = AdminAuthService();
  final TextEditingController _logSearchController = TextEditingController();

  List<AdminActivityLog> _activityLogs = const [];
  List<Admin> _admins = const [];
  String _logActionFilter = 'all';
  String _logAdminFilter = 'all';
  DateTime? _logDateFrom;
  DateTime? _logDateTo;
  String _logSortBy = 'newest';
  bool _exportingLogs = false;
  bool _loadingLogs = false;

  @override
  void initState() {
    super.initState();
    _primeAdminTools();
  }

  @override
  void dispose() {
    _logSearchController.dispose();
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

  String _formatLog(AdminActivityLog log) {
    final label = log.action.replaceAll('_', ' ');
    return '${label[0].toUpperCase()}${label.substring(1)}';
  }

  String _formatDateHeading(DateTime when) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[when.month - 1]} ${when.day}, ${when.year}';
  }

  String _formatTime(DateTime when) {
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
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final minute = when.minute.toString().padLeft(2, '0');
    final suffix = when.hour >= 12 ? 'PM' : 'AM';
    return '${months[when.month - 1]} ${when.day}, $hour:$minute $suffix';
  }

  String _formatActionLabel(String action) {
    final label = action.replaceAll('_', ' ');
    return '${label[0].toUpperCase()}${label.substring(1)}';
  }

  String _adminLabel(AdminActivityLog log) {
    if (log.adminFullName != null && log.adminFullName!.isNotEmpty) {
      return log.adminFullName!;
    }
    if (log.adminEmail != null && log.adminEmail!.isNotEmpty) {
      return log.adminEmail!;
    }
    return log.adminId ?? 'System';
  }

  List<AdminActivityLog> get _visibleLogs {
    final query = _logSearchController.text.trim().toLowerCase();
    final source = query.isEmpty
        ? List<AdminActivityLog>.from(_activityLogs)
        : _activityLogs
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
    source.sort(
      (a, b) => _logSortBy == 'oldest'
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt),
    );
    return source;
  }

  Map<DateTime, List<AdminActivityLog>> get _groupedVisibleLogs {
    final grouped = <DateTime, List<AdminActivityLog>>{};
    for (final log in _visibleLogs) {
      final day = DateTime(
        log.createdAt.year,
        log.createdAt.month,
        log.createdAt.day,
      );
      grouped.putIfAbsent(day, () => <AdminActivityLog>[]).add(log);
    }

    final sortedDays = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    for (final day in sortedDays) {
      grouped[day]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return <DateTime, List<AdminActivityLog>>{
      for (final day in sortedDays) day: grouped[day]!,
    };
  }

  IconData _iconForLog(AdminActivityLog log) {
    final action = log.action.toLowerCase();
    if (action.contains('delete') ||
        action.contains('disable') ||
        action.contains('remove')) {
      return Icons.warning_amber_rounded;
    }
    if (action.contains('create') || action.contains('add')) {
      return Icons.add_circle_outline_rounded;
    }
    if (action.contains('update') || action.contains('edit')) {
      return Icons.edit_outlined;
    }
    return Icons.shield_outlined;
  }

  Color _iconTintForLog(AdminActivityLog log) {
    final action = log.action.toLowerCase();
    if (action.contains('delete') ||
        action.contains('disable') ||
        action.contains('remove')) {
      return const Color(0xFFB45309);
    }
    if (action.contains('create') || action.contains('add')) {
      return const Color(0xFF1D4ED8);
    }
    if (action.contains('update') || action.contains('edit')) {
      return const Color(0xFF2563EB);
    }
    return const Color(0xFF4338CA);
  }

  Color _iconBackgroundForLog(AdminActivityLog log) {
    final action = log.action.toLowerCase();
    if (action.contains('delete') ||
        action.contains('disable') ||
        action.contains('remove')) {
      return const Color(0xFFFEF3C7);
    }
    if (action.contains('create') || action.contains('add')) {
      return const Color(0xFFDBEAFE);
    }
    if (action.contains('update') || action.contains('edit')) {
      return const Color(0xFFE0E7FF);
    }
    return const Color(0xFFE0E7FF);
  }

  String _detailsSummary(AdminActivityLog log) {
    if (log.details.isEmpty) return 'No additional details';
    return log.details.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }

  int get _activeLogFilterCount {
    var count = 0;
    if (_logActionFilter != 'all') count++;
    if (_logAdminFilter != 'all') count++;
    if (_logDateFrom != null || _logDateTo != null) count++;
    if (_logSortBy != 'newest') count++;
    return count;
  }

  void _showLogFilterSheet() {
    String tempAction = _logActionFilter;
    String tempAdmin = _logAdminFilter;
    String tempSort = _logSortBy;
    DateTime? tempFrom = _logDateFrom;
    DateTime? tempTo = _logDateTo;

    Future<void> pickDate({
      required bool from,
      required void Function(void Function()) setModalState,
    }) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: (from ? tempFrom : tempTo) ?? DateTime.now(),
        firstDate: DateTime(2020, 1, 1),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked == null) return;
      setModalState(() {
        if (from) {
          tempFrom = picked;
        } else {
          tempTo = picked;
        }
      });
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final actions = <String>{..._activityLogs.map((e) => e.action)};
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Filter Activity Logs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Sort by', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: tempSort,
                      items: const [
                        DropdownMenuItem(value: 'newest', child: Text('Newest First')),
                        DropdownMenuItem(value: 'oldest', child: Text('Oldest First')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() => tempSort = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text('Action', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: tempAction,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All Actions')),
                        ...actions.map((a) => DropdownMenuItem(value: a, child: Text(_formatActionLabel(a)))),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() => tempAction = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text('Admin', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: tempAdmin,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All Admins')),
                        ..._admins.map((a) => DropdownMenuItem(value: a.id, child: Text(a.fullName.isNotEmpty ? a.fullName : a.email))),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() => tempAdmin = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickDate(from: true, setModalState: setModalState),
                            icon: const Icon(Icons.calendar_month_outlined, size: 18),
                            label: Text(tempFrom == null ? 'From' : tempFrom!.toIso8601String().split('T').first),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickDate(from: false, setModalState: setModalState),
                            icon: const Icon(Icons.event_available_outlined, size: 18),
                            label: Text(tempTo == null ? 'To' : tempTo!.toIso8601String().split('T').first),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              tempAction = 'all';
                              tempAdmin = 'all';
                              tempSort = 'newest';
                              tempFrom = null;
                              tempTo = null;
                            });
                          },
                          child: const Text('Reset'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () async {
                            setState(() {
                              _logActionFilter = tempAction;
                              _logAdminFilter = tempAdmin;
                              _logSortBy = tempSort;
                              _logDateFrom = tempFrom;
                              _logDateTo = tempTo;
                            });
                            Navigator.of(sheetContext).pop();
                            await _loadLogs();
                          },
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5C4033)),
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
    final groupedLogs = _groupedVisibleLogs;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1160),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Flat, "orders-like" top controls: no extra header block or outer box.
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _logSearchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search activities...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Stack(
                      children: [
                        IconButton.outlined(
                          onPressed: _showLogFilterSheet,
                          icon: const Icon(Icons.tune_outlined),
                          tooltip: 'Filter',
                        ),
                        if (_activeLogFilterCount > 0)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: const BoxDecoration(color: Color(0xFF8D6E63), shape: BoxShape.circle),
                              child: Text(
                                '$_activeLogFilterCount',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Refresh Logs',
                      onPressed: _loadingLogs ? null : _loadLogs,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: 'Export CSV',
                      onPressed: _exportingLogs ? null : _exportLogsCsv,
                      icon: _exportingLogs
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                    ),
                  ],
                ),
                  const SizedBox(height: 6),
                  if (_loadingLogs)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (groupedLogs.isEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: const Text(
                        'No activity records yet. Critical admin actions will appear here.',
                      ),
                    )
                  else
                    ...groupedLogs.entries.map((entry) {
                      final day = entry.key;
                      final logs = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 2,
                                bottom: 8,
                              ),
                              child: Text(
                                _formatDateHeading(day),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFF6B7280),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < logs.length; i++) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: _iconBackgroundForLog(
                                                logs[i],
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              _iconForLog(logs[i]),
                                              size: 18,
                                              color: _iconTintForLog(logs[i]),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${_formatLog(logs[i])} • ${logs[i].entityType}${logs[i].entityId != null ? ' ${logs[i].entityId}' : ''}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF111827),
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${_adminLabel(logs[i])} • ${_detailsSummary(logs[i])}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF6B7280),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _formatTime(logs[i].createdAt),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF6B7280),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (i != logs.length - 1)
                                      const Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Color(0xFFF1F5F9),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
