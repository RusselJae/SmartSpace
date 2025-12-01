import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/user.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';

/// User management page with search, filtering, and detailed user views.
/// Follows Apple HIG with clean layouts and smooth interactions.
class UsersAdminPage extends StatefulWidget {
  const UsersAdminPage({super.key});

  @override
  State<UsersAdminPage> createState() => _UsersAdminPageState();
}

class _UsersAdminPageState extends State<UsersAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final TextEditingController _searchController = TextEditingController();
  
  List<User> _users = [];
  bool _loading = true;
  String _searchQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Loads all users from the database with proper error handling.
  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _db.getAllUsers();
      // Fetch orders to get order IDs per user
      final orders = await _db.getAllOrders();
      final orderIdsByUser = <String, List<String>>{};
      for (final order in orders) {
        orderIdsByUser.putIfAbsent(order.userId, () => []).add(order.id);
      }
      // Update users with actual order IDs
      final usersWithOrders = users.map((user) {
        final orderIds = orderIdsByUser[user.id] ?? [];
        return user.copyWith(orderIds: orderIds);
      }).toList();
      if (!mounted) return;
      setState(() {
        _users = usersWithOrders;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load users: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Filters users by search query for fast, responsive search.
  List<User> get _filtered {
    if (_searchQuery.isEmpty) return _users;
    
    return _users.where((user) {
      return user.fullName.toLowerCase().contains(_searchQuery) ||
             user.email.toLowerCase().contains(_searchQuery) ||
             (user.phoneNumber?.toLowerCase().contains(_searchQuery) ?? false);
    }).toList();
  }

  /// Shows detailed user information in a centered modal dialog.
  void _showUserDetails(User user) {
    showDialog(
      context: context,
      builder: (context) => _UserDetailsDialog(user: user),
    );
  }

  Future<void> _createUser() async {
    final data = await showDialog<_UserFormData>(
      context: context,
      builder: (_) => _UserFormDialog(),
    );
    if (data == null) return;
    try {
      await _db.createUser(
        email: data.email,
        fullName: data.fullName,
        username: data.fullName,
        phoneNumber: data.phoneNumber?.isEmpty ?? true ? null : data.phoneNumber,
        gender: null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User created successfully'), backgroundColor: Colors.green),
      );
      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create user: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, or phone...',
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
                      borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
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
                onPressed: _createUser,
                icon: const Icon(Icons.person_add_alt_outlined),
                label: const Text('Add user'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8D6E63),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadUsers,
                tooltip: 'Refresh users',
              ),
            ],
          ),
        ),
        AdminToolbar(
          title: 'Customers',
          actions: const [],
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
                  Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Text(
                '${filtered.length} ${filtered.length == 1 ? 'customer' : 'customers'}',
                style: GoogleFonts.poppins(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
              const Spacer(),
              if (_users.isNotEmpty)
                Text(
                  '${_users.where((u) => u.orderIds.isNotEmpty).length} with orders',
                  style: GoogleFonts.poppins(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    decoration: TextDecoration.none,
                  ),
                ),
            ],
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
                          Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No customers match your search'
                                : 'No customers yet',
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
                          const _UsersHeaderRow(),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final user = filtered[index];
                                return _UsersTableRow(
                                  user: user,
                                  onTap: () => _showUserDetails(user),
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

class _UsersHeaderRow extends StatelessWidget {
  const _UsersHeaderRow();

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
          Expanded(flex: 2, child: Text('Phone', style: style)),
          Expanded(flex: 2, child: Text('Joined', style: style)),
          Expanded(flex: 2, child: Text('Orders', style: style)),
          const SizedBox(width: 80),
        ],
      ),
    );
  }
}

class _UsersTableRow extends StatelessWidget {
  const _UsersTableRow({required this.user, required this.onTap});

  final User user;
  final VoidCallback onTap;

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
                user.fullName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                user.email,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(user.phoneNumber ?? '-'),
            ),
            Expanded(
              flex: 2,
              child: Text(user.createdAt.toLocal().toString().substring(0, 10)),
            ),
            Expanded(
              flex: 2,
              child: Text('${user.orderIds.length}'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onTap,
              child: const Text('More'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered dialog showing detailed user information.
class _UserDetailsDialog extends StatelessWidget {
  const _UserDetailsDialog({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
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
                  Text(
                    'Customer Details',
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const Spacer(),
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
                  children: [
                    _DetailRow(label: 'Name', value: user.fullName),
                    _DetailRow(label: 'Email', value: user.email),
                    if (user.username.isNotEmpty)
                      _DetailRow(label: 'Username', value: user.username),
                    if (user.phoneNumber != null)
                      _DetailRow(label: 'Phone', value: user.phoneNumber!),
                    if (user.gender != null)
                      _DetailRow(
                        label: 'Gender',
                        value: user.gender![0].toUpperCase() + user.gender!.substring(1),
                      ),
                    _DetailRow(
                      label: 'Joined',
                      value: user.createdAt.toLocal().toString().substring(0, 19),
                    ),
                    _DetailRow(
                      label: 'Last Login',
                      value: user.lastLoginAt.toLocal().toString().substring(0, 19),
                    ),
                    if (user.preferredStyle.isNotEmpty)
                      _DetailRow(label: 'Preferred Style', value: user.preferredStyle),
                    if (user.minBudget > 0 || user.maxBudget > 0)
                      _DetailRow(
                        label: 'Budget Range',
                        value: '₱${user.minBudget.toStringAsFixed(0)} - ₱${user.maxBudget.toStringAsFixed(0)}',
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Addresses',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (user.addresses.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'No addresses on file',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    else
                      ...user.addresses.where((a) => a.trim().isNotEmpty).map((address) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Text(
                                address.trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.black,
                                  fontSize: 15,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          )),
                    const SizedBox(height: 12),
                    Text(
                      'Orders',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${user.orderIds.length} ${user.orderIds.length == 1 ? 'order' : 'orders'}',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Wishlist',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${user.wishlistProductIds.length} ${user.wishlistProductIds.length == 1 ? 'item' : 'items'}',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim(),
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserFormData {
  _UserFormData({
    required this.email,
    required this.fullName,
    this.phoneNumber,
    this.addresses = const [],
    this.preferredStyle = '',
    this.minBudget = 0,
    this.maxBudget = 0,
  });

  final String email;
  final String fullName;
  final String? phoneNumber;
  final List<String> addresses;
  final String preferredStyle;
  final double minBudget;
  final double maxBudget;
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog();

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _phoneNumber = TextEditingController();
  final TextEditingController _addresses = TextEditingController();
  final TextEditingController _preferredStyle = TextEditingController();
  final TextEditingController _minBudget = TextEditingController();
  final TextEditingController _maxBudget = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _fullName.dispose();
    _phoneNumber.dispose();
    _addresses.dispose();
    _preferredStyle.dispose();
    _minBudget.dispose();
    _maxBudget.dispose();
    super.dispose();
  }

  void _submit() {
    if (_email.text.trim().isEmpty || _fullName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email and full name are required')),
      );
      return;
    }
    final addresses = _addresses.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final minBudget = double.tryParse(_minBudget.text.trim()) ?? 0;
    final maxBudget = double.tryParse(_maxBudget.text.trim()) ?? 0;
    final data = _UserFormData(
      email: _email.text.trim(),
      fullName: _fullName.text.trim(),
      phoneNumber: _phoneNumber.text.trim().isEmpty ? null : _phoneNumber.text.trim(),
      addresses: addresses,
      preferredStyle: _preferredStyle.text.trim(),
      minBudget: minBudget,
      maxBudget: maxBudget,
    );
    Navigator.of(context).pop(data);
  }

  Widget _buildField(TextEditingController controller, String label, {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF6D4C41)),
          filled: true,
          fillColor: const Color(0xFFF8F8F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add user'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(_email, 'Email *', keyboardType: TextInputType.emailAddress),
              _buildField(_fullName, 'Full name *'),
              _buildField(_phoneNumber, 'Phone number', keyboardType: TextInputType.phone),
              _buildField(_addresses, 'Addresses (comma separated)'),
              _buildField(_preferredStyle, 'Preferred style'),
              _buildField(_minBudget, 'Min budget', keyboardType: TextInputType.number),
              _buildField(_maxBudget, 'Max budget', keyboardType: TextInputType.number),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
