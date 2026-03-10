import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ReviewComposerPageState extends State<_ReviewComposerPage> with SingleTickerProviderStateMixin {
  late Product _selectedProduct = widget.products.first;
  int _rating = 5;
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final FocusNode _focusNode = FocusNode();
  static const int _minReviewLength = 10;
  static const int _maxReviewLength = 500;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
    
    // Listen to text changes for real-time validation
    _controller.addListener(() {
      if (_error != null && _controller.text.trim().length >= _minReviewLength) {
        setState(() => _error = null);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// Get the current character count
  int get _characterCount => _controller.text.length;
  
  /// Check if review is valid
  bool get _isValid => _controller.text.trim().length >= _minReviewLength && _rating > 0;

  Future<void> _submit() async {
    // Validate minimum length
    if (_controller.text.trim().length < _minReviewLength) {
      HapticFeedback.mediumImpact();
      setState(() {
        _error = 'Please share at least $_minReviewLength characters.';
      });
      _focusNode.requestFocus();
      return;
    }

    // Validate maximum length
    if (_controller.text.length > _maxReviewLength) {
      HapticFeedback.mediumImpact();
      setState(() {
        _error = 'Review must be less than $_maxReviewLength characters.';
      });
      return;
    }

    // Validate rating
    if (_rating < 1 || _rating > 5) {
      HapticFeedback.mediumImpact();
      setState(() {
        _error = 'Please select a rating.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    HapticFeedback.mediumImpact();

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
      
      // Success haptic feedback
      HapticFeedback.mediumImpact();
      
      // Small delay for better UX
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (!mounted) return;
      Navigator.of(context).pop(review);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final errorMessage = e.toString();
      setState(() {
        if (errorMessage.contains('purchased')) {
          _error = 'You can only review products you have purchased';
        } else if (errorMessage.contains('already reviewed')) {
          _error = 'You have already reviewed this product';
        } else if (errorMessage.contains('API request failed')) {
          // Extract the actual error message from API response
          final match = RegExp(r'API request failed.*?:\s*(.+)').firstMatch(errorMessage);
          _error = match != null 
              ? match.group(1) ?? 'Failed to submit review. Please try again.'
              : 'Failed to submit review. Please check your connection and try again.';
        } else {
          _error = 'Failed to submit review. Please try again.';
        }
        _submitting = false;
      });
    }
  }

  void _updateRating(int newRating) {
    if (_submitting) return;
    HapticFeedback.selectionClick();
    setState(() {
      _rating = newRating;
      if (_error != null && _isValid) {
        _error = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF9F4EF),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFFF9F4EF),
        middle: Text(
          'Write a review',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: Colors.black,
          ),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _submitting ? null : () {
            HapticFeedback.selectionClick();
            Navigator.of(context).maybePop();
          },
          child: const Icon(
            CupertinoIcons.back,
            color: Color(0xFF8D6E63),
            size: 28,
          ),
        ),
      ),
      child: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 8),
              // Product selector with improved design
              _buildProductSelector(),
              const SizedBox(height: 32),
              // Rating section
              _buildRatingSection(),
              const SizedBox(height: 32),
              // Review text area
              _buildReviewTextArea(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _buildErrorBanner(),
              ],
              const SizedBox(height: 32),
              // Submit button
              _buildSubmitButton(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Build product selector with improved UI
  Widget _buildProductSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select product',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: CupertinoColors.systemGrey4,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CupertinoButton(
            padding: const EdgeInsets.all(16),
            onPressed: _submitting ? null : () {
              HapticFeedback.selectionClick();
              showCupertinoModalPopup<void>(
                context: context,
                builder: (_) => CupertinoActionSheet(
                  title: Text(
                    'Choose a product',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  actions: widget.products
                      .map(
                        (product) => CupertinoActionSheetAction(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(context).pop();
                            setState(() => _selectedProduct = product);
                          },
                          child: Text(
                            product.name,
                            style: GoogleFonts.poppins(),
                          ),
                        ),
                      )
                      .toList(),
                  cancelButton: CupertinoActionSheetAction(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop();
                    },
                    isDefaultAction: true,
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  CupertinoIcons.chevron_down,
                  color: Colors.black45,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Build rating section with animated stars
  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rating',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (index) => GestureDetector(
              onTap: _submitting ? null : () => _updateRating(index + 1),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0.0,
                  end: index < _rating ? 1.0 : 0.0,
                ),
                duration: Duration(milliseconds: 200 + (index * 50)),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: index < _rating ? 1.0 + (value * 0.1) : 1.0,
                    child: Icon(
                      index < _rating ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      size: 44,
                      color: index < _rating 
                          ? const Color(0xFFFFC107) 
                          : Colors.black26,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _rating == 0 
                ? 'Tap to rate'
                : _rating == 5 
                    ? 'Excellent! ⭐'
                    : _rating == 4 
                        ? 'Great! 👍'
                        : _rating == 3 
                            ? 'Good 👍'
                            : _rating == 2 
                                ? 'Fair'
                                : 'Poor',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: _rating == 0 
                  ? Colors.black54 
                  : const Color(0xFF8D6E63),
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }

  /// Build review text area with character count
  Widget _buildReviewTextArea() {
    final bool isNearLimit = _characterCount > _maxReviewLength * 0.9;
    final bool isOverLimit = _characterCount > _maxReviewLength;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Your review',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                decoration: TextDecoration.none,
              ),
            ),
            Text(
              '$_characterCount / $_maxReviewLength',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: isOverLimit 
                    ? CupertinoColors.systemRed 
                    : isNearLimit 
                        ? const Color(0xFFFF9800) 
                        : Colors.black54,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _error != null 
                  ? CupertinoColors.systemRed 
                  : _focusNode.hasFocus 
                      ? const Color(0xFF8D6E63) 
                      : CupertinoColors.systemGrey4,
              width: _focusNode.hasFocus ? 2 : 1,
            ),
            boxShadow: _focusNode.hasFocus
                ? [
                    BoxShadow(
                      color: const Color(0xFF8D6E63).withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: CupertinoTextField(
            controller: _controller,
            focusNode: _focusNode,
            placeholder: 'Share your thoughts about the product...\n\nWhat did you like? What could be improved?',
            minLines: 6,
            maxLines: 8,
            maxLength: _maxReviewLength,
            style: GoogleFonts.poppins(
              color: Colors.black,
              fontSize: 15,
              height: 1.5,
            ),
            placeholderStyle: GoogleFonts.poppins(
              color: Colors.black45,
              fontSize: 15,
              height: 1.5,
            ),
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Minimum $_minReviewLength characters required',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: _controller.text.trim().length < _minReviewLength 
                ? Colors.black54 
                : const Color(0xFF2E7D32),
            fontWeight: FontWeight.w400,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  /// Build error banner with animation
  Widget _buildErrorBanner() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: CupertinoColors.systemRed.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_circle_fill,
                    color: CupertinoColors.systemRed,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: GoogleFonts.poppins(
                        color: CupertinoColors.systemRed,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build submit button with improved design
  Widget _buildSubmitButton() {
    final bool canSubmit = _isValid && !_submitting && _characterCount <= _maxReviewLength;
    
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: canSubmit ? 1.0 : 0.6),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: canSubmit
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF8D6E63), Color(0xFFFF9800)],
                    )
                  : null,
              color: canSubmit ? null : CupertinoColors.systemGrey4,
              borderRadius: BorderRadius.circular(28),
              boxShadow: canSubmit
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: canSubmit ? _submit : null,
              child: _submitting
                  ? const CupertinoActivityIndicator(
                      color: Colors.white,
                      radius: 12,
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          CupertinoIcons.check_mark_circled_solid,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Submit Review',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 0.5,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}




















