import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../auth/admin_permissions.dart';
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
  bool _sendingReset = false;

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  bool _emailVerified = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController();
    _lastName = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    await _auth.initialize();
    final full = (_auth.currentFullName ?? '').trim();
    final parts = full.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) {
      _firstName.text = '';
      _lastName.text = '';
    } else if (parts.length == 1) {
      _firstName.text = parts.first;
      _lastName.text = '';
    } else {
      _firstName.text = parts.first;
      _lastName.text = parts.sublist(1).join(' ');
    }

    final adminId = (_auth.currentAdminId ?? '').trim();
    if (adminId.isNotEmpty) {
      try {
        final remote = await _db.getAdminById(adminId);
        if (!mounted) return;
        setState(() {
          _emailVerified = remote.emailVerified;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loadError = 'Could not refresh verification status.';
          _emailVerified = true;
        });
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  String get _combinedName {
    final a = _firstName.text.trim();
    final b = _lastName.text.trim();
    if (a.isEmpty && b.isEmpty) return '';
    if (b.isEmpty) return a;
    if (a.isEmpty) return b;
    return '$a $b';
  }

  Future<void> _save() async {
    final adminId = _auth.currentAdminId;
    if (adminId == null || adminId.trim().isEmpty) {
      Toast.error(context, 'No admin session found');
      return;
    }

    final name = _combinedName;
    if (name.isEmpty) {
      Toast.error(context, 'Enter at least a first or last name');
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

  Future<void> _requestPasswordResetEmail() async {
    final email = (_auth.currentEmail ?? '').trim();
    if (email.isEmpty) {
      Toast.error(context, 'No email on this session');
      return;
    }
    setState(() => _sendingReset = true);
    try {
      await _auth.requestPasswordReset(email: email);
      if (!mounted) return;
      Toast.success(context, 'If this account exists, a reset link was sent to your email.');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, '$e');
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Widget _profileHeaderRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Details',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'How you appear in the admin console. Email stays tied to your login.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: const Color(0xFF8D6E63).withValues(alpha: 0.2),
              child: Text(
                _avatarLetters(),
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5C4033),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Avatar uses your initials',
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      ],
    );
  }

  String _avatarLetters() {
    final a = _firstName.text.trim();
    final b = _lastName.text.trim();
    if (a.isNotEmpty && b.isNotEmpty) {
      return '${a[0]}${b[0]}'.toUpperCase();
    }
    final full = _combinedName;
    if (full.length >= 2) return full.substring(0, 2).toUpperCase();
    if (full.isNotEmpty) return full[0].toUpperCase();
    return '?';
  }

  Widget _nameCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Legal name',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Submit', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _firstName,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'First name',
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lastName,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Last name',
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Use your first and last name as they appear on your government-issued ID.',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, thickness: 1, color: Colors.grey.shade200);

  Widget _emailRow() {
    final email = (_auth.currentEmail ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Email address', style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            email.isEmpty ? '—' : email,
                            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (_emailVerified) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.verified_rounded, size: 20, color: Colors.green.shade600),
                          Text(
                            ' Verified',
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade700),
                          ),
                        ],
                      ],
                    ),
                    if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _loadError!,
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.orange.shade800),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                'Read only',
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.black38),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Password', style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 4),
                Text(
                  'Use a secure link sent to your email — same flow as “Forgot password” on the login screen.',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45, height: 1.35),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _sendingReset ? null : _requestPasswordResetEmail,
            child: _sendingReset
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Email reset link', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _roleRow() {
    final role = (_auth.currentRole ?? '').trim();
    final label = role.isEmpty ? '—' : role.replaceAll('_', ' ');
    final permCount = AdminPermissions.permissionsForRole(role).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Role', style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 4),
                Text(label, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(
                  '$permCount permissions from your assigned role',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        _profileHeaderRow(),
        const SizedBox(height: 20),
        _nameCard(context),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              _emailRow(),
              _divider(),
              _passwordRow(),
              _divider(),
              _roleRow(),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildContent(context),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        title: Text(AdminProfilePage.title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Save', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: _buildContent(context),
      ),
    );
  }
}
