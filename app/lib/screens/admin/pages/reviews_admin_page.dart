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
  String _sortBy = 'rating_low';
  String _searchQuery = '';
  String? _error;

  static const int _pageSize = 10;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadReviews();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _pageIndex = 0;
      });
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

  /// Filters reviews by rating (lowest to highest rated products).
  /// Filters by selected rating level and search query.
  List<Review> get _filtered {
    var filtered = _reviews;
    
    // Filter by rating if not 'all'
    if (_filter != 'all') {
      final ratingFilter = int.tryParse(_filter);
      if (ratingFilter != null) {
        filtered = filtered.where((r) => r.rating == ratingFilter).toList();
      }
    }
    
    // Apply search query filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((review) {
        return review.productName.toLowerCase().contains(_searchQuery) ||
               review.userName.toLowerCase().contains(_searchQuery) ||
               review.content.toLowerCase().contains(_searchQuery);
      }).toList();
    }
    
    switch (_sortBy) {
      case 'rating_high':
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'newest':
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'oldest':
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'rating_low':
      default:
        filtered.sort((a, b) => a.rating.compareTo(b.rating));
        break;
    }
    
    return filtered;
  }

  int get _activeFilterCount => (_filter != 'all' ? 1 : 0) + (_sortBy != 'rating_low' ? 1 : 0);

  void _showReviewFilterSheet() {
    var tempFilter = _filter;
    var tempSort = _sortBy;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Filter Reviews', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Sort by', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: tempSort,
                  items: const [
                    DropdownMenuItem(value: 'rating_low', child: Text('Rating: Low to High')),
                    DropdownMenuItem(value: 'rating_high', child: Text('Rating: High to Low')),
                    DropdownMenuItem(value: 'newest', child: Text('Newest First')),
                    DropdownMenuItem(value: 'oldest', child: Text('Oldest First')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    tempSort = v;
                  },
                ),
                const SizedBox(height: 10),
                const Text('Rating', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: tempFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Ratings')),
                    DropdownMenuItem(value: '1', child: Text('1 Star')),
                    DropdownMenuItem(value: '2', child: Text('2 Stars')),
                    DropdownMenuItem(value: '3', child: Text('3 Stars')),
                    DropdownMenuItem(value: '4', child: Text('4 Stars')),
                    DropdownMenuItem(value: '5', child: Text('5 Stars')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    tempFilter = v;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        tempFilter = 'all';
                        tempSort = 'rating_low';
                        setState(() {
                          _filter = tempFilter;
                          _sortBy = tempSort;
                          _pageIndex = 0;
                        });
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Reset'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _filter = tempFilter;
                          _sortBy = tempSort;
                          _pageIndex = 0;
                        });
                        Navigator.of(sheetContext).pop();
                      },
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5C4033)),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Shows detailed review information in a centered modal dialog.
  void _showReviewDetails(Review review) {
    showDialog(
      context: context,
      builder: (context) => _ReviewDetailsDialog(
        review: review,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    final totalCount = filtered.length;
    final pageCount = (totalCount / _pageSize).ceil();
    final safePageIndex = pageCount <= 1 ? 0 : _pageIndex.clamp(0, pageCount - 1).toInt();
    final start = safePageIndex * _pageSize;
    final end = (start + _pageSize) > totalCount ? totalCount : (start + _pageSize);
    final pageItems = totalCount == 0 ? const <Review>[] : filtered.sublist(start, end);

    // NOTE:
    // Admin reviews are now *read‑only*. We keep filters/search so admins can
    // quickly inspect feedback, but there are no approval/reject actions.
    // Reviews are filtered by rating (lowest to highest) to prioritize low-rated products.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminToolbar(
          title: 'Customer Reviews',
          actions: [],
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
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
              const SizedBox(width: 8),
              Stack(
                children: [
                  IconButton.outlined(
                    onPressed: _showReviewFilterSheet,
                    icon: const Icon(Icons.tune_outlined),
                    tooltip: 'Filter',
                  ),
                  if (_activeFilterCount > 0)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: const BoxDecoration(color: Color(0xFF8D6E63), shape: BoxShape.circle),
                        child: Text(
                          '$_activeFilterCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadReviews,
                tooltip: 'Refresh reviews',
              ),
            ],
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
                              itemCount: pageItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final review = pageItems[index];
                                return _ReviewsTableRow(
                                  review: review,
                                  onTap: () => _showReviewDetails(review),
                                );
                              },
                            ),
                          ),
                          if (pageCount > 1)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.chevron_left),
                                        onPressed: safePageIndex > 0
                                            ? () => setState(() => _pageIndex = safePageIndex - 1)
                                            : null,
                                        tooltip: 'Previous page',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.chevron_right),
                                        onPressed: safePageIndex < pageCount - 1
                                            ? () => setState(() => _pageIndex = safePageIndex + 1)
                                            : null,
                                        tooltip: 'Next page',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Page ${safePageIndex + 1} of $pageCount',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
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
  });

  final Review review;
  final VoidCallback onTap;

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
          ],
        ),
      ),
    );
  }
}

/// Centered dialog showing detailed review information (read‑only).
class _ReviewDetailsDialog extends StatelessWidget {
  const _ReviewDetailsDialog({
    required this.review,
  });

  final Review review;
  static const double _detailFontSize = 16;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 40),
                      Expanded(
                        child: Text(
                          'Review Details',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: const AssetImage('assets/images/logo2.png'),
                    onBackgroundImageError: (_, __) {},
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
                      fontSize: _detailFontSize,
                    ),
                    _DetailRow(
                      label: 'Product ID',
                      value: review.productId,
                      fontSize: _detailFontSize,
                    ),
                    _DetailRow(
                      label: 'Customer',
                      value: review.userName.isNotEmpty ? review.userName : 'Anonymous',
                      fontSize: _detailFontSize,
                    ),
                    _DetailRow(
                      label: 'Customer ID',
                      value: review.userId,
                      fontSize: _detailFontSize,
                    ),
                    _DetailRow(
                      label: 'Rating',
                      value: '${review.rating} / 5 ${'⭐' * review.rating}',
                      fontSize: _detailFontSize,
                    ),
                    _DetailRow(
                      label: 'Status',
                      value: review.status[0].toUpperCase() + review.status.substring(1),
                      fontSize: _detailFontSize,
                    ),
                    _DetailRow(
                      label: 'Created',
                      value: review.createdAt.toLocal().toString().substring(0, 19),
                      fontSize: _detailFontSize,
                    ),
                    if (review.updatedAt != null)
                      _DetailRow(
                        label: 'Last Updated',
                        value: review.updatedAt!.toLocal().toString().substring(0, 19),
                        fontSize: _detailFontSize,
                      ),
                    _DetailRow(
                      label: 'Review Content',
                      value: review.content.isEmpty ? '(No comment provided)' : review.content,
                      fontSize: _detailFontSize,
                    ),
                    const SizedBox(height: 20),
                    // Read‑only admin view: no approve / reject actions. Admins
                    // can inspect the full review details, but all moderation
                    // happens automatically at creation time.
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
  const _DetailRow({
    required this.label,
    required this.value,
    this.fontSize = 16,
  });

  final String label;
  final String value;
  final double fontSize;

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
              '$label:',
              style: GoogleFonts.poppins(
                color: Colors.grey[600],
                fontSize: fontSize,
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
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
