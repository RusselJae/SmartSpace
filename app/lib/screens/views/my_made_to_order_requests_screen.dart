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
      backgroundColor: const Color(0xFFF8F7F5),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.itemName,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            statusLabel,
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54, height: 1.2),
          ),
          if (request.status == 'quoted' &&
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
          if (request.orderId != null && request.orderId!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Order ID: ${request.orderId}',
              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.black54, height: 1.3),
            ),
          ],
          if (onPay != null) ...[
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: onPay,
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Text(
                  'Enter shipping & pay deposit',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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
