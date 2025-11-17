import 'package:flutter/material.dart';

import '../../../models/order_record.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';

class OrdersAdminPage extends StatefulWidget {
  const OrdersAdminPage({super.key});

  @override
  State<OrdersAdminPage> createState() => _OrdersAdminPageState();
}

class _OrdersAdminPageState extends State<OrdersAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final List<String> _statuses = const ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled'];
  List<OrderRecord> _orders = [];
  bool _loading = true;
  String _filter = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await _db.getAllOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
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

  List<OrderRecord> get _filtered => _filter == 'all' ? _orders : _orders.where((o) => o.status == _filter).toList();

  Future<void> _updateStatus(OrderRecord order, String status) async {
    await _db.updateOrderStatus(order.id, status);
    await _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Orders',
          actions: [
            AdminToolbarAction(label: 'Export', icon: Icons.download, primary: true, onPressed: () {}),
          ],
          trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _loadOrders),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<String>(
            segments: [
              const ButtonSegment<String>(value: 'all', label: Text('All')),
              ..._statuses.map((status) => ButtonSegment<String>(value: status, label: Text(status))),
            ],
            selected: {_filter},
            onSelectionChanged: (Set<String> values) => setState(() => _filter = values.first),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const Center(child: Text('No orders yet.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemBuilder: (context, index) {
                        final order = filtered[index];
                        return _OrderCard(
                          order: order,
                          statuses: _statuses,
                          onStatusChanged: (value) => _updateStatus(order, value),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: filtered.length,
                    ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.statuses, required this.onStatusChanged});

  final OrderRecord order;
  final List<String> statuses;
  final ValueChanged<String> onStatusChanged;

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF39C12);
      case 'confirmed':
        return Colors.blueGrey;
      case 'shipped':
        return const Color(0xFF2980B9);
      case 'delivered':
        return const Color(0xFF27AE60);
      case 'cancelled':
        return const Color(0xFFC0392B);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = _statusColor(order.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Order ${order.id}', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(order.createdAt.toLocal().toIso8601String().substring(0, 10)),
              ],
            ),
            const SizedBox(height: 8),
            Text(order.userName, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  label: Text(order.status),
                  backgroundColor: statusColor.withAlpha(30),
                  labelStyle: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: order.status,
                    decoration: const InputDecoration(labelText: 'Update status'),
                    items: statuses.map((status) => DropdownMenuItem(value: status, child: Text(status))).toList(),
                    onChanged: (value) {
                      if (value != null && value != order.status) {
                        onStatusChanged(value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Total: \$${order.totalAmount.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            Text('Products: ${order.productIds.join(', ')}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              'Ship to: ${order.shippingAddress['line1'] ?? ''}, '
              '${order.shippingAddress['city'] ?? ''} ${order.shippingAddress['country'] ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

