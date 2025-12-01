import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/profile_extras.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/mysql_database_service.dart';
import '../../services/profile_storage.dart';
import '../../services/wishlist_service.dart';
import '../shell/tab_shell.dart';
import '../profile/addresses_screen.dart';
import '../profile/my_profile_screen.dart';
import '../profile/orders.dart';
import '../profile/reviews.dart';
import '../views/sign_in.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final AuthService _auth = AuthService();
  final ProfileStorage _storage = ProfileStorage();
  final CartService _cart = CartService();
  final WishlistService _wishlist = WishlistService();

  ProfileExtras? _extras;
  Uint8List? _avatarBytes;
  String? _avatarPath;
  String? _avatarNetworkUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    
    // Reload user from server to get latest avatar
    try {
      final serverUsers = await MySQLDatabaseService().getAllUsers();
      final serverUser = serverUsers.firstWhere(
        (u) => u.id == user.id,
        orElse: () => user,
      );
      
      final extras = await _storage.loadExtras(serverUser);
      _avatarPath = extras.avatarPath;
      Uint8List? avatarBytes;
      String? networkUrl;
      
      // Try local file first
      if (_avatarPath != null && await File(_avatarPath!).exists()) {
        try {
          avatarBytes = await File(_avatarPath!).readAsBytes();
        } catch (_) {
          // If local file fails, try server avatar
          avatarBytes = null;
        }
      }
      
      // If no local file, try server avatar
      if (avatarBytes == null && serverUser.avatarUrl != null) {
        final avatarUrl = serverUser.avatarUrl!;
        if (avatarUrl.startsWith('data:image')) {
          try {
            final base64Data = avatarUrl.split(',').last;
            avatarBytes = base64Decode(base64Data);
          } catch (_) {
            avatarBytes = null;
          }
        } else {
          networkUrl = avatarUrl;
        }
      }
      
      if (mounted) {
        setState(() {
          _extras = extras;
          _avatarBytes = avatarBytes;
          _avatarNetworkUrl = networkUrl;
          _loading = false;
        });
      }
    } catch (e) {
      // Fallback to local storage if server fails
      final extras = await _storage.loadExtras(user);
      _avatarPath = extras.avatarPath;
      Uint8List? avatarBytes;
      if (_avatarPath != null && await File(_avatarPath!).exists()) {
        avatarBytes = await File(_avatarPath!).readAsBytes();
      }
      if (mounted) {
        setState(() {
          _extras = extras;
          _avatarBytes = avatarBytes;
          _avatarNetworkUrl = null;
          _loading = false;
        });
      }
    }
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGroupedBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF8D6E63).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF8D6E63)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_forward, size: 18, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(User user) {
    final extras = _extras;
    final avatar = _avatarBytes != null
        ? CircleAvatar(radius: 40, backgroundImage: MemoryImage(_avatarBytes!))
        : _avatarNetworkUrl != null
            ? CircleAvatar(radius: 40, backgroundImage: NetworkImage(_avatarNetworkUrl!))
            : CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFFE0E0E0),
                child: Icon(CupertinoIcons.person_circle, size: 48, color: Colors.grey.shade600),
              );

    return Column(
      children: [
        avatar,
        const SizedBox(height: 12),
        // Force a neutral, non-linkified presentation so Android/iOS don't
        // auto-style the name like a tappable hyperlink (which caused the
        // red text + yellow underline in the screenshots).
        Text(
          user.fullName.isNotEmpty ? user.fullName : (extras?.username ?? 'Guest'),
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  Widget _buildButtons(User user) {
    return Column(
      children: [
        _buildTile(
          icon: CupertinoIcons.person_crop_circle,
          title: 'My Profile',
          subtitle: 'View and edit account info',
          onTap: () async {
            // Use rootNavigator to hide tab bar when navigating to my profile
            await Navigator.of(context, rootNavigator: true)
                .push(CupertinoPageRoute(builder: (_) => const MyProfileScreen()));
            // Refresh profile data after returning from My Profile screen
            if (mounted) {
              await _hydrate();
            }
          },
        ),
        _buildTile(
          icon: CupertinoIcons.location_solid,
          title: 'Addresses',
          subtitle: 'Manage Philippine addresses',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (_) => const AddressesScreen()),
          ),
        ),
        _buildTile(
          icon: CupertinoIcons.cube_box_fill,
          title: 'Orders & Tracking',
          subtitle: 'Track deliveries and status',
          onTap: () async {
            // Use rootNavigator to hide tab bar when navigating to orders
            await Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute(builder: (_) => const OrdersScreen()),
            );
            // Refresh orders when returning from the screen
            // The OrdersScreen will reload on initState, but this ensures fresh data
          },
        ),
        _buildTile(
          icon: CupertinoIcons.star_circle,
          title: 'My Reviews',
          subtitle: 'View and manage reviews',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (_) => const ReviewsScreen()),
          ),
        ),
        const SizedBox(height: 12),
        CupertinoButton(
          color: CupertinoColors.systemRed,
          onPressed: _handleLogout,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Logout',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(CupertinoIcons.power, color: Colors.white, size: 18),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleLogout() async {
    final user = _auth.currentUser;
    setState(() => _loading = true);
    _wishlist.clear();
    if (user != null) {
      await _storage.clearUserData(user.id);
    }
    await _auth.signOut();
    await _cart.syncWithUser(null);
    if (!mounted) return;
    setState(() {
      _extras = null;
      _avatarBytes = null;
      _avatarPath = null;
      _avatarNetworkUrl = null;
      _loading = false;
    });
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      TabShell.route,
      (route) => false,
    );
  }

  Widget _buildGuest() {
    return Center(
      child: SingleChildScrollView(
        // Add bottom padding to prevent content from being blocked by tab bar
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
        child: Column(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.person_crop_circle_badge_plus,
                  size: 60, color: Color(0xFF8D6E63)),
            ),
            const SizedBox(height: 24),
            Text(
              'Create a profile to save your addresses, track orders, and leave reviews.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute(
                    builder: (_) => const SignInScreen(),
                    fullscreenDialog: true,
                  ),
                );
              },
              child: Text(
                'Sign In / Sign Up',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        middle: Text('My Account', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : user == null
                ? _buildGuest()
                : SingleChildScrollView(
                    // Add bottom padding to prevent content from being blocked by tab bar
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildHeader(user),
                        const SizedBox(height: 24),
                        _buildButtons(user),
                      ],
                    ),
                  ),
      ),
    );
  }
}

