import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/profile_extras.dart';
import '../models/user.dart';
import '../models/customer_notification.dart';
import '../screens/profile/addresses_screen.dart';
import '../screens/profile/about_us_screen.dart';
import '../screens/profile/help_center_screen.dart';
import '../screens/profile/my_profile_screen.dart';
import '../screens/profile/reviews.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/profile/notifications_center_screen.dart';
import '../screens/shell/tab_shell.dart';
import '../screens/support/support_chat_screen.dart';
import '../screens/views/made_to_order_request_screen.dart';
import '../screens/views/my_made_to_order_requests_screen.dart';
import '../screens/views/sign_in.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/mysql_database_service.dart';
import '../services/profile_storage.dart';
import '../services/support_notifications_service.dart';
import '../services/customer_notifications_service.dart';
import '../widgets/loading_screen.dart';

/// =============================================================
/// GlobalProfileSidebarController
/// -------------------------------------------------------------
/// A lightweight controller so the bottom tab bar can open/close
/// the right sidebar without needing direct access to internal
/// widget state.
/// =============================================================
class GlobalProfileSidebarController {
  GlobalProfileSidebarController._();

  static final GlobalProfileSidebarController instance = GlobalProfileSidebarController._();

  final ValueNotifier<bool> isOpen = ValueNotifier<bool>(false);

  void open() => isOpen.value = true;
  void close() => isOpen.value = false;
  void toggle() => isOpen.value = !isOpen.value;
}

/// =============================================================
/// GlobalProfileSidebarOverlay
/// -------------------------------------------------------------
/// A right-to-left slide-in navigation panel that can sit above
/// the entire app, including the bottom tab bar.
///
/// - Height: 100% (Positioned.fill from TabShell)
/// - Collapse: only when tapping OUTSIDE the sidebar (scrim)
/// - Open: typically when the Profile tab is tapped
/// =============================================================
class GlobalProfileSidebarOverlay extends StatefulWidget {
  const GlobalProfileSidebarOverlay({super.key, required this.controller});

  final GlobalProfileSidebarController controller;

  @override
  State<GlobalProfileSidebarOverlay> createState() => _GlobalProfileSidebarOverlayState();
}

class _GlobalProfileSidebarOverlayState extends State<GlobalProfileSidebarOverlay> {
  final AuthService _auth = AuthService();
  final ProfileStorage _storage = ProfileStorage();
  final CartService _cart = CartService();
  final SupportNotificationsService _supportNotifications = SupportNotificationsService.instance;
  final CustomerNotificationsService _customerNotifications = CustomerNotificationsService.instance;

  ProfileExtras? _extras;
  Uint8List? _avatarBytes;
  String? _avatarNetworkUrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.isOpen.addListener(_onOpenChanged);
  }

  @override
  void dispose() {
    widget.controller.isOpen.removeListener(_onOpenChanged);
    super.dispose();
  }

  void _onOpenChanged() {
    if (!mounted) return;

    // When the sidebar opens, hydrate so avatar/name are fresh.
    // We keep this cheap: only hydrate if authenticated.
    if (widget.controller.isOpen.value && _auth.currentUser != null) {
      _hydrate();
      _supportNotifications.startPolling();
    } else if (!widget.controller.isOpen.value) {
      _supportNotifications.stopPolling();
    }

    setState(() {});
  }

  Future<void> _hydrate() async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (mounted) setState(() => _loading = true);
    try {
      final serverUser = await MySQLDatabaseService().getUserById(user.id) ?? user;
      final extras = await _storage.loadExtras(serverUser);

      Uint8List? avatarBytes;
      String? networkUrl;

      // Prefer local file if present (same behavior as ProfileTab).
      if (extras.avatarPath != null && await File(extras.avatarPath!).exists()) {
        try {
          avatarBytes = await File(extras.avatarPath!).readAsBytes();
        } catch (_) {
          avatarBytes = null;
        }
      }

      // Otherwise fall back to server avatarUrl (data URI or network URL).
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

      if (!mounted) return;
      setState(() {
        _extras = extras;
        _avatarBytes = avatarBytes;
        _avatarNetworkUrl = networkUrl;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _extras = null;
        _avatarBytes = null;
        _avatarNetworkUrl = null;
        _loading = false;
      });
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
      child: Icon(CupertinoIcons.person_circle, size: radius * 1.15, color: Colors.grey.shade600),
    );
  }

  Widget _buildSidebarHeader(User user) {
    final name = user.fullName.isNotEmpty ? user.fullName : (_extras?.username ?? 'Guest');
    // The sidebar can sit above camera preview surfaces (front camera UI can
    // visually overlap the very top of the screen). Add extra top padding so
    // the name never gets blocked.
    final safeTop = MediaQuery.of(context).padding.top;
    final headerTopPadding = safeTop + 26;

    return Container(
      padding: EdgeInsets.fromLTRB(16, headerTopPadding, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: const Color(0xFF8D6E63).withValues(alpha: 0.18), width: 0.5),
        ),
      ),
      child: Row(
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
          _buildAvatar(radius: 22),
        ],
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
    int? badgeCount,
    /// Customer support unread: walnut gradient instead of flat red (HIG-aligned accent).
    bool gradientUnreadBadge = false,
  }) {
    return Center(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBCAAA4).withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: (textColor ?? const Color(0xFF8D6E63)).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 15, color: textColor ?? const Color(0xFF8D6E63)),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: textColor ?? Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if ((badgeCount ?? 0) > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(Radius.circular(999)),
                          gradient: gradientUnreadBadge
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF8D6E63),
                                    Color(0xFF5D4037),
                                  ],
                                )
                              : null,
                          color: gradientUnreadBadge ? null : Colors.red,
                        ),
                        child: Text(
                          (badgeCount ?? 0) > 99 ? '99+' : '${badgeCount ?? 0}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_forward,
                  size: 11, color: textColor?.withValues(alpha: 0.5) ?? Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuest() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
        child: Column(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(color: CupertinoColors.systemGrey6, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.person_crop_circle_badge_plus, size: 60, color: Color(0xFF8D6E63)),
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
                  CupertinoPageRoute(builder: (_) => const SignInScreen(), fullscreenDialog: true),
                );
              },
              child: Text('Sign In / Sign Up', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
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
      _avatarNetworkUrl = null;
      _loading = false;
    });

    widget.controller.close();

    if (!mounted) return;
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

  Widget _buildButtons(User user) {
    return ValueListenableBuilder<int>(
      valueListenable: _supportNotifications.unreadCount,
      builder: (context, supportUnread, _) => ValueListenableBuilder<List<CustomerNotification>>(
        valueListenable: _customerNotifications.notifications,
        builder: (context, __, ___) {
          final customerUnread = _customerNotifications.unreadCount;
          return Column(
      children: [
        _buildTile(
          icon: CupertinoIcons.location,
          title: 'Address',
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(CupertinoPageRoute(builder: (_) => const AddressesScreen())),
        ),
        _buildTile(
          icon: CupertinoIcons.star_circle,
          title: 'Reviews',
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(CupertinoPageRoute(builder: (_) => const ReviewsScreen())),
        ),
        _buildTile(
          icon: CupertinoIcons.headphones,
          title: 'Help Center',
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(CupertinoPageRoute(builder: (_) => const HelpCenterScreen())),
        ),
        _buildTile(
          icon: CupertinoIcons.chat_bubble_2,
          title: 'Support Chat',
          badgeCount: supportUnread,
          gradientUnreadBadge: true,
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(CupertinoPageRoute(builder: (_) => const SupportChatScreen())),
        ),
        _buildTile(
          icon: CupertinoIcons.bell,
          title: 'Notifications',
          badgeCount: customerUnread,
          gradientUnreadBadge: true,
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(CupertinoPageRoute(builder: (_) => const NotificationsCenterScreen())),
        ),
        _buildTile(
          icon: CupertinoIcons.sparkles,
          title: 'Request Made to Order',
          onTap: () {
            if (_auth.currentUser == null) {
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(builder: (_) => const SignInScreen(), fullscreenDialog: true),
              );
              return;
            }
            Navigator.of(context, rootNavigator: true)
                .push(CupertinoPageRoute(builder: (_) => const MadeToOrderRequestScreen()));
          },
        ),
        _buildTile(
          icon: CupertinoIcons.list_bullet,
          title: 'My Custom Requests',
          onTap: () { 
            if (_auth.currentUser == null) {
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(builder: (_) => const SignInScreen(), fullscreenDialog: true),
              );
              return;
            }
            Navigator.of(context, rootNavigator: true)
                .push(CupertinoPageRoute(builder: (_) => const MyMadeToOrderRequestsScreen()));
          },
        ),
        _buildTile(
          icon: CupertinoIcons.info_circle,
          title: 'About Us',
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(CupertinoPageRoute(builder: (_) => const AboutUsScreen())),
        ),
        _buildTile(
          icon: CupertinoIcons.gear,
          title: 'Settings',
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(CupertinoPageRoute(builder: (_) => const SettingsScreen())),
        ),
        _buildTile(
          icon: CupertinoIcons.arrow_right_circle,
          title: 'Logout',
          textColor: CupertinoColors.systemRed,
          onTap: _handleLogout,
        ),
      ],
    );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.controller.isOpen.value;

    // Fast exit: do not build overlay tree when closed.
    if (!open) return const SizedBox.shrink();

    final user = _auth.currentUser;

    // Sidebar sizing is based on the *full* viewport, since we sit above TabShell.
    final width = MediaQuery.of(context).size.width;
    final pinned = width >= 900;
    final sidebarWidth = pinned ? 380.0 : (width * 0.86).clamp(280.0, 420.0);

    return Stack(
      children: [
        // Scrim: tap OUTSIDE the sidebar collapses it.
        Positioned.fill(
          child: GestureDetector(
            onTap: () => widget.controller.close(),
            child: Container(color: Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        // Sidebar panel: slides in from the right; 100% height by being inside Positioned.fill.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutBack,
          top: 0,
          bottom: 0,
          right: 0,
          width: sidebarWidth,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 26,
                    offset: const Offset(-10, 0),
                  ),
                ],
                border: Border(
                  left: BorderSide(color: const Color(0xFF8D6E63).withValues(alpha: 0.12), width: 1),
                ),
              ),
              child: Column(
                children: [
                  if (user != null) _buildSidebarHeader(user) else const SizedBox(height: 12),
                  Expanded(
                    child: _loading
                        ? const Center(child: CupertinoActivityIndicator())
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                            child: user == null ? _buildGuest() : _buildButtons(user),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

