import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/review.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';

/// Reviews management page with moderation, search, and status filtering.
/// Follows Apple HIG with clean layouts and smooth animations.
class ReviewsAdminPage extends StatefulWidget {
  const ReviewsAdminPage({super.key});

  @override
  State<ReviewsAdminPage> createState() => _ReviewsAdminPageState();
}

class _ReviewsAdminPageState extends State<ReviewsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Review> _reviews = [];
  bool _loading = true;
  String _filter = 'all';
  String _searchQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReviews();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Loads all reviews from the database with error handling.
  Future<void> _loadReviews() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reviews = await _db.getAllReviews();
      if (!mounted) return;
      setState(() {
        _reviews = reviews;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load reviews: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Filters reviews by status and search query.
  List<Review> get _filtered {
    var filtered = _filter == 'all'
        ? _reviews
        : _reviews.where((r) => r.status == _filter).toList();
    
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((review) {
        return review.productName.toLowerCase().contains(_searchQuery) ||
               review.userName.toLowerCase().contains(_searchQuery) ||
               review.content.toLowerCase().contains(_searchQuery);
      }).toList();
    }
    
    return filtered;
  }

  /// Updates review status with user feedback.
  Future<void> _updateReviewStatus(Review review, String status) async {
    try {
      await _db.updateReviewStatus(review.id, status);
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Review ${status == 'published' ? 'approved' : status == 'rejected' ? 'rejected' : 'updated'}'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      
      await _loadReviews();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update review: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Shows detailed review information in a centered modal dialog.
  void _showReviewDetails(Review review) {
    showDialog(
      context: context,
      builder: (context) => _ReviewDetailsDialog(
        review: review,
        onStatusUpdate: (status) => _updateReviewStatus(review, status),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pendingCount = _reviews.where((r) => r.status == 'pending').length;
    final flaggedCount = _reviews.where((r) => r.status == 'flagged').length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Customer Reviews',
          actions: [
            if (pendingCount > 0)
              AdminToolbarAction(
                label: 'Approve All ($pendingCount)',
                icon: Icons.check_circle_outline,
                primary: true,
                onPressed: () {
                  // Batch approve functionality
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Batch approve coming soon')),
                  );
                },
              ),
            AdminToolbarAction(
              label: 'Export',
              icon: Icons.download_outlined,
              primary: false,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Export functionality coming soon')),
                );
              },
            ),
          ],
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReviews,
            tooltip: 'Refresh reviews',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (flaggedCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$flaggedCount ${flaggedCount == 1 ? 'review' : 'reviews'} flagged for review',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by product, customer, or content...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'all', label: Text('All')),
              ButtonSegment<String>(value: 'pending', label: Text('Pending')),
              ButtonSegment<String>(value: 'published', label: Text('Published')),
              ButtonSegment<String>(value: 'flagged', label: Text('Flagged')),
              ButtonSegment<String>(value: 'rejected', label: Text('Rejected')),
            ],
            selected: {_filter},
            onSelectionChanged: (Set<String> values) {
              setState(() => _filter = values.first);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            '${filtered.length} ${filtered.length == 1 ? 'review' : 'reviews'}',
            style: GoogleFonts.poppins(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.reviews_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty || _filter != 'all'
                                ? 'No reviews match your filters'
                                : 'No reviews yet',
                            style: GoogleFonts.poppins(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Card(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        children: [
                          const _ReviewsHeaderRow(),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final review = filtered[index];
                                return _ReviewsTableRow(
                                  review: review,
                                  onTap: () => _showReviewDetails(review),
                                  onApprove: review.status != 'published'
                                      ? () => _updateReviewStatus(review, 'published')
                                      : null,
                                  onReject: review.status != 'rejected'
                                      ? () => _updateReviewStatus(review, 'rejected')
                                      : null,
                                  onFlag: review.status != 'flagged'
                                      ? () => _updateReviewStatus(review, 'flagged')
                                      : null,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

class _ReviewsHeaderRow extends StatelessWidget {
  const _ReviewsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.grey[600],
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Product', style: style)),
          Expanded(flex: 3, child: Text('Customer', style: style)),
          Expanded(flex: 2, child: Text('Rating', style: style)),
          Expanded(flex: 3, child: Text('Excerpt', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          const SizedBox(width: 80),
        ],
      ),
    );
  }
}

class _ReviewsTableRow extends StatelessWidget {
  const _ReviewsTableRow({
    required this.review,
    required this.onTap,
    this.onApprove,
    this.onReject,
    this.onFlag,
  });

  final Review review;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onFlag;

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF39C12);
      case 'published':
        return const Color(0xFF27AE60);
      case 'flagged':
        return const Color(0xFFE74C3C);
      case 'rejected':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stars = List.generate(
      5,
      (index) => Icon(
        index < review.rating ? Icons.star : Icons.star_border,
        size: 16,
        color: Colors.amber,
      ),
    );
    final statusColor = _statusColor(review.status);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                review.productName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                review.userName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  ...stars,
                  const SizedBox(width: 4),
                  Text('${review.rating}'),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                review.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  review.status[0].toUpperCase() + review.status.substring(1),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 4,
              children: [
                if (onApprove != null)
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    color: const Color(0xFF27AE60),
                    tooltip: 'Approve',
                    onPressed: onApprove,
                  ),
                if (onReject != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.redAccent,
                    tooltip: 'Reject',
                    onPressed: onReject,
                  ),
                if (onFlag != null)
                  IconButton(
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    color: Colors.orange,
                    tooltip: 'Flag',
                    onPressed: onFlag,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered dialog showing detailed review information with moderation actions.
class _ReviewDetailsDialog extends StatelessWidget {
  const _ReviewDetailsDialog({
    required this.review,
    required this.onStatusUpdate,
  });

  final Review review;
  final ValueChanged<String> onStatusUpdate;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                children: [
                  Text(
                    'Review Details',
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Product',
                      value: review.productName.isNotEmpty ? review.productName : 'Unknown Product',
                    ),
                    _DetailRow(label: 'Product ID', value: review.productId),
                    _DetailRow(
                      label: 'Customer',
                      value: review.userName.isNotEmpty ? review.userName : 'Anonymous',
                    ),
                    _DetailRow(label: 'Customer ID', value: review.userId),
                    _DetailRow(
                      label: 'Rating',
                      value: '${review.rating} / 5 ${'⭐' * review.rating}',
                    ),
                    _DetailRow(
                      label: 'Status',
                      value: review.status[0].toUpperCase() + review.status.substring(1),
                    ),
                    _DetailRow(
                      label: 'Created',
                      value: review.createdAt.toLocal().toString().substring(0, 19),
                    ),
                    if (review.updatedAt != null)
                      _DetailRow(
                        label: 'Last Updated',
                        value: review.updatedAt!.toLocal().toString().substring(0, 19),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Review Content',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Text(
                        review.content.isEmpty ? '(No comment provided)' : review.content,
                        style: GoogleFonts.poppins(
                          color: review.content.isEmpty ? Colors.grey[600] : Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          fontStyle: review.content.isEmpty ? FontStyle.italic : FontStyle.normal,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              onStatusUpdate('published');
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.check_circle_outline, size: 20),
                            label: const Text('Approve'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF27AE60),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              onStatusUpdate('rejected');
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.close, size: 20),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim(),
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
