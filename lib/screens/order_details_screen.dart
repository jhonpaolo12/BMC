import 'package:flutter/material.dart';

import '../models/order_summary.dart';
import '../services/order_history_store.dart';
import '../services/order_service.dart';
import '../widgets/status_badge.dart';
import 'payment_success_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;
  final OrderSummary? cached;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    this.cached,
  });

  @override
  State<OrderDetailsScreen> createState() =>
      _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  OrderSummary? _summary;
  Map<String, dynamic>? _order;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _summary = widget.cached;
    _load();
  }

  /// Fetches the single order document the rules allow
  /// (`orders/{orderId}` GET). No collection query is used.
  Future<void> _load() async {
    var summary = _summary ??
        await OrderHistoryStore.find(widget.orderId);

    if (summary != null) {
      _summary = summary;
    }

    try {
      final order = await OrderService.getOrder(widget.orderId);

      if (!mounted) return;

      if (order == null) {
        setState(() {
          _error = 'This order could not be found.';
        });
      } else {
        await OrderHistoryStore.applyOrderSnapshot(
          widget.orderId,
          order,
        );

        final fresh = await OrderHistoryStore.find(widget.orderId);

        if (!mounted) return;

        setState(() {
          _order = order;
          _summary = fresh ??
              summary ??
              OrderSummary.fromOrderDocument(widget.orderId, order);
          _error = null;
        });
      }
    } catch (error) {
      debugPrint('Unable to refresh order: $error');

      if (!mounted) return;

      setState(() {
        _error = 'Could not refresh from the server. '
            'Showing the details saved on this device.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _customerField(String key) {
    final value = _order?[key];

    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return '—';
  }

  String _orderNotes() {
    final notes = _order?['order_notes'];

    if (notes is String && notes.trim().isNotEmpty) {
      return notes.trim();
    }

    return 'No notes provided';
  }

  void _openPaymentStatus() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessScreen(
          orderId: widget.orderId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        actions: [
          IconButton(
            tooltip: 'Refresh order',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: summary == null
          ? _buildMissingState()
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(summary),
                    const SizedBox(height: 16),
                    _buildItems(summary),
                    const SizedBox(height: 16),
                    _buildOrderInfo(summary),
                    const SizedBox(height: 16),
                    _buildCustomerInfo(),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (summary.paymentStatus != 'paid')
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _openPaymentStatus,
                          child: const Text(
                            'VIEW PAYMENT STATUS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMissingState() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 44,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Order not found',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'This order is no longer available.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(OrderSummary summary) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ORDER',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: Color(0xFF8A8A90),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Order #${summary.shortId}',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary.formattedDateTime,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge.payment(summary.paymentStatus),
              StatusBadge.order(summary.orderStatus),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItems(OrderSummary summary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading('PURCHASED ITEMS'),
          const SizedBox(height: 14),
          if (summary.items.isEmpty)
            Text(
              'No item details saved for this order.',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade600,
              ),
            )
          else
            for (final item in summary.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ItemRow(item: item),
              ),
          const Divider(height: 20),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '₱${summary.total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderInfo(OrderSummary summary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading('ORDER INFORMATION'),
          const SizedBox(height: 14),
          _DetailRow(
            label: 'Order ID',
            value: summary.orderId,
            small: true,
          ),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Order date',
            value: summary.formattedDateTime,
          ),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Payment',
            value: summary.paymentMethod,
          ),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Payment status',
            value: StatusBadge.paymentLabel(
              summary.paymentStatus,
            ),
            valueColor: StatusBadge.colorFor(
              StatusBadge.paymentTone(summary.paymentStatus),
            ),
          ),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Order status',
            value: StatusBadge.orderLabel(
              summary.orderStatus,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInfo() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading('CUSTOMER INFORMATION'),
          const SizedBox(height: 14),
          if (_order == null)
            Text(
              _loading
                  ? 'Loading the latest details...'
                  : 'Customer details will appear here once the '
                      'order can be refreshed.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Colors.grey.shade600,
              ),
            )
          else ...[
            _DetailRow(
              label: 'Full name',
              value: _customerField('customer_name'),
            ),
            const SizedBox(height: 10),
            _DetailRow(
              label: 'Contact',
              value: _customerField('phone'),
            ),
            const SizedBox(height: 10),
            _DetailRow(
              label: 'Address',
              value: _customerField('address'),
            ),
            const SizedBox(height: 10),
            _DetailRow(
              label: 'City',
              value: _customerField('city'),
            ),
            const SizedBox(height: 10),
            _DetailRow(
              label: 'Postal code',
              value: _customerField('postal_code'),
            ),
            const SizedBox(height: 10),
            _DetailRow(
              label: 'Order notes',
              value: _orderNotes(),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardHeading extends StatelessWidget {
  final String title;

  const _CardHeading(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: Color(0xFF8A8A90),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = item['product_name']?.toString() ?? 'Item';
    final size = item['size']?.toString() ?? '-';
    final quantity = item['quantity'];
    final subtotal = item['subtotal'];
    final price = item['price'];
    final imagePath = item['image_path']?.toString();

    final amount = subtotal is num
        ? subtotal
        : (price is num
            ? price * (quantity is int ? quantity : 1)
            : 0);

    final unitPrice = price is num ? price : 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 54,
            height: 66,
            color: const Color(0xFFF4F4F6),
            child: imagePath == null
                ? Icon(
                    Icons.image_not_supported_outlined,
                    size: 20,
                    color: Colors.grey.shade400,
                  )
                : Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: (
                      context,
                      error,
                      stackTrace,
                    ) {
                      return Icon(
                        Icons.image_not_supported_outlined,
                        size: 20,
                        color: Colors.grey.shade400,
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Size $size  ·  Qty ${quantity ?? 1}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '₱${unitPrice.toStringAsFixed(2)} each',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '₱${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool small;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: small ? 11 : 12.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
