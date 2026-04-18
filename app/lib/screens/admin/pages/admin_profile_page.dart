import 'package:flutter/material.dart';

import '../../../services/admin_auth_service.dart';
import '../../../services/mysql_database_service.dart';
import '../../../widgets/toast.dart';

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key, this.embedded = false});

  static const String title = 'Profile Information';

  /// When true, renders content only (no Scaffold/AppBar) for use in modals.
  final bool embedded;

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  final AdminAuthService _auth = AdminAuthService();
  final MySQLDatabaseService _db = MySQLDatabaseService();

  bool _loading = true;
  bool _saving = false;

  late final TextEditingController _fullName;

  @override
  void initState() {
    super.initState();
    _fullName = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _auth.initialize();
    _fullName.text = (_auth.currentFullName ?? '').trim();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final adminId = _auth.currentAdminId;
    if (adminId == null || adminId.trim().isEmpty) {
      Toast.error(context, 'No admin session found');
      return;
    }

    final name = _fullName.text.trim();
    if (name.isEmpty) {
      Toast.error(context, 'Full name is required');
      return;
    }

    setState(() => _saving = true);
    try {
      await _db.updateAdmin(adminId: adminId, fullName: name);
      await _auth.updateLocalProfile(fullName: name);
      if (!mounted) return;
      Toast.success(context, 'Profile updated');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to update profile: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildContent(BuildContext context) {
    final email = (_auth.currentEmail ?? '').trim();
    final adminId = (_auth.currentAdminId ?? '').trim();
    final signedInAt = _auth.signedInAt;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Email', value: email.isEmpty ? '—' : email),
                      const SizedBox(height: 8),
                      _InfoRow(label: 'Admin ID', value: adminId.isEmpty ? '—' : adminId),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'Role',
                        value: (_auth.currentRole ?? '—').replaceAll('_', ' '),
                      ),
                      if (signedInAt != null) ...[
                        const SizedBox(height: 8),
                        _InfoRow(label: 'Signed in', value: signedInAt.toLocal().toString()),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fullName,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          hintText: 'Enter your name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Email and password changes are handled by admin management.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.embedded
          ? const Center(child: CircularProgressIndicator())
          : const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildContent(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(AdminProfilePage.title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _buildContent(context),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]);
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    return Row(
      children: [
        SizedBox(width: 88, child: Text(label, style: labelStyle)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, style: valueStyle, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

