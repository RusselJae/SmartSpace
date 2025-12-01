import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/product.dart';
import '../../models/review.dart';
import '../../models/order_record.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../widgets/toast.dart';
import '../views/sign_in.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  final AuthService _auth = AuthService();
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');

  List<Review> _reviews = [];
  List<Product> _purchasedProducts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _reviews = [];
        _purchasedProducts = [];
        _loading = false;
        _error = null;
      });
      return;
    }

    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final reviewsFuture = _db.getAllReviews();
      final ordersFuture = _db.getAllOrders();
      final productsFuture = _db.getAllProducts();

      final reviews = (await reviewsFuture)
          .where((review) => review.userId == user.id)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final List<OrderRecord> orders = await ordersFuture;
      final userOrders = orders.where((order) => order.userId == user.id).toList();
      final products = await productsFuture;

      final purchasedIds = userOrders.expand((order) => order.productIds).toSet();
      final purchasedProducts =
          products.where((product) => purchasedIds.contains(product.id)).toList();

      setState(() {
        _reviews = reviews;
        _purchasedProducts = purchasedProducts;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load reviews.';
        _loading = false;
      });
    }
  }

  void _handleWriteReview() async {
    final user = _auth.currentUser;
    if (user == null) {
      Toast.info(context, 'Please sign in to write a review');
      return;
    }

    if (_purchasedProducts.isEmpty) {
      Toast.info(context, 'Purchase a product to review it');
      return;
    }

    // Use rootNavigator to hide tab bar when navigating to write review
    final review = await Navigator.of(context, rootNavigator: true).push<Review>(
      CupertinoPageRoute(
        builder: (_) => _ReviewComposerPage(
          user: user,
          products: _purchasedProducts,
          db: _db,
        ),
        fullscreenDialog: true,
      ),
    );

    if (review != null) {
      setState(() => _reviews.insert(0, review));
      if (mounted) {
        Toast.success(context, 'Review submitted!');
      }
    }
  }

  Widget _buildSignedOut() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.chat_bubble_2_fill, size: 48, color: Color(0xFFBCAAA4)),
          const SizedBox(height: 16),
          Text(
            'Sign in to manage your reviews.',
            style: GoogleFonts.poppins(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          CupertinoButton.filled(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (_) => const SignInScreen(),
                  fullscreenDialog: true,
                ),
              );
            },
            child: Text('Sign In', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Review review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.productName,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              _ReviewStatusChip(status: review.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(
              5,
              (index) => Icon(
                index < review.rating ? CupertinoIcons.star_fill : CupertinoIcons.star,
                size: 18,
                color: index < review.rating ? const Color(0xFFFFC107) : Colors.black26,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            review.content,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.black87,
              height: 1.4,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _dateFormat.format(review.createdAt),
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.black54,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        if (_loading)
          const Center(child: CupertinoActivityIndicator())
        else if (user == null)
          _buildSignedOut()
        else if (_error != null)
          Column(
            children: [
              Text(
                _error!,
                style: GoogleFonts.poppins(color: Colors.black, fontSize: 16),
              ),
              const SizedBox(height: 12),
              CupertinoButton(
                color: const Color(0xFF8D6E63),
                onPressed: _loadData,
                child: Text('Retry', style: GoogleFonts.poppins(color: Colors.white)),
              ),
            ],
          )
        else if (_reviews.isEmpty)
          Column(
            children: [
              const SizedBox(height: 60),
              Icon(CupertinoIcons.doc_text_search, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No reviews yet',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Share your thoughts about the products you love.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.black87,
                  // Guard against auto-underline when the OS thinks this text
                  // might be a link.
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          )
        else
          ..._reviews.map(_buildReviewCard),
        if (user != null && !_loading)
          CupertinoButton.filled(
            onPressed: _handleWriteReview,
            child: Text(
              'Write a review',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('Your Reviews', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF8D6E63),
          onRefresh: () => _loadData(showLoader: false),
          child: list,
        ),
      ),
    );
  }
}

class _ReviewStatusChip extends StatelessWidget {
  const _ReviewStatusChip({required this.status});
  final String status;

  Color get _color {
    switch (status.toLowerCase()) {
      case 'published':
        return const Color(0xFF2E7D32);
      case 'pending':
        return CupertinoColors.systemOrange;
      case 'flagged':
        return CupertinoColors.systemRed;
      default:
        return const Color(0xFF8D6E63);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeStatus = status.isEmpty ? 'status' : status;
    final label = safeStatus[0].toUpperCase() + safeStatus.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: _color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _ReviewComposerPage extends StatefulWidget {
  const _ReviewComposerPage({
    required this.products,
    required this.user,
    required this.db,
  });

  final List<Product> products;
  final User user;
  final MySQLDatabaseService db;

  @override
  State<_ReviewComposerPage> createState() => _ReviewComposerPageState();
}

class _ReviewComposerPageState extends State<_ReviewComposerPage> {
  late Product _selectedProduct = widget.products.first;
  int _rating = 5;
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().length < 10) {
      setState(() {
        _error = 'Please share at least 10 characters.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final review = await widget.db.createReview(
        productId: _selectedProduct.id,
        productName: _selectedProduct.name,
        userId: widget.user.id,
        userName: widget.user.fullName,
        rating: _rating,
        content: _controller.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(review);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to submit review.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('Write a review', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _submitting ? null : () => Navigator.of(context).maybePop(),
          child: Text(
            'Close',
            style: GoogleFonts.poppins(color: const Color(0xFF8D6E63)),
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Select product',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(16),
              onPressed: () {
                showCupertinoModalPopup<void>(
                  context: context,
                  builder: (_) => CupertinoActionSheet(
                    title: Text('Choose a product', style: GoogleFonts.poppins()),
                    actions: widget.products
                        .map(
                          (product) => CupertinoActionSheetAction(
                            onPressed: () {
                              Navigator.of(context).pop();
                              setState(() => _selectedProduct = product);
                            },
                            child: Text(product.name, style: GoogleFonts.poppins()),
                          ),
                        )
                        .toList(),
                    cancelButton: CupertinoActionSheetAction(
                      onPressed: () => Navigator.of(context).pop(),
                      isDefaultAction: true,
                      child: Text('Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ),
                  ),
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _selectedProduct.name,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(CupertinoIcons.chevron_down, color: Colors.black45),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Rating',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: List.generate(
                5,
                (index) => IconButton(
                  iconSize: 30,
                  icon: Icon(
                    index < _rating ? CupertinoIcons.star_fill : CupertinoIcons.star,
                    color: index < _rating ? const Color(0xFFFFC107) : Colors.black26,
                  ),
                  onPressed: _submitting ? null : () => setState(() => _rating = index + 1),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your review',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _controller,
              placeholder: 'Share your thoughts about the product...',
              minLines: 4,
              maxLines: 6,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CupertinoColors.systemGrey4),
              ),
              style: GoogleFonts.poppins(color: Colors.black),
              placeholderStyle: GoogleFonts.poppins(color: Colors.black45),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: GoogleFonts.poppins(color: CupertinoColors.systemRed, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            CupertinoButton.filled(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : Text('Submit', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}




















