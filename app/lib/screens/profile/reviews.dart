import 'package:flutter/cupertino.dart';

class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Reviews')),
      child: Center(child: Text('Your product ratings and reviews appear here.')),
    );
  }
}




















