import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../models/admin.dart';
import '../../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';
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
  final TextEditingController _searchController = TextEditingController();
  
  List<Admin> _admins = const [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

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
    if (_searchQuery.isEmpty) return _admins;
    
    final query = _searchQuery.toLowerCase();
    return _admins.where((admin) {
      return admin.fullName.toLowerCase().contains(query) ||
             admin.email.toLowerCase().contains(query);
    }).toList();
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
    final data = await showDialog<_AdminFormData>(
      context: context,
      builder: (_) => const _AdminFormDialog(),
    );
    if (data == null) return;
    
    try {
      await _db.createAdmin(
        email: data.email,
        password: data.password,
        fullName: data.fullName,
      );
      if (!mounted) return;
      Toast.success(context, 'Admin created successfully');
      await _loadAdmins();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to create admin: $e');
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
    return AlertDialog(
      title: const Text('Admin Details'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: 'Full Name', value: admin.fullName),
            const SizedBox(height: 12),
            _DetailRow(label: 'Email', value: admin.email),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Helper widget for displaying a label-value pair in the details dialog.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.black,
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
  });

  final String email;
  final String password;
  final String fullName;
}

/// Dialog form for creating a new admin account.
class _AdminFormDialog extends StatefulWidget {
  const _AdminFormDialog();

  @override
  State<_AdminFormDialog> createState() => _AdminFormDialogState();
}

class _AdminFormDialogState extends State<_AdminFormDialog> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _fullName = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  void _submit() {
    if (_email.text.trim().isEmpty ||
        _password.text.isEmpty ||
        _fullName.text.trim().isEmpty) {
      Toast.warning(context, 'All fields are required');
      return;
    }

    if (_password.text.length < 6) {
      Toast.warning(context, 'Password must be at least 6 characters long');
      return;
    }

    final data = _AdminFormData(
      email: _email.text.trim(),
      password: _password.text,
      fullName: _fullName.text.trim(),
    );
    Navigator.of(context).pop(data);
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
    return AlertDialog(
      title: const Text('Add admin'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(_email, 'Email *', keyboardType: TextInputType.emailAddress),
              _buildField(
                _password,
                'Password *',
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              _buildField(_fullName, 'Full name *'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Password must be at least 6 characters. Credentials cannot be changed after creation.',
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8D6E63),
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

















