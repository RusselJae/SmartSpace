import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/made_to_order_request.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../widgets/toast.dart';
import 'mto_quote_checkout_screen.dart';
import 'sign_in.dart';

/// Lists the signed-in user's made-to-order requests and next steps (quote → pay).
class MyMadeToOrderRequestsScreen extends StatefulWidget {
  const MyMadeToOrderRequestsScreen({super.key});

  @override
  State<MyMadeToOrderRequestsScreen> createState() => _MyMadeToOrderRequestsScreenState();
}

class _MyMadeToOrderRequestsScreenState extends State<MyMadeToOrderRequestsScreen> {
  static const Color _kWalnut = Color(0xFF5C4033);
  static const Color _kWalnutDeep = Color(0xFF3E2723);
  static const Color _kWalnutSoftBg = Color(0xFFF7F3EF);

  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AuthService _auth = AuthService();

  List<MadeToOrderRequest> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _auth.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushReplacement(
          CupertinoPageRoute(
            builder: (_) => const SignInScreen(),
            fullscreenDialog: true,
          ),
        );
        Toast.info(context, 'Please sign in first');
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final list = await _db.getMadeToOrderRequests(userId: user.id);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(context, 'Could not load requests: $e');
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending_review':
        return 'Under review';
      case 'quoted':
        return 'Quoted — ready to order';
      case 'declined':
        return 'Declined';
      case 'order_created':
        return 'Order placed';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: _kWalnutSoftBg,
        border: Border(
          bottom: BorderSide(
            color: _kWalnut.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: _kWalnut,
        ),
        middle: Text(
          'My custom requests',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: _kWalnut),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : Material(
                color: Colors.transparent,
                child: RefreshIndicator(
                  color: _kWalnut,
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                'No requests yet. Submit one from the catalog or your profile.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54, height: 1.4),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final r = _items[index];
                            return _RequestCard(
                              request: r,
                              statusLabel: _statusLabel(r.status),
                              onPay: r.status == 'quoted' && (r.orderId == null || r.orderId!.isEmpty)
                                  ? () async {
                                      await Navigator.of(context).push<void>(
                                        CupertinoPageRoute(
                                          builder: (_) => MtoQuoteCheckoutScreen(request: r),
                                        ),
                                      );
                                      if (mounted) await _load();
                                    }
                                  : null,
                            );
                          },
                        ),
                ),
              ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.statusLabel,
    this.onPay,
  });

  final MadeToOrderRequest request;
  final String statusLabel;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final bool isQuoted = request.status == 'quoted';
    final String meta = [
      statusLabel,
      if (request.orderId != null && request.orderId!.isNotEmpty) 'Order: ${request.orderId}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFBCAAA4).withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _MyMadeToOrderRequestsScreenState._kWalnut.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isQuoted ? CupertinoIcons.checkmark_alt_circle_fill : CupertinoIcons.doc_text_fill,
                  size: 16,
                  color: _MyMadeToOrderRequestsScreenState._kWalnut,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.itemName,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _MyMadeToOrderRequestsScreenState._kWalnutDeep,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.black54,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isQuoted &&
              request.quotedTotal != null &&
              request.quotedDownpayment != null &&
              request.quotedRemaining != null) ...[
            const SizedBox(height: 10),
            Text(
              'Total ₱${request.quotedTotal!.toStringAsFixed(2)} · '
              'DP ₱${request.quotedDownpayment!.toStringAsFixed(2)} · '
              'Balance ₱${request.quotedRemaining!.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                height: 1.3,
              ),
            ),
          ],
          if ((request.adminMessage ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              request.adminMessage!.trim(),
              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.black87, height: 1.35),
            ),
          ],
          if (onPay != null) ...[
            const SizedBox(height: 12),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onPay,
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: _MyMadeToOrderRequestsScreenState._kWalnut,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Enter shipping & pay deposit',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 16,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
