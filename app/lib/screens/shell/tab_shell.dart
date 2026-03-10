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
    
    return Container(
      decoration: const BoxDecoration(color: walnut),
      child: CupertinoTabScaffold(
        backgroundColor: Colors.transparent,
        tabBar: CupertinoTabBar(
          backgroundColor: walnut,
          iconSize: 22, // Icon size
          height: 60, // Increased height to add padding inside navigation bar
          border: Border(
            top: BorderSide(
              color: walnutDark.withValues(alpha: 0.3),
              width: 0.6,
            ),
          ),
          activeColor: Colors.white,
          inactiveColor: Colors.white70,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house, size: 22), // Reduced from default ~28 to 22
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.heart, size: 22), // Reduced from default ~28 to 22
            label: 'Wishlist',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(CupertinoIcons.cart, size: 22), // Reduced from default ~28 to 22
                if (cartCount > 0)
                  Positioned(
                    right: -8,
                    top: -8,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: cartCount > 9 ? 7 : 6,
                        vertical: 4,
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
                            blurRadius: 8,
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
                        minWidth: cartCount > 9 ? 24 : 22,
                        minHeight: 22,
                      ),
                      child: Center(
                        child: Text(
                          cartCount > 99 ? '99+' : cartCount.toString(),
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.none,
                            height: 1.1,
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
            icon: Icon(CupertinoIcons.square_list, size: 22), // Reduced from default ~28 to 22
            label: 'Orders',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person, size: 22), // Reduced from default ~28 to 22
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
            return CupertinoTabView(builder: (context) => const OrdersTab());
          case 4:
            return CupertinoTabView(builder: (context) => const ProfileTab());
          default:
            return CupertinoTabView(builder: (context) => const CatalogHome());
        }
      },
      ),
    );
  }
}


