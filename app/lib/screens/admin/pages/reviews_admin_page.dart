import 'package:flutter/material.dart';

import '../widgets/admin_toolbar.dart';

class ReviewsAdminPage extends StatefulWidget {
  const ReviewsAdminPage({super.key});

  @override
  State<ReviewsAdminPage> createState() => _ReviewsAdminPageState();
}

class _ReviewsAdminPageState extends State<ReviewsAdminPage> {
  final List<_AdminReview> _reviews = [
    const _AdminReview(product: 'Oak Lounge Chair', author: 'Jane Doe', rating: 5, status: 'pending', content: 'Incredible craftsmanship.'),
    const _AdminReview(product: 'Walnut Coffee Table', author: 'Marcus Tan', rating: 4, status: 'published', content: 'Sturdy and elegant.'),
    const _AdminReview(product: 'Rattan Accent Chair', author: 'Noah Chen', rating: 2, status: 'flagged', content: 'Arrived with scratches.'),
  ];
  String _filter = 'pending';

  @override
  Widget build(BuildContext context) {
    final List<_AdminReview> filtered = _filter == 'all' ? _reviews : _reviews.where((review) => review.status == _filter).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Customer reviews',
          actions: const [
            AdminToolbarAction(label: 'Approve', icon: Icons.check_circle, primary: true),
            AdminToolbarAction(label: 'Reject', icon: Icons.close_rounded),
            AdminToolbarAction(label: 'Export', icon: Icons.download),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'pending', label: Text('Pending')),
              ButtonSegment<String>(value: 'published', label: Text('Published')),
              ButtonSegment<String>(value: 'flagged', label: Text('Flagged')),
              ButtonSegment<String>(value: 'all', label: Text('All')),
            ],
            selected: {_filter},
            onSelectionChanged: (Set<String> values) => setState(() => _filter = values.first),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemBuilder: (context, index) => _ReviewCard(review: filtered[index]),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: filtered.length,
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final _AdminReview review;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(review.product, style: Theme.of(context).textTheme.titleMedium)),
                Chip(label: Text(review.status)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (int i = 0; i < 5; i++)
                  Icon(i < review.rating ? Icons.star : Icons.star_border, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Text('• ${review.author}'),
              ],
            ),
            const SizedBox(height: 8),
            Text(review.content),
          ],
        ),
      ),
    );
  }
}

class _AdminReview {
  const _AdminReview({
    required this.product,
    required this.author,
    required this.rating,
    required this.status,
    required this.content,
  });

  final String product;
  final String author;
  final int rating;
  final String status;
  final String content;
}

