import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../tabs/catalog_home.dart';
import '../tabs/wishlist.dart';
import '../tabs/cart.dart';
import '../tabs/orders_tab.dart';
import '../tabs/profile.dart';
import '../../services/cart_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/global_profile_sidebar.dart';
import '_nav_icon.dart';
import '../views/sign_in.dart';

/// =============================================================
/// TabShell
///
/// Primary bottom-tab navigation with five core areas:
/// - Home (catalog & recommendations)
/// - Wishlist
/// - Cart
/// - Orders (order tracking and management)
/// - Profile
///
/// Each tab maintains its own navigation stack via a separate
/// CupertinoTabView.
/// =============================================================
class TabShell extends StatefulWidget {
  const TabShell({super.key});

  static const String route = '/app';
  static Widget builder(BuildContext context) => const TabShell();

  @override
  State<TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<TabShell> {
  final CartService _cart = CartService();
  final AuthService _auth = AuthService();
  final CupertinoTabController _tabs = CupertinoTabController();
  final GlobalProfileSidebarController _profileSidebar = GlobalProfileSidebarController.instance;

  int _lastNonProfileIndex = 0;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
    _primeSession();
  }

  Future<void> _primeSession() async {
    // The tab shell decides whether the Orders tab should exist based on auth.
    // We must restore the persisted session before building the tab list,
    // otherwise users can land on an "empty" orders experience.
    await _auth.initializeSession();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Use productCount (number of unique items) instead of totalQuantity
    final isAuthenticated = _auth.isAuthenticated;
    final cartCount = isAuthenticated ? _cart.productCount : 0;
    
    // Walnut navigation bar with white icons
    const walnut = Color(0xFF5C4033); // Walnut background
    const walnutDark = Color(0xFF4A3329);
    
    final tabs = <Widget>[
      const CatalogHome(),
      const WishlistScreen(),
      const CartScreen(),
      if (isAuthenticated) const OrdersTab(),
      // Keep ProfileTab as a real page in case it’s navigated to internally,
      // but the tab button itself acts as an overlay toggle (see onTap).
      const ProfileTab(),
    ];

    final profileTabIndex = tabs.length - 1;

    Widget _buildCartBadge() {
      if (cartCount <= 0) return const SizedBox.shrink();
      return Positioned(
        right: -6,
        top: -6,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: cartCount > 9 ? 6 : 5,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8D6E63), Color(0xFFFF9800)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          constraints: BoxConstraints(
            minWidth: cartCount > 9 ? 22 : 20,
            minHeight: 20,
          ),
          child: Center(
            child: Text(
              cartCount > 99 ? '99+' : cartCount.toString(),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
                height: 1.1,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final items = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        icon: NavIcon(
          icon: CupertinoIcons.house,
          active: _selectedIndex == 0,
        ),
        label: 'Home',
      ),
      BottomNavigationBarItem(
        icon: NavIcon(
          icon: CupertinoIcons.heart,
          active: _selectedIndex == 1,
        ),
        label: 'Likes',
      ),
      BottomNavigationBarItem(
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            NavIcon(
              icon: CupertinoIcons.cart,
              active: _selectedIndex == 2,
            ),
            _buildCartBadge(),
          ],
        ),
        label: 'Cart',
      ),
      if (isAuthenticated)
        BottomNavigationBarItem(
          icon: NavIcon(
            icon: CupertinoIcons.square_list,
            active: _selectedIndex == 3,
          ),
          label: 'Orders',
        ),
      // Profile/Login is always last
      BottomNavigationBarItem(
        icon: NavIcon(
          icon: CupertinoIcons.person,
          active: _selectedIndex == (isAuthenticated ? 4 : 3),
        ),
        label: isAuthenticated ? 'Profile' : 'Login',
      ),
    ];

    final profileItemIndex = items.length - 1;

    return Container(
      decoration: const BoxDecoration(color: walnut),
      child: Stack(
        children: [
          CupertinoTabScaffold(
            controller: _tabs,
            backgroundColor: walnut,
            tabBar: CupertinoTabBar(
          backgroundColor: walnut,
          iconSize: 20,
          height: 64,
          border: Border(
            top: BorderSide(
              color: walnutDark.withValues(alpha: 0.3),
              width: 0.6,
            ),
          ),
          activeColor: Colors.white,
          inactiveColor: Colors.white70,
          onTap: (index) {
            // Profile/Login tab behavior:
            // - Authenticated: do NOT switch screens; toggle the overlay sidebar
            //   on top of the current tab (home/wishlist/cart/orders).
            // - Guest: do NOT switch screens; open the sign-in screen.
            if (index == profileItemIndex) {
              if (isAuthenticated) {
                // Toggle sidebar but keep user on the current tab (home/wishlist/cart/orders).
                _profileSidebar.toggle();
                setState(() {
                  _selectedIndex = profileItemIndex;
                });
              } else {
                // Guests get routed to the sign-in screen, but we still keep them
                // on whatever tab they were viewing.
                Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute(
                    builder: (_) => const SignInScreen(),
                    fullscreenDialog: true,
                  ),
                );
                setState(() {
                  _selectedIndex = profileItemIndex;
                });
              }
              // Immediately restore the last non-profile index so the visible
              // tab content never jumps to a "Profile" page.
              _tabs.index = _lastNonProfileIndex;
            } else {
              setState(() {
                _lastNonProfileIndex = index;
                _selectedIndex = index;
              });
              _tabs.index = index;
            }
          },
        items: items,
        ),
      tabBuilder: (context, index) {
        final safeIndex = index.clamp(0, tabs.length - 1);
        final tabRoot = tabs[safeIndex];

        // The "profile tab" route remains accessible, but the bottom tab
        // button for Profile does not switch to it (overlay-only).
        return CupertinoTabView(builder: (context) => tabRoot);
      },
          ),
          // Global overlay: sits ABOVE everything, including bottom tab bar.
          // ValueListenableBuilder ensures we rebuild immediately on open/close.
          Positioned.fill(
            child: ValueListenableBuilder<bool>(
              valueListenable: _profileSidebar.isOpen,
              builder: (context, open, _) {
                return IgnorePointer(
                  ignoring: !open,
                  child: GlobalProfileSidebarOverlay(controller: _profileSidebar),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


