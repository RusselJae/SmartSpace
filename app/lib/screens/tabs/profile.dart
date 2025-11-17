import 'package:flutter/cupertino.dart';
import '../profile/sign_in.dart';
import '../profile/orders.dart';
import '../profile/reviews.dart';

/// =============================================================
/// ProfileScreen
///
/// Placeholder for authentication and profile management (sign in,
/// sign up, profile details, addresses, orders, reviews).
/// =============================================================
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Profile'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => const SignInScreen()),
              ),
              child: const Text('Sign In / Manage Account'),
            ),
            const SizedBox(height: 12),
            CupertinoButton(
              color: CupertinoColors.systemGrey5,
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => const OrdersScreen()),
              ),
              child: const Text('Orders & Tracking'),
            ),
            const SizedBox(height: 12),
            CupertinoButton(
              color: CupertinoColors.systemGrey5,
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => const ReviewsScreen()),
              ),
              child: const Text('Your Reviews'),
            ),
          ],
        ),
      ),
    );
  }
}


