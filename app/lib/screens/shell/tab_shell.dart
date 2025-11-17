import 'package:flutter/cupertino.dart';

import '../tabs/catalog_home.dart';
import '../tabs/wishlist.dart';
import '../tabs/cart.dart';
import '../tabs/profile.dart';

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
class TabShell extends StatelessWidget {
  const TabShell({super.key});

  static const String route = '/app';
  static Widget builder(BuildContext context) => const TabShell();

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.heart),
            label: 'Wishlist',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.cart),
            label: 'Cart',
          ),
          BottomNavigationBarItem(
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
            return CupertinoTabView(builder: (context) => const ProfileScreen());
          default:
            return CupertinoTabView(builder: (context) => const CatalogHome());
        }
      },
    );
  }
}


