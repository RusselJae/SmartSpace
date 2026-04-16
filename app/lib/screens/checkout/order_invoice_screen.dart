import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/product.dart';
import '../../services/mysql_database_service.dart';
import '../../widgets/toast.dart';

class OrderInvoiceScreen extends StatefulWidget {
  const OrderInvoiceScreen({
    super.key,
    required this.orderId,
    required this.userId,
    this.autoDownload = false,
  });

  final String orderId;
  final String userId;
  final bool autoDownload;

  @override
  State<OrderInvoiceScreen> createState() => _OrderInvoiceScreenState();
}

class _OrderInvoiceScreenState extends State<OrderInvoiceScreen> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final DateFormat _dateFmt = DateFormat('d MMM yyyy');

  static const Color _kWalnut = Color(0xFF5C4033);

  bool _loading = true;
  bool _downloading = false;
  String? _error;
  Map<String, dynamic>? _invoice;
  Map<String, Product> _productById = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invoiceData = await _db.getOrderInvoiceData(
        orderId: widget.orderId,
        userId: widget.userId,
      );
      final products = await _db.getAllProducts();
      if (!mounted) return;
      setState(() {
        _invoice = invoiceData;
        _productById = {for (final p in products) p.id: p};
        _loading = false;
      });
      if (widget.autoDownload) {
        await _downloadPdfA4();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        _loading = false;
      });
    }
  }

  String _currency(num? v) => '₱${(v ?? 0).toStringAsFixed(2)}';

  String _safeDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '—';
    return _dateFmt.format(parsed.toLocal());
  }

  List<MapEntry<String, int>> _lineItems() {
    final order = (_invoice?['order'] as Map<String, dynamic>? ?? const {});
    final ids = (order['productIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);
    final qty = <String, int>{};
    for (final id in ids) {
      qty[id] = (qty[id] ?? 0) + 1;
    }
    return qty.entries.toList(growable: false);
  }

  Future<void> _downloadPdfA4() async {
    if (_invoice == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _buildPdfA4();
      final filename = 'invoice_${widget.orderId.substring(0, widget.orderId.length.clamp(0, 10))}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: filename);
      if (!mounted) return;
      Toast.success(context, 'Invoice PDF ready to download');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<Uint8List> _buildPdfA4() async {
    final inv = _invoice!;
    final order = (inv['order'] as Map<String, dynamic>? ?? const {});
    final shipping = (order['shippingAddress'] as Map<String, dynamic>? ?? const {});
    final items = _lineItems();

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Wood Home Furniture Trading', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 10),
                      pw.Text((shipping['name'] ?? order['userName'] ?? 'Customer').toString()),
                      pw.Text((shipping['line1'] ?? '').toString()),
                      pw.Text((shipping['city'] ?? '').toString()),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Invoice', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 10),
                      pw.Text('Invoice #: ${inv['invoiceNumber'] ?? widget.orderId}'),
                      pw.Text('Invoice Date: ${_safeDate(order['createdAt'])}'),
                      pw.Text('Invoice Amount: ${_currency(order['totalAmount'] as num?)}'),
                      pw.Text('Customer ID: ${widget.userId}'),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Container(height: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('DESCRIPTION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('AMOUNT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Container(height: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 12),
              ...items.map((entry) {
                final p = _productById[entry.key];
                final unit = p?.price ?? 0;
                final line = unit * entry.value;
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(child: pw.Text('${p?.name ?? 'Item'} x${entry.value}')),
                      pw.Text(_currency(line)),
                    ],
                  ),
                );
              }),
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Total: ${_currency(order['totalAmount'] as num?)}'),
                    pw.Text('Amount Due: ${_currency(inv['totalBalanceDue'] as num?)}',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              // Notes: must match the in-app invoice card so printed/downloaded PDFs align.
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  'Notes: Please pay your invoice within 6 months of receiving it',
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;
    final order = (inv?['order'] as Map<String, dynamic>? ?? const {});
    final shipping = (order['shippingAddress'] as Map<String, dynamic>? ?? const {});
    final lineItems = _lineItems();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: _kWalnut,
        ),
        middle: Text('Invoice', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _downloading || inv == null ? null : _downloadPdfA4,
          child: _downloading
              ? const CupertinoActivityIndicator()
              : Text('PDF', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: GoogleFonts.poppins()))
                : ListView(
                    // Keep generous canvas breathing room like the reference invoice.
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F8FA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header block: left sender + right invoice meta.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          // Wood Home logo (replaces the legacy wordmark).
                                          Image.asset(
                                            'assets/images/logo2.png',
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.contain,
                                            errorBuilder: (context, _, __) => const Icon(
                                              CupertinoIcons.cube_box,
                                              size: 28,
                                              color: _kWalnut,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        (shipping['name'] ?? order['userName'] ?? 'Customer').toString(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (shipping['line1'] ?? '').toString(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: const Color(0xFF374151),
                                        ),
                                      ),
                                      Text(
                                        (shipping['city'] ?? '').toString(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: const Color(0xFF374151),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'BILLED TO',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                          color: const Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (shipping['line1'] ?? '').toString(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: const Color(0xFF374151),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 170,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Invoice',
                                        style: GoogleFonts.poppins(
                                          fontSize: 40 * 0.72,
                                          fontWeight: FontWeight.w700,
                                          height: 1.0,
                                          color: const Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Invoice: ',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                            TextSpan(
                                              text: '#${inv?['invoiceNumber'] ?? widget.orderId}',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Invoice Date: ',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                            TextSpan(
                                              text: _safeDate(order['createdAt']),
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Invoice Amount: ',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                            TextSpan(
                                              text: _currency(order['totalAmount'] as num?),
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Customer ID: ',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                            TextSpan(
                                              text: '#${widget.userId}',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (inv?['totalBalanceDue'] as num? ?? 0) <= 0.01 ? 'Paid' : 'Pending',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: (inv?['totalBalanceDue'] as num? ?? 0) <= 0.01
                                              ? const Color(0xFF16A34A)
                                              : const Color(0xFFB45309),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'DESCRIPTION',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF111827),
                                  ),
                                ),
                                Text(
                                  'AMOUNT',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF111827),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            const SizedBox(height: 12),
                            ...lineItems.map((entry) {
                              final p = _productById[entry.key];
                              final line = (p?.price ?? 0) * entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${p?.name ?? 'Item'} x${entry.value}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: const Color(0xFF111827),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _currency(line),
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: const Color(0xFF111827),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  SizedBox(
                                    width: 170,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Total',
                                            style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF374151))),
                                        Text(
                                          _currency(order['totalAmount'] as num?),
                                          style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF111827)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 170,
                                    child: Text.rich(
                                      textAlign: TextAlign.right,
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Amount Due ',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF111827),
                                            ),
                                          ),
                                          TextSpan(
                                            text: _currency(inv?['totalBalanceDue'] as num?),
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF111827),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0EEF9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Notes: Please pay your invoice within 6 months of receiving it',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: const Color(0xFF4B5563),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      CupertinoButton.filled(
                        onPressed: _downloading ? null : _downloadPdfA4,
                        child: Text(
                          _downloading ? 'Preparing PDF...' : 'Download PDF (A4)',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

