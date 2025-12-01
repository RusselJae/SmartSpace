import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../tabs/catalog_home.dart';
import '../tabs/wishlist.dart';
import '../tabs/cart.dart';
import '../tabs/profile.dart';
import '../../services/cart_service.dart';
import '../../services/auth_service.dart';

/// =============================================================
/// TabShell
///
/// Primary bottom-tab navigation with four core areas:
/// - Home (catalog & recommendations)
/// - Wishlist
/// - Cart
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

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    // Only rebuild if cart count actually changed to reduce unnecessary rebuilds
    if (mounted) {
      final newCount = _cart.productCount;
      if (newCount != _lastCartCount) {
        _lastCartCount = newCount;
        setState(() {});
      }
    }
  }

  int _lastCartCount = 0;

  @override
  Widget build(BuildContext context) {
    // Only show cart count if user is authenticated
    final isAuthenticated = _auth.isAuthenticated;
    final cartCount = isAuthenticated ? _cart.productCount : 0;
    
    return Container(
      // Custom navigation bar wrapper with gradient background
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            const Color(0xFFFFFBF7).withValues(alpha: 0.8),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8D6E63).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: CupertinoTabScaffold(
        backgroundColor: Colors.transparent,
        tabBar: CupertinoTabBar(
          // Modern navigation bar with enhanced design following Apple HIG
          backgroundColor: Colors.transparent,
          border: Border(
            top: BorderSide(
              color: const Color(0xFFBCAAA4).withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          activeColor: const Color(0xFF8D6E63), // Medium brown for active state
          inactiveColor: const Color(0xFFBCAAA4), // Light brown for inactive state
          // Custom height for better visual presence
          height: 70,
          iconSize: 26,
          items: [
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.heart),
            label: 'Wishlist',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(CupertinoIcons.cart),
                if (cartCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      // Enhanced badge with proper sizing to prevent cut-off
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
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.5),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                            spreadRadius: 0,
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.8),
                            blurRadius: 2,
                            offset: const Offset(0, 0),
                            spreadRadius: 1,
                          ),
                        ],
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
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.none,
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Cart',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person),
            label: 'Profile',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return CupertinoTabView(builder: (context) => const CatalogHome());
          case 1:
            return CupertinoTabView(builder: (context) => const WishlistScreen());
          case 2:
            return CupertinoTabView(builder: (context) => const CartScreen());
          case 3:
            return CupertinoTabView(builder: (context) => const ProfileTab());
          default:
            return CupertinoTabView(builder: (context) => const CatalogHome());
        }
      },
      ),
    );
  }
}


