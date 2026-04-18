import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../models/admin.dart';
import '../../../../services/admin_auth_service.dart';
import '../../../../services/mysql_database_service.dart';
import '../../../../utils/password_policy.dart';
import '../widgets/admin_toolbar.dart';
import '../widgets/admin_anchored_popover.dart';
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

  /// Opens the "Add admin" dialog and creates a new admin if confirmed.
  Future<void> _createAdmin() async {
    final allowRolePick = (_adminAuth.currentRole ?? '').trim() == 'super_admin';
    final data = await showDialog<_AdminFormData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _AdminFormDialog(allowRolePick: allowRolePick),
    );
    if (data == null) return;
    
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
                onPressed: _createAdmin,
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
                                  onTap: () => _showAdminDetails(admin),
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

/// Header row for the admins table.
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
          Expanded(flex: 3, child: Text('Name', style: style)),
          Expanded(flex: 3, child: Text('Email', style: style)),
          Expanded(flex: 2, child: Text('Role', style: style)),
          Expanded(flex: 2, child: Text('Created', style: style)),
          Expanded(flex: 2, child: Text('Last Login', style: style)),
          const SizedBox(width: 80),
        ],
      ),
    );
  }
}

/// Table row displaying an admin's information.
class _AdminsTableRow extends StatelessWidget {
  const _AdminsTableRow({required this.admin, required this.onTap});

  final Admin admin;
  final VoidCallback onTap;

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                admin.fullName,
                style: GoogleFonts.poppins(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                admin.email,
                style: GoogleFonts.poppins(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                admin.role.replaceAll('_', ' '),
                style: GoogleFonts.poppins(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _formatDate(admin.createdAt),
                style: GoogleFonts.poppins(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                admin.lastLoginAt != null
                    ? _formatDate(admin.lastLoginAt!)
                    : 'Never',
                style: GoogleFonts.poppins(
                  color: admin.lastLoginAt != null
                      ? Colors.black
                      : Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 20),
              onPressed: onTap,
              tooltip: 'View details',
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      'Admin Details',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailRow(label: 'Full Name', value: admin.fullName),
                    const SizedBox(height: 12),
                    _DetailRow(label: 'Email', value: admin.email),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Role',
                      value: admin.role.replaceAll('_', ' '),
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Created',
                      value: _formatDateTime(admin.createdAt),
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Last Login',
                      value: admin.lastLoginAt != null
                          ? _formatDateTime(admin.lastLoginAt!)
                          : 'Never',
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline, size: 18, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Credentials cannot be edited for security reasons.',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.orange[900],
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
          ],
        ),
      ),
    );
  }
}

/// Helper widget for displaying a label-value pair in the details dialog.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;
  static const double _detailFontSize = 16;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: GoogleFonts.poppins(
              fontSize: _detailFontSize,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: _detailFontSize,
              color: Colors.black,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _email.text.trim();
    final password = _password.text.trim();
    final fullName = _fullName.text.trim();
    if (email.isEmpty || password.isEmpty || fullName.isEmpty) {
      Toast.warning(context, 'All fields are required');
      return;
    }

    final passwordError = PasswordPolicy.validateStrongPassword(password);
    if (passwordError != null) {
      Toast.warning(context, passwordError);
      return;
    }

    final data = _AdminFormData(
      email: email,
      password: password,
      fullName: fullName,
      role: widget.allowRolePick ? _pickedRole : null,
    );
    // Root navigator matches [showDialog(..., useRootNavigator: true)] so the dialog always closes.
    Navigator.of(context, rootNavigator: true).pop(data);
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
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
                      _buildField(_email, 'Email *', keyboardType: TextInputType.emailAddress),
                      _buildField(
                        _password,
                        'Password *',
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      _buildField(_fullName, 'Full name *'),
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

















