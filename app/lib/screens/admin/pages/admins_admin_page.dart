import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../auth/admin_permissions.dart';
import '../../../../models/admin.dart';
import '../../../../services/admin_auth_service.dart';
import '../../../../services/mysql_database_service.dart';
import '../../../../utils/password_policy.dart';
import '../auth/admin_login_page.dart';
import '../widgets/admin_toolbar.dart';
import '../widgets/admin_anchored_popover.dart';
import '../../../../widgets/admin_console_surfaces.dart';
import '../../../../widgets/toast.dart';

/// Admin management page for viewing and creating admin accounts.
/// 
/// This page allows authenticated admins to:
/// - View all admin accounts
/// - Create new admin accounts
/// - View admin details (but NOT edit credentials for security)
/// 
/// SECURITY: Email and password cannot be edited through this interface.
class AdminsAdminPage extends StatefulWidget {
  const AdminsAdminPage({super.key});

  @override
  State<AdminsAdminPage> createState() => _AdminsAdminPageState();
}

class _AdminsAdminPageState extends State<AdminsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AdminAuthService _adminAuth = AdminAuthService();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _filterAnchorKey = GlobalKey();
  
  List<Admin> _admins = const [];
  bool _loading = true;
  /// True while POST /admins is in flight (dialog already closed).
  bool _createAdminInFlight = false;
  String? _error;
  String _searchQuery = '';
  String _sortBy = 'newest';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    _loadAdmins();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Loads all admins from the database.
  Future<void> _loadAdmins() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final admins = await _db.getAllAdmins();
      if (!mounted) return;
      setState(() {
        _admins = admins;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load admins: $e';
        _loading = false;
      });
    }
  }

  /// Filters admins by search query (searches name and email).
  List<Admin> get _filtered {
    final query = _searchQuery.toLowerCase();
    final filtered = _admins.where((admin) {
      return admin.fullName.toLowerCase().contains(query) ||
             admin.email.toLowerCase().contains(query);
    }).toList(growable: false);
    final result = _searchQuery.isEmpty ? List<Admin>.from(_admins) : filtered;
    switch (_sortBy) {
      case 'oldest':
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'name_az':
        result.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
        break;
      case 'name_za':
        result.sort((a, b) => b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase()));
        break;
      case 'newest':
      default:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    return result;
  }

  int get _activeFilterCount => _sortBy == 'newest' ? 0 : 1;

  void _showAdminFilterPopover() {
    var tempSort = _sortBy;
    AdminAnchoredPopover.show<void>(
      context: context,
      anchorKey: _filterAnchorKey,
      width: 360,
      height: 220,
      child: StatefulBuilder(
        builder: (ctx, setModalState) {
          return Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Filter Admins',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Sort by', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: tempSort,
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Color(0xFFF8F8F8),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest First')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest First')),
                      DropdownMenuItem(value: 'name_az', child: Text('Name A–Z')),
                      DropdownMenuItem(value: 'name_za', child: Text('Name Z–A')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setModalState(() => tempSort = v);
                    },
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => setModalState(() => tempSort = 'newest'),
                        child: const Text('Reset'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          setState(() => _sortBy = tempSort);
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Shows detailed admin information in a centered modal dialog.
  /// 
  /// Note: Credentials (email/password) are NOT editable for security.
  void _showAdminDetails(Admin admin) {
    showDialog(
      context: context,
      builder: (context) => _AdminDetailsDialog(admin: admin),
    );
  }

  /// Opens the edit sheet (role + permissions follow the selected role, same as backend RBAC).
  Future<void> _openEditAdmin(Admin admin) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _EditAdminDialog(
        admin: admin,
        canChangeRole: (_adminAuth.currentRole ?? '').trim() == 'super_admin',
      ),
    );
    if (changed == true && mounted) {
      await _loadAdmins();
    }
  }

  void _onArchiveAdmin(Admin admin) {
    Toast.info(
      context,
      'Admin accounts cannot be archived from the console yet. Change this user’s role to restrict access.',
    );
  }

  /// Disables or re-enables sign-in for an admin (super_admin only; enforced server-side).
  Future<void> _confirmSetDisabled(Admin admin, bool disabled) async {
    final isSuper = (_adminAuth.currentRole ?? '').trim() == 'super_admin';
    if (!isSuper) {
      Toast.error(context, 'Only a super admin can change account status');
      return;
    }
    final self = (_adminAuth.currentAdminId ?? '').trim() == admin.id.trim();
    if (disabled && self) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Disable your own account?'),
          content: const Text(
            'You will be signed out immediately and cannot sign in again until another super admin re-enables this account.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              child: const Text('Disable'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    } else if (!disabled && self) {
      // Enabling self is a no-op edge case (you're already in).
    }

    try {
      await _db.updateAdmin(adminId: admin.id, isDisabled: disabled);
      if (!mounted) return;
      Toast.success(context, disabled ? 'Account disabled' : 'Account enabled');
      if (disabled && self) {
        await _adminAuth.signOut();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(AdminLoginPage.route, (route) => false);
        return;
      }
      await _loadAdmins();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed: $e');
    }
  }

  /// Opens the "Add admin" dialog and creates a new admin if confirmed.
  Future<void> _createAdmin() async {
    if (_createAdminInFlight) return;
    final allowRolePick = (_adminAuth.currentRole ?? '').trim() == 'super_admin';
    // Match [Users] add-dialog routing: single app navigator — avoid rootNavigator pop mismatch on web.
    final data = await showDialog<_AdminFormData>(
      context: context,
      builder: (_) => _AdminFormDialog(allowRolePick: allowRolePick),
    );
    if (data == null) return;

    setState(() => _createAdminInFlight = true);
    try {
      await _db.createAdmin(
        email: data.email,
        password: data.password,
        fullName: data.fullName,
        role: data.role,
      );
      if (!mounted) return;
      Toast.success(context, 'Admin created successfully');
      await _loadAdmins();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final friendly = msg.contains('401') || msg.contains('sign in again')
          ? 'Session expired or missing token. Sign out and sign in again, then retry.'
          : msg.contains('ADMIN_JWT_SECRET') || msg.contains('500')
              ? 'Server is not configured for admin API (ADMIN_JWT_SECRET). Check backend .env.'
              : 'Failed to create admin: $e';
      Toast.error(context, friendly);
    } finally {
      if (mounted) setState(() => _createAdminInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminToolbar(
          title: 'Administrators',
          actions: [],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: CupertinoColors.separator.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: CupertinoColors.separator.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Stack(
                children: [
                  SizedBox(
                    key: _filterAnchorKey,
                    child: IconButton.outlined(
                      onPressed: _showAdminFilterPopover,
                      icon: const Icon(Icons.tune_outlined),
                      tooltip: 'Filter',
                    ),
                  ),
                  if (_activeFilterCount > 0)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: const BoxDecoration(color: Color(0xFF8D6E63), shape: BoxShape.circle),
                        child: Text(
                          '$_activeFilterCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _createAdminInFlight ? null : _createAdmin,
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Add admin'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8D6E63),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadAdmins,
                tooltip: 'Refresh admins',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            '${filtered.length} ${filtered.length == 1 ? 'administrator' : 'administrators'}',
            style: GoogleFonts.poppins(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.admin_panel_settings_outlined,
                              size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No admins match your search'
                                : 'No admins yet',
                            style: GoogleFonts.poppins(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Card(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        children: [
                          const _AdminsHeaderRow(),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final admin = filtered[index];
                                return _AdminsTableRow(
                                  admin: admin,
                                  onEdit: () => _openEditAdmin(admin),
                                  onDetails: () => _showAdminDetails(admin),
                                  onArchive: () => _onArchiveAdmin(admin),
                                  onDisableAccount: () => _confirmSetDisabled(admin, true),
                                  onEnableAccount: () => _confirmSetDisabled(admin, false),
                                  viewerIsSuper: (_adminAuth.currentRole ?? '').trim() == 'super_admin',
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

/// Header row for the admins table (image · name · email · role · permissions · actions).
class _AdminsHeaderRow extends StatelessWidget {
  const _AdminsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.grey[600],
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 44, child: Center(child: Text('Image', style: style))),
          Expanded(flex: 22, child: Text('Name', style: style)),
          Expanded(flex: 28, child: Text('Email', style: style)),
          Expanded(flex: 16, child: Text('Role', style: style)),
          Expanded(flex: 30, child: Text('Permissions', style: style)),
          SizedBox(width: 44, child: Center(child: Text('', style: style))),
        ],
      ),
    );
  }
}

String _adminInitials(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) {
    return '?';
  }
  if (parts.length == 1) {
    final s = parts[0];
    return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
  }
  return ('${parts.first[0]}${parts.last[0]}').toUpperCase();
}

/// Permission tags for the table (first few + overflow count).
class _PermissionsChips extends StatelessWidget {
  const _PermissionsChips({required this.admin});

  final Admin admin;

  @override
  Widget build(BuildContext context) {
    final perms = AdminPermissions.effectivePermissionsFor(admin);
    const maxVisible = 4;
    final visible = perms.take(maxVisible).toList();
    final extra = perms.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visible.map(
          (p) => Chip(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            label: Text(
              p,
              style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            side: BorderSide(color: Colors.grey.shade300),
            backgroundColor: const Color(0xFFF5F5F5),
          ),
        ),
        if (extra > 0)
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(
              '+$extra',
              style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
            side: BorderSide(color: Colors.grey.shade300),
            backgroundColor: const Color(0xFFEDE7DC),
          ),
      ],
    );
  }
}

/// One data row: avatar, identity, role badge, permission chips, overflow menu.
class _AdminsTableRow extends StatelessWidget {
  const _AdminsTableRow({
    required this.admin,
    required this.onEdit,
    required this.onDetails,
    required this.onArchive,
    required this.onDisableAccount,
    required this.onEnableAccount,
    required this.viewerIsSuper,
  });

  final Admin admin;
  final VoidCallback onEdit;
  final VoidCallback onDetails;
  final VoidCallback onArchive;
  final VoidCallback onDisableAccount;
  final VoidCallback onEnableAccount;
  final bool viewerIsSuper;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: admin.isDisabled ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          SizedBox(
            width: 44,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF8D6E63).withValues(alpha: 0.2),
              child: Text(
                _adminInitials(admin.fullName),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5C4033),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 22,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    admin.fullName,
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (admin.isDisabled) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      'Disabled',
                      style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.red.shade800),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 28,
            child: Text(
              admin.email,
              style: GoogleFonts.poppins(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 16,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7DC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  admin.role.replaceAll('_', ' '),
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF4E342E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 30,
            child: _PermissionsChips(admin: admin),
          ),
          SizedBox(
            width: 44,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 22),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                    break;
                  case 'details':
                    onDetails();
                    break;
                  case 'archive':
                    onArchive();
                    break;
                  case 'disable':
                    onDisableAccount();
                    break;
                  case 'enable':
                    onEnableAccount();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'details', child: Text('View details')),
                if (viewerIsSuper)
                  PopupMenuItem(
                    value: admin.isDisabled ? 'enable' : 'disable',
                    child: Text(admin.isDisabled ? 'Enable account' : 'Disable account'),
                  ),
                const PopupMenuItem(value: 'archive', child: Text('Archive')),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Per-key override: inherit role matrix, force grant, or force revoke (super admin only; stored server-side).
enum _PermOverride { inherit, grant, revoke }

/// Modal to adjust display name and role; permission list reflects the role (server-side RBAC).
class _EditAdminDialog extends StatefulWidget {
  const _EditAdminDialog({
    required this.admin,
    required this.canChangeRole,
  });

  final Admin admin;
  final bool canChangeRole;

  @override
  State<_EditAdminDialog> createState() => _EditAdminDialogState();
}

class _EditAdminDialogState extends State<_EditAdminDialog> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AdminAuthService _auth = AdminAuthService();

  late final TextEditingController _fullName;
  late String _draftRole;
  late Set<String> _extra;
  late Set<String> _revoked;
  String? _inlineError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fullName = TextEditingController(text: widget.admin.fullName);
    _draftRole = widget.admin.role;
    _extra = Set<String>.from(widget.admin.extraPermissions);
    _revoked = Set<String>.from(widget.admin.revokedPermissions);
  }

  @override
  void dispose() {
    _fullName.dispose();
    super.dispose();
  }

  _PermOverride _modeFor(String key) {
    if (_revoked.contains(key)) return _PermOverride.revoke;
    if (_extra.contains(key)) return _PermOverride.grant;
    return _PermOverride.inherit;
  }

  void _applyMode(String key, _PermOverride mode) {
    setState(() {
      _extra.remove(key);
      _revoked.remove(key);
      switch (mode) {
        case _PermOverride.inherit:
          break;
        case _PermOverride.grant:
          _extra.add(key);
          break;
        case _PermOverride.revoke:
          _revoked.add(key);
          break;
      }
    });
  }

  bool _listSetMatch(Set<String> a, List<String> b) =>
      a.length == b.length && a.containsAll(b);

  Admin _previewAdmin(String name) {
    return Admin(
      id: widget.admin.id,
      email: widget.admin.email,
      fullName: name,
      createdAt: widget.admin.createdAt,
      updatedAt: widget.admin.updatedAt,
      lastLoginAt: widget.admin.lastLoginAt,
      emailVerified: widget.admin.emailVerified,
      role: _draftRole,
      isDisabled: widget.admin.isDisabled,
      extraPermissions: _extra.toList(),
      revokedPermissions: _revoked.toList(),
    );
  }

  Future<void> _save() async {
    setState(() {
      _inlineError = null;
    });
    final name = _fullName.text.trim();
    if (name.isEmpty) {
      setState(() => _inlineError = 'Name is required.');
      return;
    }

    final roleChanged = widget.canChangeRole && _draftRole != widget.admin.role;
    final nameChanged = name != widget.admin.fullName;
    final permsChanged = widget.canChangeRole &&
        (!_listSetMatch(_extra, widget.admin.extraPermissions) ||
            !_listSetMatch(_revoked, widget.admin.revokedPermissions));

    if (!nameChanged && !roleChanged && !permsChanged) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() => _busy = true);
    try {
      final updated = await _db.updateAdmin(
        adminId: widget.admin.id,
        fullName: nameChanged ? name : null,
        role: roleChanged ? _draftRole : null,
        extraPermissions: permsChanged ? _extra.toList() : null,
        revokedPermissions: permsChanged ? _revoked.toList() : null,
      );
      final self = (_auth.currentAdminId ?? '').trim() == widget.admin.id.trim();
      if (self) {
        await _auth.updateLocalProfile(fullName: updated.fullName, role: updated.role);
      }
      if (!mounted) return;
      Toast.success(context, 'Administrator updated');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewAdmin(_fullName.text.trim().isEmpty ? widget.admin.fullName : _fullName.text.trim());
    final effective = AdminPermissions.effectivePermissionsFor(preview);
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit administrator',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Role sets the baseline. Super admins can grant or revoke individual permissions below.',
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: Colors.black54,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_inlineError != null) ...[
                      Material(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _inlineError!,
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.red.shade900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'General',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fullName,
                      decoration: InputDecoration(
                        labelText: 'Full name',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Email is read-only here for security.',
                      style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.black45),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Role',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    if (widget.canChangeRole)
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _draftRole,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'super_admin', child: Text('Super admin')),
                          DropdownMenuItem(value: 'operations_admin', child: Text('Operations')),
                          DropdownMenuItem(value: 'support_admin', child: Text('Support')),
                          DropdownMenuItem(value: 'social_admin', child: Text('Social / content')),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _draftRole = v);
                              },
                      )
                    else
                      Text(
                        widget.admin.role.replaceAll('_', ' '),
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      'Permission overrides',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Default follows the role. Grant adds a capability; Revoke removes it even if the role normally includes it.',
                      style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.black45, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    if (widget.canChangeRole)
                      ...AdminPermissions.allDefinedPermissions.map((p) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  p,
                                  style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<_PermOverride>(
                                  // ignore: deprecated_member_use
                                  value: _modeFor(p),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: _PermOverride.inherit, child: Text('Default')),
                                    DropdownMenuItem(value: _PermOverride.grant, child: Text('Grant')),
                                    DropdownMenuItem(value: _PermOverride.revoke, child: Text('Revoke')),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (v) {
                                          if (v != null) _applyMode(p, v);
                                        },
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                    else
                      Text(
                        'Only a super admin can edit permission overrides.',
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Effective permissions (${effective.length})',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: effective
                          .map(
                            (p) => Chip(
                              label: Text(p, style: GoogleFonts.poppins(fontSize: 10.5)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: const Color(0xFFF0EBE6),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8D6E63),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Save changes', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog showing detailed admin information.
/// 
/// SECURITY: Credentials (email/password) are NOT editable.
class _AdminDetailsDialog extends StatelessWidget {
  const _AdminDetailsDialog({required this.admin});

  final Admin admin;

  String _formatDateTime(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _initials(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    const fs = 15.0;
    final initials = _initials(admin.fullName);
    final avatar = CircleAvatar(
      radius: 34,
      backgroundColor: AdminConsoleSurfaces.accentBrown.withValues(alpha: 0.2),
      child: Text(
        initials,
        style: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AdminConsoleSurfaces.walnutText,
        ),
      ),
    );

    return AdminProfileStyleDetailDialog(
      title: 'Admin Details',
      subtitle: 'Role, overrides, and sign-in metadata (read-only credentials).',
      headerTrailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(height: 4),
          Text(
            'Initials',
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
      body: AdminConsoleSurfaces.detailCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminProfileStyleDetailRow(label: 'Full Name', value: admin.fullName, fontSize: fs),
            AdminProfileStyleDetailRow(label: 'Email', value: admin.email, fontSize: fs),
            AdminProfileStyleDetailRow(
              label: 'Role',
              value: admin.role.replaceAll('_', ' '),
              fontSize: fs,
            ),
            AdminProfileStyleDetailRow(
              label: 'Account',
              value: admin.isDisabled ? 'Disabled (cannot sign in)' : 'Enabled',
              fontSize: fs,
            ),
            AdminProfileStyleDetailRow(
              label: 'Permission overrides',
              value: admin.extraPermissions.isEmpty && admin.revokedPermissions.isEmpty
                  ? 'None (role defaults only)'
                  : 'Extra: ${admin.extraPermissions.length}, Revoked: ${admin.revokedPermissions.length}',
              fontSize: fs,
            ),
            AdminProfileStyleDetailRow(
              label: 'Created',
              value: _formatDateTime(admin.createdAt),
              fontSize: fs,
            ),
            AdminProfileStyleDetailRow(
              label: 'Last Login',
              value: admin.lastLoginAt != null ? _formatDateTime(admin.lastLoginAt!) : 'Never',
              fontSize: fs,
              showDivider: false,
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(36),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade200.withValues(alpha: 0.65)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 20, color: Colors.orange.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Credentials cannot be edited for security reasons.',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Form data structure for creating a new admin.
class _AdminFormData {
  const _AdminFormData({
    required this.email,
    required this.password,
    required this.fullName,
    this.role,
  });

  final String email;
  final String password;
  final String fullName;
  /// When non-null, only [super_admin] should send this; server validates.
  final String? role;
}

/// Dialog form for creating a new admin account.
class _AdminFormDialog extends StatefulWidget {
  const _AdminFormDialog({this.allowRolePick = false});

  final bool allowRolePick;

  @override
  State<_AdminFormDialog> createState() => _AdminFormDialogState();
}

class _AdminFormDialogState extends State<_AdminFormDialog> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _fullName = TextEditingController();
  String _pickedRole = 'operations_admin';
  bool _obscurePassword = true;
  /// Shown inside the modal — top [Toast] can sit under the dialog barrier on web.
  String? _inlineError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _inlineError = null);
    final email = _email.text.trim();
    final password = _password.text.trim();
    final fullName = _fullName.text.trim();
    if (email.isEmpty || password.isEmpty || fullName.isEmpty) {
      setState(() => _inlineError = 'All fields are required.');
      return;
    }

    final passwordError = PasswordPolicy.validateStrongPassword(password);
    if (passwordError != null) {
      setState(() => _inlineError = passwordError);
      return;
    }

    final data = _AdminFormData(
      email: email,
      password: password,
      fullName: fullName,
      role: widget.allowRolePick ? _pickedRole : null,
    );
    // Same navigator as [showDialog] (see [_createAdmin]) — do not use rootNavigator here.
    Navigator.of(context).pop(data);
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF8F8F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: CupertinoColors.separator.withValues(alpha: 0.1),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: CupertinoColors.separator.withValues(alpha: 0.1),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
          ),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Constrained modal matching admin container—not full screen.
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 540),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                    Expanded(
                      child: Text(
                        'Add admin',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_inlineError != null) ...[
                        Material(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _inlineError!,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Colors.red.shade900,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildField(
                        _email,
                        'Email *',
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) {
                          if (_inlineError != null) setState(() => _inlineError = null);
                        },
                      ),
                      _buildField(
                        _password,
                        'Password *',
                        obscureText: _obscurePassword,
                        onChanged: (_) {
                          if (_inlineError != null) setState(() => _inlineError = null);
                        },
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      _buildField(
                        _fullName,
                        'Full name *',
                        onChanged: (_) {
                          if (_inlineError != null) setState(() => _inlineError = null);
                        },
                      ),
                      if (widget.allowRolePick) ...[
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          value: _pickedRole,
                          decoration: InputDecoration(
                            labelText: 'Role',
                            filled: true,
                            fillColor: const Color(0xFFF8F8F8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'operations_admin',
                              child: Text('Operations'),
                            ),
                            DropdownMenuItem(
                              value: 'support_admin',
                              child: Text('Support'),
                            ),
                            DropdownMenuItem(
                              value: 'social_admin',
                              child: Text('Social / content'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _pickedRole = v);
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${PasswordPolicy.strongPasswordMessage} New admin accounts must verify email before first login.',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.blue[900],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        _submit();
                      },
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8D6E63)),
                      child: const Text('Create'),
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
}

















