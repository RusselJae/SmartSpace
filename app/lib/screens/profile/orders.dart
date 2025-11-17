import 'package:flutter/cupertino.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Orders')),
      child: Center(child: Text('Your order history and tracking appear here.')),
    );
  }
}




















