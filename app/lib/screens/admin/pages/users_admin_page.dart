import 'package:flutter/material.dart';

import '../../../models/user.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';

class UsersAdminPage extends StatefulWidget {
  const UsersAdminPage({super.key});

  @override
  State<UsersAdminPage> createState() => _UsersAdminPageState();
}

class _UsersAdminPageState extends State<UsersAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  List<User> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _db.getAllUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Customers',
          actions: [
            AdminToolbarAction(label: 'Invite user', icon: Icons.person_add_alt, primary: true, onPressed: () {}),
          ],
          trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _users.isEmpty
                  ? const Center(child: Text('No users yet.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return Card(
                          child: ListTile(
                            leading: _InitialBadge(text: user.fullName.substring(0, 2).toUpperCase()),
                            title: Text(user.fullName),
                            subtitle: Text(user.email),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${user.preferredStyle} • \$${user.minBudget.toStringAsFixed(0)} - \$${user.maxBudget.toStringAsFixed(0)}'),
                                Text('Orders: ${user.orderIds.length}', style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: _users.length,
                    ),
        ),
      ],
    );
  }
}

class _InitialBadge extends StatelessWidget {
  const _InitialBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.brown.shade200,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

