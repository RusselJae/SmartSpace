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
          'My Custom Requests',
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

  /// Status line under the title (matches tone of address / review secondary lines).
  String get _subtitleLine {
    final parts = <String>[statusLabel];
    if (request.orderId != null && request.orderId!.isNotEmpty) {
      parts.add('Order ${request.orderId}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final bool isQuoted = request.status == 'quoted';
    final bool isPending = request.status == 'pending_review';
    final bool isDeclined = request.status == 'declined';

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
                      _subtitleLine,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.black54,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _RequestAmountPanel(
            request: request,
            isQuoted: isQuoted,
            isPending: isPending,
            isDeclined: isDeclined,
          ),
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

/// Amount / status detail block — separate layouts for quoted vs pending vs declined
/// so values are scannable (not a single dense line).
class _RequestAmountPanel extends StatelessWidget {
  const _RequestAmountPanel({
    required this.request,
    required this.isQuoted,
    required this.isPending,
    required this.isDeclined,
  });

  final MadeToOrderRequest request;
  final bool isQuoted;
  final bool isPending;
  final bool isDeclined;

  static const Color _kWalnut = Color(0xFF5C4033);
  static const Color _kWalnutDeep = Color(0xFF3E2723);

  @override
  Widget build(BuildContext context) {
    if (isQuoted &&
        request.quotedTotal != null &&
        request.quotedDownpayment != null &&
        request.quotedRemaining != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3EF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _kWalnut.withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'QUOTE',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: _kWalnut.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 10),
            _labeledAmountRow(
              label: 'Total',
              value: '₱${request.quotedTotal!.toStringAsFixed(2)}',
              emphasize: true,
            ),
            const SizedBox(height: 8),
            _labeledAmountRow(
              label: 'Down payment',
              value: '₱${request.quotedDownpayment!.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 8),
            _labeledAmountRow(
              label: 'Balance after DP',
              value: '₱${request.quotedRemaining!.toStringAsFixed(2)}',
            ),
          ],
        ),
      );
    }

    if (isPending) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBCAAA4).withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'REVIEW',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: _kWalnut.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 8),
            if (request.downPaymentAmount > 0.009) ...[
              _labeledAmountRow(
                label: 'Inquiry deposit (reference)',
                value: '₱${request.downPaymentAmount.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 6),
              Text(
                'Final pricing comes after we review your request.',
                style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.black54, height: 1.35),
              ),
            ] else
              Text(
                'Awaiting admin quote — no deposit on file.',
                style: GoogleFonts.poppins(fontSize: 12.5, color: _kWalnutDeep, height: 1.35),
              ),
          ],
        ),
      );
    }

    if (isDeclined) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DECLINED',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Colors.black45,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No quote was issued for this request.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.black54, height: 1.35),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _labeledAmountRow({
    required String label,
    required String value,
    bool emphasize = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
              height: 1.25,
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: GoogleFonts.poppins(
              fontSize: emphasize ? 15 : 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              color: _kWalnutDeep,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}
