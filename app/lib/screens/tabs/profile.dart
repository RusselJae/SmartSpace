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
import '../../widgets/loading_screen.dart';
import '../shell/tab_shell.dart';
import '../profile/addresses_screen.dart';
import '../profile/my_profile_screen.dart';
import '../profile/reviews.dart';
import '../profile/help_center_screen.dart';
import '../profile/about_us_screen.dart';
import '../profile/settings_screen.dart';
import '../profile/notifications_center_screen.dart';
import '../views/sign_in.dart';
import '../support/support_chat_screen.dart';
import '../../widgets/global_profile_sidebar.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final AuthService _auth = AuthService();
  final ProfileStorage _storage = ProfileStorage();
  final CartService _cart = CartService();

  ProfileExtras? _extras;
  Uint8List? _avatarBytes;
  String? _avatarPath;
  String? _avatarNetworkUrl;
  bool _loading = true;

  // NOTE:
  // The sidebar overlay is now global (mounted in TabShell), so the
  // Profile tab itself stays simple and just shows a lightweight
  // "Profile" surface behind the overlay.

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
      final serverUser = await MySQLDatabaseService().getUserById(user.id) ?? user;
      
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

  Widget _buildAvatar({required double radius}) {
    if (_avatarBytes != null) {
      return CircleAvatar(radius: radius, backgroundImage: MemoryImage(_avatarBytes!));
    }
    if (_avatarNetworkUrl != null) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(_avatarNetworkUrl!));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE0E0E0),
      child: Icon(
        CupertinoIcons.person_circle,
        size: radius * 1.15,
        color: Colors.grey.shade600,
      ),
    );
  }

  Widget _buildSidebarHeader(User user) {
    final extras = _extras;
    final name = user.fullName.isNotEmpty ? user.fullName : (extras?.username ?? 'Guest');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF8D6E63).withValues(alpha: 0.18),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () async {
                    await Navigator.of(context, rootNavigator: true)
                        .push(CupertinoPageRoute(builder: (_) => const MyProfileScreen()));
                    if (mounted) {
                      await _hydrate();
                    }
                  },
                  child: Text(
                    'View profile',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF8D6E63),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right-to-left visual: avatar on the far right.
          _buildAvatar(radius: 22),
        ],
      ),
    );
  }

  /// Menu tile with consistent styling - white background, no subtitle
  /// Wider tiles, no padding inside, minimal gaps between tiles, centered
  Widget _buildTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return Center(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Container(
          // Increased width for tiles - from 0.75 to 0.85 for larger tiles
          width: MediaQuery.of(context).size.width * 0.85,
          // Reduced padding inside tiles
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Reduced from 16/11 to 12/8
          // Reduced space between tiles by 3/4 of added size
          margin: const EdgeInsets.only(bottom: 6), // 5 + (5 * 0.25) = 5 + 1.25 = 6.25 ≈ 6
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFBCAAA4).withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Icon container with background - increased by half of reduced size
              Container(
                width: 25, // 19 + (31 - 19) * 0.5 = 19 + 6 = 25
                height: 25, // 19 + (31 - 19) * 0.5 = 19 + 6 = 25
                decoration: BoxDecoration(
                  color: (textColor ?? const Color(0xFF8D6E63)).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7), // 5 + (9 - 5) * 0.5 = 5 + 2 = 7
                ),
                child: Icon(icon, size: 15, color: textColor ?? const Color(0xFF8D6E63)), // 11 + (18 - 11) * 0.5 = 11 + 3.5 = 14.5 ≈ 15
              ),
              const SizedBox(width: 7), // 5 + (9 - 5) * 0.5 = 5 + 2 = 7
              // Title only - increased by half of reduced size
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 12, // 9 + (15 - 9) * 0.5 = 9 + 3 = 12
                    color: textColor ?? Colors.black,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Chevron arrow at the most right - increased by half of reduced size
              Icon(
                CupertinoIcons.chevron_forward,
                size: 11, // 8 + (13 - 8) * 0.5 = 8 + 2.5 = 10.5 ≈ 11
                color: textColor?.withValues(alpha: 0.5) ?? Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Profile header with avatar, name, and email
  /// Avatar at original size, name/email slightly larger with less gap, Edit Profile button half width
  Widget _buildHeader(User user) {
    final extras = _extras;
    // Avatar at increased size (increased by half of reduced size)
    final avatar = _buildAvatar(radius: 35);

    return Column(
      children: [
        avatar,
        const SizedBox(height: 7), // 5 + (9 - 5) * 0.5 = 5 + 2 = 7
        // User's full name - increased by half of reduced size
        Text(
          user.fullName.isNotEmpty ? user.fullName : (extras?.username ?? 'Guest'),
          style: GoogleFonts.poppins(
            fontSize: 15, // 11 + (18 - 11) * 0.5 = 11 + 3.5 = 14.5 ≈ 15
            fontWeight: FontWeight.w600,
            color: Colors.black,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 3), // 2 + (3 - 2) * 0.5 = 2 + 0.5 = 2.5 ≈ 3
        // User's email address - increased by half of reduced size
        Text(
          user.email,
          style: GoogleFonts.poppins(
            fontSize: 12, // 9 + (15 - 9) * 0.5 = 9 + 3 = 12
            fontWeight: FontWeight.w400,
            color: Colors.black87,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 13), // 12 + (4 * 0.25) = 12 + 1 = 13
        // Edit Profile button - modern brown color matching the app's design system, rounded corners, half width
        // Following Apple's Human Interface Guidelines for button design
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () async {
            await Navigator.of(context, rootNavigator: true)
                .push(CupertinoPageRoute(builder: (_) => const MyProfileScreen()));
            // Refresh profile data after returning from My Profile screen
            if (mounted) {
              await _hydrate();
            }
          },
          child: Container(
            // Reduced button width
            width: MediaQuery.of(context).size.width * 0.28, // Reduced from 0.35 to 0.28
            padding: const EdgeInsets.symmetric(vertical: 8), // Reduced from 11 to 8
            decoration: BoxDecoration(
              color: const Color(0xFF8D6E63), // Rich brown primary color matching the app's design system
              borderRadius: BorderRadius.circular(8), // Reduced from 11 to 8
            ),
            child: Text(
              'Edit Profile',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12, // Reduced from 14 to 12
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Menu items with consistent tile styling - grouped with divider
  /// Group 1: Address, Reviews
  /// Group 2: Help Center, About Us, Logout
  Widget _buildButtons(User user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Group 1: Address, Reviews
        // Address - using map pin icon
        _buildTile(
          icon: CupertinoIcons.location,
          title: 'Address',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (_) => const AddressesScreen()),
          ),
        ),
        // Reviews - using star circle icon
        _buildTile(
          icon: CupertinoIcons.star_circle,
          title: 'Reviews',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (_) => const ReviewsScreen()),
          ),
        ),
        // Group 2: Help Center, About Us, Logout
        // Help Center - using headset icon
        _buildTile(
          icon: CupertinoIcons.headphones,
          title: 'Help Center',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (_) => const HelpCenterScreen()),
          ),
        ),
        // Support chat - direct customer support messaging
        _buildTile(
          icon: CupertinoIcons.chat_bubble_2,
          title: 'Support Chat',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (_) => const SupportChatScreen()),
          ),
        ),
        _buildTile(
          icon: CupertinoIcons.bell,
          title: 'Notifications',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (_) => const NotificationsCenterScreen()),
          ),
        ),
        // About Us - using info circle icon
        _buildTile(
          icon: CupertinoIcons.info_circle,
          title: 'About Us',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (_) => const AboutUsScreen()),
          ),
        ),
        // Settings - for account/password related actions
        _buildTile(
          icon: CupertinoIcons.gear,
          title: 'Settings',
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
        // Logout - using same tile style with red text
        _buildTile(
          icon: CupertinoIcons.arrow_right_circle,
          title: 'Logout',
          textColor: CupertinoColors.systemRed,
          onTap: _handleLogout,
        ),
      ],
    );
  }

  Future<void> _handleLogout() async {
    final user = _auth.currentUser;
    setState(() => _loading = true);
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
    // Show loading screen before navigating to home
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      CupertinoPageRoute(
        builder: (_) => const LoadingScreen(
          message: 'Signing out...',
          nextRoute: TabShell.route,
        ),
      ),
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
    // Medium brown color for text
    const mediumBrown = Color(0xFF8D6E63);
    
    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white, // Changed from lightBrown to white
        border: Border(
          bottom: BorderSide(
            color: mediumBrown.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        middle: Text(
          'Profile',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: mediumBrown,
          ),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : user == null
                ? _buildGuest()
                : Center(
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => GlobalProfileSidebarController.instance.open(),
                      child: Text(
                        'Profile menu',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.black.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}


