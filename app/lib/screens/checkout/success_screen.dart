import 'package:flutter/cupertino.dart';

/// Order confirmation
class SuccessScreen extends StatelessWidget {
  const SuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Order Placed')),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.check_mark_circled_solid, size: 64, color: CupertinoColors.activeGreen),
            const SizedBox(height: 12),
            const Text('Your order is confirmed!'),
            const SizedBox(height: 24),
            CupertinoButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}


