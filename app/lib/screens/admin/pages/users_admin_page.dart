import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/address_entry.dart';
import '../../../models/user.dart';
import '../../../services/admin_support_inbox_navigation_service.dart';
import '../../../services/mysql_database_service.dart';
import '../admin_routes.dart';
import '../widgets/admin_toolbar.dart';
import '../widgets/admin_anchored_popover.dart';
import '../../../widgets/toast.dart';

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
  final GlobalKey _filterAnchorKey = GlobalKey();
  
  List<User> _users = [];
  bool _loading = true;
  String _searchQuery = '';
  String _sortBy = 'newest';
  bool _onlyWithOrders = false;
  String? _error;

  static const int _pageSize = 10;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _pageIndex = 0;
      });
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
    var filtered = _users.where((user) {
      return user.fullName.toLowerCase().contains(_searchQuery) ||
             user.email.toLowerCase().contains(_searchQuery) ||
             (user.phoneNumber?.toLowerCase().contains(_searchQuery) ?? false);
    }).toList(growable: false);
    if (_searchQuery.isEmpty) {
      filtered = List<User>.from(_users);
    }
    if (_onlyWithOrders) {
      filtered = filtered.where((u) => u.orderIds.isNotEmpty).toList(growable: false);
    }
    switch (_sortBy) {
      case 'oldest':
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'name_az':
        filtered.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
        break;
      case 'name_za':
        filtered.sort((a, b) => b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase()));
        break;
      case 'newest':
      default:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    return filtered;
  }

  int get _activeFilterCount => (_sortBy != 'newest' ? 1 : 0) + (_onlyWithOrders ? 1 : 0);

  void _showUserFilterPopover() {
    var tempSort = _sortBy;
    var tempOnlyWithOrders = _onlyWithOrders;
    AdminAnchoredPopover.show<void>(
      context: context,
      anchorKey: _filterAnchorKey,
      width: 360,
      height: 280,
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
                        'Filter Customers',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
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
                  const Text(
                    'Sort by',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
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
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    value: tempOnlyWithOrders,
                    onChanged: (v) => setModalState(() => tempOnlyWithOrders = v),
                    title: const Text('Only Customers With Orders'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => setModalState(() {
                          tempSort = 'newest';
                          tempOnlyWithOrders = false;
                        }),
                        child: const Text('Reset'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _sortBy = tempSort;
                            _onlyWithOrders = tempOnlyWithOrders;
                            _pageIndex = 0;
                          });
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
      Toast.success(context, 'User created successfully');
      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to create user: $e');
    }
  }

  Future<void> _openSupportForUser(User user) async {
    try {
      await _db.getOrCreateSupportConversation(user.id, email: user.email);
      AdminSupportInboxNavigationService.instance.pendingUserId = user.id;
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AdminRoutes.support);
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to open support conversation: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    final totalCount = filtered.length;
    final pageCount = (totalCount / _pageSize).ceil();
    final safePageIndex = pageCount <= 1 ? 0 : _pageIndex.clamp(0, pageCount - 1).toInt();
    final start = safePageIndex * _pageSize;
    final end = (start + _pageSize) > totalCount ? totalCount : (start + _pageSize);
    final pageItems = totalCount == 0 ? const <User>[] : filtered.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              Stack(
                children: [
                  SizedBox(
                    key: _filterAnchorKey,
                    child: IconButton.outlined(
                      onPressed: _showUserFilterPopover,
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
                              itemCount: pageItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final user = pageItems[index];
                                return _UsersTableRow(
                                  user: user,
                                  onTap: () => _showUserDetails(user),
                                  onMessageTap: () => _openSupportForUser(user),
                                );
                              },
                            ),
                          ),
                          if (pageCount > 1)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.chevron_left),
                                        onPressed: safePageIndex > 0
                                            ? () => setState(() => _pageIndex = safePageIndex - 1)
                                            : null,
                                        tooltip: 'Previous page',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.chevron_right),
                                        onPressed: safePageIndex < pageCount - 1
                                            ? () => setState(() => _pageIndex = safePageIndex + 1)
                                            : null,
                                        tooltip: 'Next page',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Page ${safePageIndex + 1} of $pageCount',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black54,
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
  const _UsersTableRow({
    required this.user,
    required this.onTap,
    required this.onMessageTap,
  });

  final User user;
  final VoidCallback onTap;
  final VoidCallback onMessageTap;

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
            IconButton(
              onPressed: onMessageTap,
              tooltip: 'Open support chat',
              icon: const Icon(Icons.forum_outlined),
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
  static const double _detailFontSize = 16;

  String _formatDefaultAddress(List<AddressEntry> addresses) {
    if (addresses.isEmpty) return 'No addresses on file';
    final selected = addresses.firstWhere(
      (entry) => entry.isDefault,
      orElse: () => addresses.first,
    );
    final parts = <String>[
      selected.street.trim(),
      selected.region.trim(),
      selected.postalCode.trim(),
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'No addresses on file' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 40),
                      Expanded(
                        child: Text(
                          'Customer Details',
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
                  const SizedBox(height: 10),
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: (user.avatarUrl != null &&
                            user.avatarUrl!.trim().isNotEmpty)
                        ? NetworkImage(user.avatarUrl!.trim())
                        : null,
                    child: (user.avatarUrl == null || user.avatarUrl!.trim().isEmpty)
                        ? Icon(Icons.person, size: 38, color: Colors.grey[600])
                        : null,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Name',
                      value: user.fullName,
                      fontSize: _detailFontSize,
                    ),
                    _DetailRow(
                      label: 'Email',
                      value: user.email,
                      fontSize: _detailFontSize,
                    ),
                    if (user.username.isNotEmpty)
                      _DetailRow(
                        label: 'Username',
                        value: user.username,
                        fontSize: _detailFontSize,
                      ),
                    if (user.phoneNumber != null)
                      _DetailRow(
                        label: 'Phone',
                        value: user.phoneNumber!,
                        fontSize: _detailFontSize,
                      ),
                    if (user.gender != null)
                      _DetailRow(
                        label: 'Gender',
                        value: user.gender![0].toUpperCase() + user.gender!.substring(1),
                        fontSize: _detailFontSize,
                      ),
                    _DetailRow(
                      label: 'Joined',
                      value: user.createdAt.toLocal().toString().substring(0, 19),
                      fontSize: _detailFontSize,
                    ),
                    _DetailRow(
                      label: 'Last Login',
                      value: user.lastLoginAt.toLocal().toString().substring(0, 19),
                      fontSize: _detailFontSize,
                    ),
                    if (user.preferredStyle.isNotEmpty)
                      _DetailRow(
                        label: 'Preferred Style',
                        value: user.preferredStyle,
                        fontSize: _detailFontSize,
                      ),
                    if (user.minBudget > 0 || user.maxBudget > 0)
                      _DetailRow(
                        label: 'Budget Range',
                        value: '₱${user.minBudget.toStringAsFixed(0)} - ₱${user.maxBudget.toStringAsFixed(0)}',
                        fontSize: _detailFontSize,
                      ),
                    FutureBuilder<List<AddressEntry>>(
                      future: MySQLDatabaseService().getAddresses(user.id),
                      builder: (context, snapshot) {
                        final addressValue = snapshot.hasData
                            ? _formatDefaultAddress(snapshot.data!)
                            : 'Loading...';
                        return _DetailRow(
                          label: 'Address',
                          value: addressValue,
                          fontSize: _detailFontSize,
                        );
                      },
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
  const _DetailRow({
    required this.label,
    required this.value,
    this.fontSize = 16,
  });

  final String label;
  final String value;
  final double fontSize;

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
              '$label:',
              style: GoogleFonts.poppins(
                color: Colors.grey[600],
                fontSize: fontSize,
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
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
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
  bool _submitting = false;

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
    if (_submitting) return;
    if (_email.text.trim().isEmpty || _fullName.text.trim().isEmpty) {
      Toast.warning(context, 'Email and full name are required');
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
      padding: const EdgeInsets.only(bottom: 12),
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
    // Constrained modal matching admin container—not full screen.
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
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
                        'Add user',
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
                      _buildField(_fullName, 'Full name *'),
                      _buildField(_phoneNumber, 'Phone number', keyboardType: TextInputType.phone),
                      _buildField(_addresses, 'Addresses (comma separated)'),
                      _buildField(_preferredStyle, 'Preferred style'),
                      Row(
                        children: [
                          Expanded(child: _buildField(_minBudget, 'Min budget', keyboardType: TextInputType.number)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildField(_maxBudget, 'Max budget', keyboardType: TextInputType.number)),
                        ],
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
                      onPressed: _submitting
                          ? null
                          : () async {
                              setState(() => _submitting = true);
                              try {
                                _submit();
                              } finally {
                                if (mounted) setState(() => _submitting = false);
                              }
                            },
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8D6E63)),
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create'),
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
