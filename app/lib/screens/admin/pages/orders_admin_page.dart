import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/made_to_order_request.dart';
import '../../../models/order_record.dart';
import '../../../services/mysql_database_service.dart';
import '../../../config/api_config.dart';
import '../widgets/admin_toolbar.dart';
import '../widgets/admin_anchored_popover.dart';
import '../../../widgets/admin_console_surfaces.dart';
import '../../../widgets/toast.dart';
import '../../../utils/order_payment_balance.dart';

/// Orders management page with search, filtering, and status updates.
/// Follows Apple HIG principles with clean layouts and smooth animations.
class OrdersAdminPage extends StatefulWidget {
  const OrdersAdminPage({super.key});

  @override
  State<OrdersAdminPage> createState() => _OrdersAdminPageState();
}

class _OrdersAdminPageState extends State<OrdersAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _filterAnchorKey = GlobalKey();
  final List<String> _statuses = const ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled'];
  
  List<OrderRecord> _orders = [];
  Map<String, String> _productNames = {}; // Cache product names by ID
  /// First product image URL per id (absolute), for admin order detail thumbnails.
  Map<String, String> _productThumbUrls = {};
  bool _loading = true;
  String _filter = 'all';
  String _searchQuery = '';
  String _sortBy = 'newest';
  DateTime? _createdFrom;
  DateTime? _createdTo;
  String? _error;

  static const int _pageSize = 10;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadOrders();
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

  /// Loads all orders from the database with error handling.
  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await _db.getAllOrders();
      // Fetch all products to get names
      final products = await _db.getAllProducts();
      final productNamesMap = <String, String>{};
      final thumbMap = <String, String>{};
      for (final product in products) {
        productNamesMap[product.id] = product.name;
        if (product.imageUrls.isNotEmpty) {
          final u = _absoluteMediaUrl(product.imageUrls.first);
          if (u.isNotEmpty) thumbMap[product.id] = u;
        }
      }
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _productNames = productNamesMap;
        _productThumbUrls = thumbMap;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load orders: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Filters orders by status and search query for a responsive, fast UI.
  List<OrderRecord> get _filtered {
    var filtered = _filter == 'all' 
        ? _orders 
        : _orders.where((o) => o.status == _filter).toList();
    
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((order) {
        return order.id.toLowerCase().contains(_searchQuery) ||
               order.userName.toLowerCase().contains(_searchQuery) ||
               order.productIds.any((id) => id.toLowerCase().contains(_searchQuery));
      }).toList();
    }

    if (_createdFrom != null) {
      final start = DateTime(_createdFrom!.year, _createdFrom!.month, _createdFrom!.day);
      filtered = filtered.where((order) => !order.createdAt.isBefore(start)).toList();
    }
    if (_createdTo != null) {
      final end = DateTime(_createdTo!.year, _createdTo!.month, _createdTo!.day, 23, 59, 59);
      filtered = filtered.where((order) => !order.createdAt.isAfter(end)).toList();
    }

    switch (_sortBy) {
      case 'oldest':
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'amount_high':
        filtered.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        break;
      case 'amount_low':
        filtered.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
        break;
      case 'customer_az':
        filtered.sort((a, b) => a.userName.toLowerCase().compareTo(b.userName.toLowerCase()));
        break;
      case 'customer_za':
        filtered.sort((a, b) => b.userName.toLowerCase().compareTo(a.userName.toLowerCase()));
        break;
      case 'newest':
      default:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    
    return filtered;
  }

  int get _activeOrderFilterCount {
    var count = 0;
    if (_filter != 'all') count++;
    if (_sortBy != 'newest') count++;
    if (_createdFrom != null || _createdTo != null) count++;
    return count;
  }

  void _showOrderFilterPopover() {
    String tempStatus = _filter;
    String tempSort = _sortBy;
    DateTime? tempFrom = _createdFrom;
    DateTime? tempTo = _createdTo;

    Future<void> pickDate({
      required bool isFrom,
      required void Function(void Function()) setModalState,
    }) async {
      final base = Theme.of(context);
      final pickerTheme = base.copyWith(
        dialogTheme: base.dialogTheme.copyWith(backgroundColor: Colors.white),
        colorScheme: base.colorScheme.copyWith(surface: Colors.white),
        datePickerTheme: base.datePickerTheme.copyWith(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      );
      final picked = await showDatePicker(
        context: context,
        initialDate: (isFrom ? tempFrom : tempTo) ?? DateTime.now(),
        firstDate: DateTime(2020, 1, 1),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: (context, child) => Theme(
          data: pickerTheme,
          child: child ?? const SizedBox.shrink(),
        ),
      );
      if (picked == null) return;
      setModalState(() {
        if (isFrom) {
          tempFrom = picked;
        } else {
          tempTo = picked;
        }
      });
    }

    AdminAnchoredPopover.show<void>(
      context: context,
      anchorKey: _filterAnchorKey,
      width: 380,
      height: 360,
      child: StatefulBuilder(
        builder: (ctx, setModalState) {
          return Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Filter Orders',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sort by',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: tempSort,
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Color(0xFFF8F8F8),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest First')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest First')),
                      DropdownMenuItem(value: 'amount_high', child: Text('Amount: High to Low')),
                      DropdownMenuItem(value: 'amount_low', child: Text('Amount: Low to High')),
                      DropdownMenuItem(value: 'customer_az', child: Text('Customer A–Z')),
                      DropdownMenuItem(value: 'customer_za', child: Text('Customer Z–A')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setModalState(() => tempSort = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Status',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: tempStatus,
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Color(0xFFF8F8F8),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                      ..._statuses.map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text('${s[0].toUpperCase()}${s.substring(1)}'),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setModalState(() => tempStatus = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickDate(
                            isFrom: true,
                            setModalState: setModalState,
                          ),
                          icon: const Icon(Icons.calendar_month_outlined, size: 18),
                          label: Text(
                            tempFrom == null
                                ? 'Created From'
                                : tempFrom!.toIso8601String().split('T').first,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickDate(
                            isFrom: false,
                            setModalState: setModalState,
                          ),
                          icon: const Icon(Icons.event_available_outlined, size: 18),
                          label: Text(
                            tempTo == null
                                ? 'Created To'
                                : tempTo!.toIso8601String().split('T').first,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          setModalState(() {
                            tempStatus = 'all';
                            tempSort = 'newest';
                            tempFrom = null;
                            tempTo = null;
                          });
                        },
                        child: const Text('Reset'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _filter = tempStatus;
                            _sortBy = tempSort;
                            _createdFrom = tempFrom;
                            _createdTo = tempTo;
                            _pageIndex = 0;
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Shows order history dialog with cancelled and delivered orders
  void _showOrderHistory() {
    final cancelledOrders = _orders.where((o) => o.status == 'cancelled').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final deliveredOrders = _orders.where((o) => o.status == 'delivered').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order History',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Tabs for Cancelled and Delivered
              DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: const Color(0xFF8D6E63),
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: const Color(0xFF8D6E63),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Cancelled'),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemRed.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${cancelledOrders.length}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.systemRed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Delivered'),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemGreen.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${deliveredOrders.length}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.systemGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Cancelled orders tab
                          cancelledOrders.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.cancel_outlined, size: 64, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No cancelled orders',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: cancelledOrders.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final order = cancelledOrders[index];
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      title: Text(
                                        'Order #${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            'Customer: ${order.userName.isEmpty ? 'Guest' : order.userName}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Date: ${order.createdAt.toLocal().toString().substring(0, 16)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Total: ₱${order.totalAmount.toStringAsFixed(2)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: CupertinoColors.systemRed.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Text(
                                          'Cancelled',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: CupertinoColors.systemRed,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        _showOrderDetails(order);
                                      },
                                    );
                                  },
                                ),
                          // Delivered orders tab
                          deliveredOrders.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No delivered orders',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: deliveredOrders.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final order = deliveredOrders[index];
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      title: Text(
                                        'Order #${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            'Customer: ${order.userName.isEmpty ? 'Guest' : order.userName}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Date: ${order.createdAt.toLocal().toString().substring(0, 16)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Total: ₱${order.totalAmount.toStringAsFixed(2)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.systemGreen.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: CupertinoColors.systemGreen.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Text(
                                          'Delivered',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: CupertinoColors.systemGreen,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        _showOrderDetails(order);
                                      },
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Admin: set quote line items (total must equal DP + balance).
  Future<bool> _showQuoteMtoDialog(MadeToOrderRequest req) async {
    final totalCtrl = TextEditingController(
      text: req.quotedTotal != null ? req.quotedTotal!.toStringAsFixed(2) : '',
    );
    final dpCtrl = TextEditingController(
      text: req.quotedDownpayment != null ? req.quotedDownpayment!.toStringAsFixed(2) : '',
    );
    final remCtrl = TextEditingController(
      text: req.quotedRemaining != null ? req.quotedRemaining!.toStringAsFixed(2) : '',
    );
    final msgCtrl = TextEditingController(text: req.adminMessage ?? '');

    final borderColor = Colors.grey.shade300;
    const fillColor = Colors.white;
    const focusColor = Color(0xFF8D6E63);

    void recalcRemaining() {
      final total = double.tryParse(totalCtrl.text.trim().replaceAll(',', ''));
      final dp = double.tryParse(dpCtrl.text.trim().replaceAll(',', ''));
      if (total == null || dp == null) {
        remCtrl.text = '';
        return;
      }
      final remaining = (total - dp).toStringAsFixed(2);
      remCtrl.value = TextEditingValue(
        text: remaining,
        selection: TextSelection.collapsed(offset: remaining.length),
      );
    }

    // Keep “Remaining balance” automatically in sync with (Total - Down payment).
    totalCtrl.addListener(recalcRemaining);
    dpCtrl.addListener(recalcRemaining);
    recalcRemaining();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        InputDecoration amountDecoration({
          required String label,
          required String prefix,
          required bool readOnly,
        }) {
          return InputDecoration(
            labelText: label,
            prefixText: prefix,
            filled: true,
            fillColor: fillColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor, width: readOnly ? 1 : 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: focusColor, width: 2),
            ),
          );
        }

        Widget fieldLabel(String text, {bool required = false}) {
          return Row(
            children: [
              Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6D4C41),
                  decoration: TextDecoration.none,
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(color: CupertinoColors.systemRed, fontSize: 16),
                ),
            ],
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 920, maxHeight: 700),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(ctx).pop(false),
                          tooltip: 'Close',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Expanded(
                          child: Text(
                            'Quote request',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                              color: Colors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: AdminConsoleSurfaces.detailCard(
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${req.itemName} · ${req.userName}',
                              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 12),

                            // TOTAL
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  fieldLabel('Total (incl. shipping)', required: true),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: totalCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: amountDecoration(
                                      label: 'Total',
                                      prefix: '₱',
                                      readOnly: false,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // DOWN PAYMENT
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  fieldLabel('Down payment', required: true),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: dpCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: amountDecoration(
                                      label: 'Down payment',
                                      prefix: '₱',
                                      readOnly: false,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // REMAINING (read-only)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  fieldLabel('Remaining balance', required: true),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: remCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    readOnly: true,
                                    decoration: amountDecoration(
                                      label: 'Remaining balance',
                                      prefix: '₱',
                                      readOnly: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // NOTE
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  fieldLabel('Note to customer', required: false),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: msgCtrl,
                                    maxLines: 2,
                                    decoration: InputDecoration(
                                      labelText: 'Optional note',
                                      filled: true,
                                      fillColor: fillColor,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: borderColor),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: borderColor, width: 1),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: focusColor, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(
                            'Save quote',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Cleanup controllers/listeners.
    totalCtrl.removeListener(recalcRemaining);
    dpCtrl.removeListener(recalcRemaining);

    if (result != true) {
      totalCtrl.dispose();
      dpCtrl.dispose();
      remCtrl.dispose();
      msgCtrl.dispose();
      return false;
    }

    final totalParsed = double.tryParse(totalCtrl.text.trim().replaceAll(',', ''));
    final dpParsed = double.tryParse(dpCtrl.text.trim().replaceAll(',', ''));

    totalCtrl.dispose();
    dpCtrl.dispose();
    remCtrl.dispose();

    final msg = msgCtrl.text.trim();
    msgCtrl.dispose();

    if (totalParsed == null || dpParsed == null) {
      if (mounted) Toast.error(context, 'Enter valid numbers for total and down payment');
      return false;
    }

    final totalRounded = double.parse(totalParsed.toStringAsFixed(2));
    final dpRounded = double.parse(dpParsed.toStringAsFixed(2));
    final remainingRounded = double.parse((totalRounded - dpRounded).toStringAsFixed(2));

    try {
      await _db.quoteMadeToOrderRequest(
        requestId: req.id,
        quotedTotal: totalRounded,
        quotedDownpayment: dpRounded,
        quotedRemaining: remainingRounded,
        adminMessage: msg.isEmpty ? null : msg,
      );
      if (mounted) Toast.success(context, 'Quote saved');
      return true;
    } catch (e) {
      if (mounted) Toast.error(context, _humanMessage(e));
      return false;
    }
  }

  Future<bool> _showDeclineMtoDialog(MadeToOrderRequest req) async {
    final msgCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 700),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        tooltip: 'Close',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      Expanded(
                        child: Text(
                          'Decline request',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: Colors.black,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: AdminConsoleSurfaces.detailCard(
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Decline “${req.itemName}” for ${req.userName}?',
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: msgCtrl,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'Reason (optional)',
                              hintText: 'e.g. materials not available for this design',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: CupertinoColors.systemRed,
                        ),
                        child: Text(
                          'Decline',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != true) {
      msgCtrl.dispose();
      return false;
    }
    final msg = msgCtrl.text.trim();
    msgCtrl.dispose();
    try {
      await _db.declineMadeToOrderRequest(
        requestId: req.id,
        adminMessage: msg.isEmpty ? null : msg,
      );
      if (mounted) Toast.success(context, 'Request declined');
      return true;
    } catch (e) {
      if (mounted) Toast.error(context, _humanMessage(e));
      return false;
    }
  }

  Widget _mtoDetailLabelValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
                height: 1.3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AdminConsoleSurfaces.walnutText,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mtoStatusChip(String statusRaw) {
    final status = statusRaw.trim();
    final lower = status.toLowerCase();
    Color bg;
    Color fg;
    if (lower.contains('declin')) {
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade800;
    } else if (lower.contains('order_created') || lower.contains('completed')) {
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
    } else if (lower.contains('quoted') || lower.contains('quote')) {
      bg = AdminConsoleSurfaces.accentBrown.withValues(alpha: 0.14);
      fg = AdminConsoleSurfaces.walnutText;
    } else {
      bg = Colors.blueGrey.shade50;
      fg = Colors.blueGrey.shade800;
    }
    final readable = status.replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Text(
        readable,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _mtoRequestCard(MadeToOrderRequest req, BuildContext dialogContext) {
    final validIdUrl =
        (req.validIdUrl == null || req.validIdUrl!.isEmpty) ? null : _absoluteMediaUrl(req.validIdUrl!);
    final quoted = req.quotedTotal != null &&
        req.quotedDownpayment != null &&
        req.quotedRemaining != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: AdminConsoleSurfaces.profilePanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.itemName.trim().isEmpty ? '—' : req.itemName,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AdminConsoleSurfaces.walnutText,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      req.userName,
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              _mtoStatusChip(req.status),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 10),
          _mtoDetailLabelValue('Request ref', req.requestRef.isEmpty ? '—' : req.requestRef),
          if (quoted)
            _mtoDetailLabelValue(
              'Quote',
              'Total ₱${req.quotedTotal!.toStringAsFixed(2)} · DP ₱${req.quotedDownpayment!.toStringAsFixed(2)} · '
                  'Bal ₱${req.quotedRemaining!.toStringAsFixed(2)}',
            )
          else
            _mtoDetailLabelValue('Down payment (required)', '₱${req.downPaymentAmount.toStringAsFixed(2)}'),
          if ((req.preferredSize ?? '').trim().isNotEmpty)
            _mtoDetailLabelValue('Size', req.preferredSize!.trim()),
          if ((req.materials ?? '').trim().isNotEmpty)
            _mtoDetailLabelValue('Materials', req.materials!.trim()),
          if ((req.notes ?? '').trim().isNotEmpty)
            _mtoDetailLabelValue('Customer notes', req.notes!.trim()),
          if ((req.adminMessage ?? '').trim().isNotEmpty)
            _mtoDetailLabelValue('Admin note', req.adminMessage!.trim()),
          if (validIdUrl != null) ...[
            const SizedBox(height: 4),
            Text(
              'Valid ID',
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _showImageDialog(validIdUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(validIdUrl, height: 96, width: double.infinity, fit: BoxFit.cover),
              ),
            ),
          ],
          if (req.status != 'declined' && req.status != 'order_created') ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminConsoleSurfaces.walnutText,
                    side: BorderSide(color: AdminConsoleSurfaces.accentBrown.withValues(alpha: 0.55)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onPressed: () async {
                    final nav = Navigator.of(dialogContext);
                    final ok = await _showQuoteMtoDialog(req);
                    if (ok && mounted) {
                      nav.pop();
                      await _showMadeToOrderRequests();
                    }
                  },
                  child: Text('Quote', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CupertinoColors.systemRed,
                    side: BorderSide(color: CupertinoColors.systemRed.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onPressed: () async {
                    final nav = Navigator.of(dialogContext);
                    final ok = await _showDeclineMtoDialog(req);
                    if (ok && mounted) {
                      nav.pop();
                      await _showMadeToOrderRequests();
                    }
                  },
                  child: Text('Decline', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showMadeToOrderRequests() async {
    try {
      final requests = await _db.getMadeToOrderRequests();
      if (!mounted) return;
      final screenW = MediaQuery.sizeOf(context).width;
      final screenH = MediaQuery.sizeOf(context).height;
      showDialog(
        context: context,
        builder: (dialogContext) => AdminProfileStyleDetailDialog(
          maxWidth: math.min(980, screenW - 24),
          maxHeight: screenH * 0.9,
          title: 'Made-to-order requests',
          subtitle: 'Quote, decline, or reopen this list after each action.',
          bodyExpands: true,
          body: requests.isEmpty
              ? Center(
                  child: Text(
                    'No made-to-order requests yet',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.black54,
                      decoration: TextDecoration.none,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    return _mtoRequestCard(requests[index], dialogContext);
                  },
                ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to load made-to-order requests: $e');
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Updates order status with a smooth animation and user feedback.
  Future<void> _updateStatus(OrderRecord order, String status) async {
    final remainingBalance = parseShippingDouble(order.shippingAddress, 'remainingBalance') ?? 0.0;
    final normalizedTarget = status.toLowerCase();
    if ((normalizedTarget == 'shipped' || normalizedTarget == 'delivered') &&
        remainingBalance > 0.01) {
      Toast.warning(
        context,
        'Cannot mark as $normalizedTarget while remaining balance is not zero.',
      );
      return;
    }

    // Show confirmation dialog for order confirmation
    if (status == 'confirmed' && order.status != 'confirmed') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Confirm Order',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: Text(
            'Confirming this order will send an email notification to the customer. Continue?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Confirm',
                style: GoogleFonts.poppins(
                  color: CupertinoColors.systemBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      
      if (confirmed != true) {
        return; // User cancelled
      }
    }
    
    try {
      await _db.updateOrderStatus(order.id, status);
      if (!mounted) return;
      
      String message = 'Order #${order.id.length >= 8 ? order.id.substring(0, 8) : order.id} updated to $status';
      if (status == 'confirmed') {
        message += '. Email notification sent to customer.';
      }
      
      Toast.success(context, message);
      
      await _loadOrders();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, _humanMessage(e));
    }
  }

  String _humanMessage(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) return 'Something went wrong. Please try again.';

    // Most of our service exceptions are thrown as `Exception("Human message")`.
    // Strip the Dart prefix so the UI stays clean and customer/admin-friendly.
    var msg = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();

    // Avoid nested prefixes like "Failed to X: <human message>" when upstream code
    // already provides the human-facing string.
    final colon = msg.indexOf(':');
    if (colon > 0) {
      final left = msg.substring(0, colon).toLowerCase();
      if (left.startsWith('failed') || left.contains('error')) {
        msg = msg.substring(colon + 1).trim();
      }
    }

    return msg.isEmpty ? 'Something went wrong. Please try again.' : msg;
  }

  /// Shows detailed order information in a centered modal dialog following Apple's
  /// modal presentation style.
  void _showOrderDetails(OrderRecord order) {
    showDialog(
      context: context,
      builder: (context) => _OrderDetailsDialog(
        order: order,
        productNames: _productNames,
        productThumbUrls: _productThumbUrls,
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
    final pageItems = totalCount == 0 ? const <OrderRecord>[] : filtered.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Orders',
          actions: const [],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search orders by ID, customer, or product...',
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
                      borderSide: BorderSide(color: CupertinoColors.systemBlue.withValues(alpha: 0.5), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Stack(
                children: [
                  SizedBox(
                    key: _filterAnchorKey,
                    child: IconButton.outlined(
                      onPressed: _showOrderFilterPopover,
                      icon: const Icon(Icons.tune_outlined),
                      tooltip: 'Filter',
                    ),
                  ),
                  if (_activeOrderFilterCount > 0)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: const BoxDecoration(
                          color: Color(0xFF8D6E63),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$_activeOrderFilterCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _showMadeToOrderRequests,
                icon: const Icon(Icons.design_services_outlined, size: 18),
                label: const Text('Made-to-Order'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5C4033),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: () {
                  Toast.info(context, 'Export functionality coming soon');
                },
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Export',
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadOrders,
                tooltip: 'Refresh orders',
              ),
            ],
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            '${filtered.length} ${filtered.length == 1 ? 'order' : 'orders'}',
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
                          Icon(Icons.shopping_bag_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty || _filter != 'all'
                                ? 'No orders match your filters'
                                : 'No orders yet',
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
                  : Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: CupertinoColors.separator.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          _OrdersHeaderRow(onAnyTap: () {}),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: CupertinoColors.separator.withValues(alpha: 0.1),
                          ),
                          Expanded(
                            child: ListView.separated(
                              itemCount: pageItems.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                thickness: 1,
                                indent: 16,
                                endIndent: 16,
                                color: CupertinoColors.separator.withValues(alpha: 0.1),
                              ),
                              itemBuilder: (context, index) {
                                final order = pageItems[index];
                                return _OrdersTableRow(
                                  order: order,
                                  productNames: _productNames,
                                  onTap: () => _showOrderDetails(order),
                                  onStatusChanged: (value) => _updateStatus(order, value),
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

class _OrdersHeaderRow extends StatelessWidget {
  const _OrdersHeaderRow({required this.onAnyTap});

  final VoidCallback onAnyTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Order ID',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Customer',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'City',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Date',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Total',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Balance',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              'Status',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 70),
        ],
      ),
    );
  }
}

class _OrdersTableRow extends StatelessWidget {
  const _OrdersTableRow({
    required this.order,
    required this.productNames,
    required this.onTap,
    required this.onStatusChanged,
  });

  final OrderRecord order;
  final Map<String, String> productNames;
  final VoidCallback onTap;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final dateStr = order.createdAt.toLocal().toString().substring(0, 10);
    return InkWell(
      onTap: onTap,
      hoverColor: CupertinoColors.systemGrey6.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                '#${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: CupertinoColors.label,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                order.userName.isEmpty ? 'Guest user' : order.userName,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: CupertinoColors.label,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    order.shippingAddress['city']?.toString() ?? '-',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: CupertinoColors.secondaryLabel,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (order.productIds.isNotEmpty)
                    Text(
                      '${order.productIds.length} ${order.productIds.length == 1 ? 'item' : 'items'}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: CupertinoColors.tertiaryLabel,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                dateStr,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '₱${order.totalAmount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                adminOrdersBalanceColumnText(order),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: adminOrdersBalanceColumnHighlighted(order)
                      ? const Color(0xFFE65100)
                      : CupertinoColors.secondaryLabel,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _StatusPill(
                status: order.status,
                onChanged: onStatusChanged,
                isEditable: order.status != 'delivered' && order.status != 'cancelled',
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: const Size(70, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.3)),
                ),
                backgroundColor: Colors.transparent,
              ),
              child: Text(
                'View',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.systemBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.onChanged,
    this.isEditable = true,
  });

  final String status;
  final ValueChanged<String> onChanged;
  final bool isEditable; // Whether the status can be edited

  /// Returns a clean, light color palette for status indicators
  /// Following Apple HIG with subtle, approachable colors
  Color _statusColor(String value) {
    switch (value) {
      case 'pending':
        return Colors.yellow.shade700; // Yellow color for pending status
      case 'confirmed':
        return CupertinoColors.systemBlue;
      case 'shipped':
        return CupertinoColors.systemTeal;
      case 'delivered':
        return CupertinoColors.systemGreen;
      case 'cancelled':
        return CupertinoColors.systemRed;
      default:
        return CupertinoColors.systemGrey;
    }
  }

  /// Icon per status for clearer affordance in the dropdown
  IconData _statusIcon(String value) {
    switch (value) {
      case 'pending':
        return Icons.hourglass_top_outlined;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'shipped':
        return Icons.local_shipping_outlined;
      case 'delivered':
        return Icons.task_alt_outlined;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final isDeliveredOrCancelled = status == 'delivered' || status == 'cancelled';
    
    // For delivered and cancelled orders, show non-editable status pill
    if (!isEditable || isDeliveredOrCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                status[0].toUpperCase() + status.substring(1),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Only show dropdown icon if editable and not delivered/cancelled
            if (isEditable && !isDeliveredOrCancelled) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.expand_more,
                size: 16,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      );
    }
    
    // For editable orders, show dropdown menu
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final s in const ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled'])
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                Icon(_statusIcon(s), size: 18, color: _statusColor(s)),
                const SizedBox(width: 10),
                Text(
                  s[0].toUpperCase() + s.substring(1),
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                status[0].toUpperCase() + status.substring(1),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more,
              size: 16,
              color: color.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same rules as payment-proof URLs: relative paths become absolute against the API host.
String _absoluteMediaUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
  final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
  if (trimmed.startsWith('/')) return '$baseUrl$trimmed';
  return '$baseUrl/$trimmed';
}

/// Pretty-print API ISO date for admin detail rows.
String _formatAdminDeliveryDate(String iso) {
  try {
    return DateTime.parse(iso).toLocal().toString().substring(0, 16);
  } catch (_) {
    return iso;
  }
}

/// Centered dialog showing detailed order information in Apple's modal style.
class _OrderDetailsDialog extends StatelessWidget {
  const _OrderDetailsDialog({
    required this.order,
    required this.productNames,
    required this.productThumbUrls,
  });

  final OrderRecord order;
  final Map<String, String> productNames;
  final Map<String, String> productThumbUrls;

  String _paymentMethodLabel(String? raw) {
    final pm = raw?.toString().trim().toLowerCase() ?? '';
    if (pm.isEmpty) return '—';
    switch (pm) {
      case 'paymongo':
      case 'gcash':
        return 'GCash';
      case 'cod':
        return 'Cash on Delivery (COD)';
      default:
        return raw!.toString();
    }
  }

  /// Core metadata rows; split into two columns on wide modals to reduce vertical scroll.
  List<Widget> _orderInfoRows() {
    return [
      AdminProfileStyleDetailRow(dense: true, showDivider: false, label: 'Order ID', value: order.id),
      AdminProfileStyleDetailRow(dense: true, showDivider: false, label: 'Customer', value: order.userName.isNotEmpty ? order.userName : 'Guest'),
      AdminProfileStyleDetailRow(dense: true, showDivider: false, label: 'Status', value: order.status[0].toUpperCase() + order.status.substring(1)),
      AdminProfileStyleDetailRow(dense: true, showDivider: false,
        label: 'Total Amount',
        value: '₱${order.totalAmount.toStringAsFixed(2)}',
      ),
      AdminProfileStyleDetailRow(dense: true, showDivider: false,
        label: 'Mode of Payment',
        value: _paymentMethodLabel(order.shippingAddress['paymentMethod']?.toString()),
      ),
      AdminProfileStyleDetailRow(dense: true, showDivider: false,
        label: 'Payment plan',
        value: order.shippingAddress['paymentPlan']?.toString() ?? '—',
      ),
      AdminProfileStyleDetailRow(dense: true, showDivider: false,
        label: 'Order Option',
        value: order.shippingAddress['orderOption']?.toString() ?? '—',
      ),
      AdminProfileStyleDetailRow(dense: true, showDivider: false,
        label: 'Payment Status',
        value: order.shippingAddress['paymentStatus']?.toString() ?? '—',
      ),
      if (order.status.toLowerCase() == 'cancelled' &&
          order.shippingAddress['cancellationReason'] != null &&
          order.shippingAddress['cancellationReason'].toString().trim().isNotEmpty)
        AdminProfileStyleDetailRow(dense: true, showDivider: false,
          label: 'Cancellation reason',
          value: order.shippingAddress['cancellationReason'].toString(),
        ),
      if (order.shippingAddress['estimatedDeliveryAt'] != null &&
          order.shippingAddress['estimatedDeliveryAt'].toString().isNotEmpty)
        AdminProfileStyleDetailRow(dense: true, showDivider: false,
          label: 'Est. delivery (from confirm +10–12d)',
          value: _formatAdminDeliveryDate(
            order.shippingAddress['estimatedDeliveryAt'].toString(),
          ),
        ),
      if (parseShippingDouble(order.shippingAddress, 'downpayment') != null)
        AdminProfileStyleDetailRow(dense: true, showDivider: false,
          label: 'Down Payment (line)',
          value: '₱${parseShippingDouble(order.shippingAddress, 'downpayment')!.toStringAsFixed(2)}',
        ),
      if (parseShippingDouble(order.shippingAddress, 'remainingBalance') != null)
        AdminProfileStyleDetailRow(dense: true, showDivider: false,
          label: 'Remaining Balance',
          value: '₱${parseShippingDouble(order.shippingAddress, 'remainingBalance')!.toStringAsFixed(2)}',
        ),
      if (parseFirstInstallmentPaidAt(order) != null)
        AdminProfileStyleDetailRow(dense: true, showDivider: false,
          label: 'First GCash (window start)',
          value: parseFirstInstallmentPaidAt(order)!.toLocal().toString().substring(0, 19),
        ),
      if (shouldShowInstallmentBalanceUi(order)) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            installmentInterestCountdownLine(order, DateTime.now()),
            style: GoogleFonts.poppins(
              fontSize: 13,
              height: 1.4,
              color: Colors.grey[800],
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
      if (order.shippingAddress['phone'] != null)
        AdminProfileStyleDetailRow(dense: true, showDivider: false,
          label: 'Contact Phone',
          value: order.shippingAddress['phone'].toString(),
        ),
      AdminProfileStyleDetailRow(dense: true, showDivider: false,
        label: 'Created',
        value: order.createdAt.toLocal().toString().substring(0, 19),
      ),
      AdminProfileStyleDetailRow(dense: true, showDivider: false,
        label: 'Last Updated',
        value: order.updatedAt.toLocal().toString().substring(0, 19),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final maxDialogW = math.min(1240.0, screenW - 16);

    return AdminProfileStyleDetailDialog(
      maxWidth: maxDialogW,
      maxHeight: MediaQuery.of(context).size.height * 0.94,
      title: 'Order Details',
      subtitle: 'Payments, fulfillment, catalog lines, and shipping context.',
      headerTrailing: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Icon(Icons.receipt_long_rounded, size: 40, color: AdminConsoleSurfaces.accentBrown),
      ),
      body: AdminConsoleSurfaces.detailCard(
        child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final rows = _orderInfoRows();
                        final wide = constraints.maxWidth >= 640;
                        if (!wide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: rows,
                          );
                        }
                        final mid = (rows.length + 1) ~/ 2;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: rows.sublist(0, mid),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: rows.sublist(mid),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Products (${order.productIds.length})',
                      style: GoogleFonts.poppins(
                        color: AdminConsoleSurfaces.walnutText,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (order.productIds.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'No products',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    else
                      ...order.productIds.map((id) {
                        final productName = productNames[id] ?? id;
                        final thumb = productThumbUrls[id];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: thumb != null && thumb.isNotEmpty
                                        ? Image.network(
                                            thumb,
                                            fit: BoxFit.cover,
                                            headers: const {'Accept': 'image/*'},
                                            errorBuilder: (_, __, ___) => const _ProductThumbPlaceholder(),
                                            loadingBuilder: (context, child, progress) {
                                              if (progress == null) return child;
                                              return Container(
                                                color: Colors.grey[200],
                                                alignment: Alignment.center,
                                                child: const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                              );
                                            },
                                          )
                                        : const _ProductThumbPlaceholder(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        productName.trim(),
                                        style: GoogleFonts.poppins(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                      'ID: $id',
                                        style: GoogleFonts.poppins(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    Text(
                      'Shipping Address',
                      style: GoogleFonts.poppins(
                        color: AdminConsoleSurfaces.walnutText,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (order.shippingAddress['name'] != null && order.shippingAddress['name'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                order.shippingAddress['name'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.black,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['phone'] != null && order.shippingAddress['phone'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                order.shippingAddress['phone'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['line1'] != null && order.shippingAddress['line1'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                order.shippingAddress['line1'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.black,
                                  fontSize: 15,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['line2'] != null && order.shippingAddress['line2'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                order.shippingAddress['line2'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.black,
                                  fontSize: 15,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['city'] != null && order.shippingAddress['city'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${order.shippingAddress['city'].toString().trim()}${order.shippingAddress['postalCode'] != null && order.shippingAddress['postalCode'].toString().trim().isNotEmpty ? ', ${order.shippingAddress['postalCode'].toString().trim()}' : ''}',
                                style: GoogleFonts.poppins(
                                  color: Colors.black,
                                  fontSize: 15,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['label'] != null && order.shippingAddress['label'].toString().trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                order.shippingAddress['label'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.blue[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Valid ID Section (made-to-order / installment KYC)
                    Builder(
                      builder: (context) {
                        final rawValidIdUrl =
                            order.shippingAddress['validIdUrl']?.toString().trim() ?? '';
                        if (rawValidIdUrl.isEmpty) return const SizedBox.shrink();

                        final validIdUrl = _absoluteMediaUrl(rawValidIdUrl);
                        if (validIdUrl.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            Text(
                              'Valid ID',
                              style: GoogleFonts.poppins(
                                color: AdminConsoleSurfaces.walnutText,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Government ID proof:',
                                    style: GoogleFonts.poppins(
                                      color: Colors.black,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (dialogContext) => Dialog(
                                          backgroundColor: Colors.transparent,
                                          insetPadding: const EdgeInsets.all(20),
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: InteractiveViewer(
                                                  minScale: 0.5,
                                                  maxScale: 4.0,
                                                  child: Image.network(
                                                    validIdUrl,
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return Container(
                                                        padding: const EdgeInsets.all(40),
                                                        color: Colors.black54,
                                                        child: const Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons.error_outline,
                                                              color: Colors.white,
                                                              size: 48,
                                                            ),
                                                            SizedBox(height: 12),
                                                            Text(
                                                              'Failed to load image',
                                                              style: TextStyle(color: Colors.white),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: IconButton(
                                                  icon: const Icon(Icons.close, color: Colors.white),
                                                  onPressed: () => Navigator.of(dialogContext).pop(),
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: Colors.black54,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        validIdUrl,
                                        width: double.infinity,
                                        height: 200,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            height: 200,
                                            alignment: Alignment.center,
                                            color: Colors.grey[200],
                                            child: const Icon(
                                              Icons.verified_outlined,
                                              size: 44,
                                              color: Colors.grey,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    // Payment Proof Section
                    // Check for payment proof URL in order field first, then fall back to shippingAddress
                    if (order.paymentProofUrl != null ||
                        order.shippingAddress['paymentProofUrl'] != null ||
                        order.shippingAddress['paymentProof'] != null)
                      ...[
                        const SizedBox(height: 12),
                        Text(
                          'Payment Proof',
                          style: GoogleFonts.poppins(
                            color: AdminConsoleSurfaces.walnutText,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Get payment proof URL from order field first, then shippingAddress (for backward compatibility)
                              Builder(
                                builder: (context) {
                                  final proofUrl = order.paymentProofUrl ??
                                      order.shippingAddress['paymentProofUrl'] as String? ??
                                      order.shippingAddress['paymentProof'] as String?;
                                  
                                  if (proofUrl == null || proofUrl.isEmpty) {
                                    return Text(
                                      'No payment proof available',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                        decoration: TextDecoration.none,
                                      ),
                                    );
                                  }
                                  
                                  // Convert relative URL to absolute if needed
                                  String finalImageUrl = proofUrl;
                                  
                                  // If URL is relative (starts with /), construct full URL
                                  if (finalImageUrl.startsWith('/')) {
                                    // Remove /api from base URL if present, then append the image path
                                    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
                                    finalImageUrl = '$baseUrl$finalImageUrl';
                                  } else if (!finalImageUrl.startsWith('http')) {
                                    // If it's a relative path without leading slash, prepend base URL
                                    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
                                    finalImageUrl = '$baseUrl/$finalImageUrl';
                                  }
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Payment Screenshot:',
                                        style: GoogleFonts.poppins(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Display payment proof image with tap to view full size
                                      Builder(
                                        builder: (context) {
                                          // Use the already constructed finalImageUrl
                                          
                                          return GestureDetector(
                                            onTap: () {
                                              // Show full-size image in a dialog with zoom capability
                                              showDialog(
                                                context: context,
                                                builder: (dialogContext) => Dialog(
                                                  backgroundColor: Colors.transparent,
                                                  insetPadding: const EdgeInsets.all(20),
                                                  child: Stack(
                                                    children: [
                                                      Center(
                                                        child: InteractiveViewer(
                                                          minScale: 0.5,
                                                          maxScale: 4.0,
                                                          child: Image.network(
                                                            finalImageUrl,
                                                            fit: BoxFit.contain,
                                                            errorBuilder: (context, error, stackTrace) {
                                                              return Container(
                                                                padding: const EdgeInsets.all(40),
                                                                color: Colors.black54,
                                                                child: const Column(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    Icon(Icons.error_outline, color: Colors.white, size: 48),
                                                                    SizedBox(height: 12),
                                                                    Text('Failed to load image', style: TextStyle(color: Colors.white)),
                                                                  ],
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                      Positioned(
                                                        top: 8,
                                                        right: 8,
                                                        child: IconButton(
                                                          icon: const Icon(Icons.close, color: Colors.white),
                                                          onPressed: () => Navigator.of(dialogContext).pop(),
                                                          style: IconButton.styleFrom(
                                                            backgroundColor: Colors.black54,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.network(
                                                finalImageUrl,
                                                width: double.infinity,
                                                fit: BoxFit.contain,
                                                headers: const {
                                                  'Accept': 'image/*',
                                                },
                                                loadingBuilder: (context, child, loadingProgress) {
                                                  if (loadingProgress == null) return child;
                                                  return Container(
                                                    height: 200,
                                                    color: Colors.grey[200],
                                                    child: Center(
                                                      child: CircularProgressIndicator(
                                                        value: loadingProgress.expectedTotalBytes != null
                                                            ? loadingProgress.cumulativeBytesLoaded /
                                                                loadingProgress.expectedTotalBytes!
                                                            : null,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                errorBuilder: (context, error, stackTrace) {
                                                  // Log the error for debugging
                                                  developer.log(
                                                    'Failed to load payment proof image: $error',
                                                    name: 'OrdersAdmin',
                                                    error: error,
                                                    stackTrace: stackTrace,
                                                  );
                                                  developer.log('Image URL: $finalImageUrl', name: 'OrdersAdmin');
                                                  
                                                  return Container(
                                                    height: 200,
                                                    color: Colors.grey[200],
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        const Icon(
                                                          Icons.error_outline,
                                                          color: Colors.red,
                                                          size: 48,
                                                        ),
                                                        const SizedBox(height: 8),
                                                        Text(
                                                          'Failed to load image',
                                                          style: GoogleFonts.poppins(
                                                            color: Colors.grey[600],
                                                            fontSize: 14,
                                                            decoration: TextDecoration.none,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Padding(
                                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                                          child: Text(
                                                            finalImageUrl.length > 50 
                                                                ? '${finalImageUrl.substring(0, 50)}...'
                                                                : finalImageUrl,
                                                            style: GoogleFonts.poppins(
                                                              color: Colors.grey[500],
                                                              fontSize: 10,
                                                              decoration: TextDecoration.none,
                                                            ),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 8),
                                                        TextButton(
                                                          onPressed: () {
                                                            // Trigger rebuild to retry loading
                                                            (context as Element).markNeedsBuild();
                                                          },
                                                          child: const Text('Retry'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap image to view full size',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                          fontStyle: FontStyle.italic,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Payment status
                                      if (order.shippingAddress['paymentStatus'] != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                    order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                ? Colors.green[50]
                                                : Colors.orange[50],
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                      order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                  ? Colors.green[300]!
                                                  : Colors.orange[300]!,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                        order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                    ? Icons.check_circle
                                                    : Icons.pending,
                                                size: 16,
                                                color: order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                        order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                    ? Colors.green[700]
                                                    : Colors.orange[700],
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Payment Status: ${(order.shippingAddress['paymentStatus'] as String? ?? 'pending').toUpperCase()}',
                                                style: GoogleFonts.poppins(
                                                  color: order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                          order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                      ? Colors.green[700]
                                                      : Colors.orange[700],
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  decoration: TextDecoration.none,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                  ],
                ),
              ),
    );
  }
}

/// Shown when a product has no image or the network request fails (HIG: clear empty state).
class _ProductThumbPlaceholder extends StatelessWidget {
  const _ProductThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE8EAED),
      child: Center(
        child: Icon(Icons.chair_outlined, size: 26, color: Colors.grey[500]),
      ),
    );
  }
}
