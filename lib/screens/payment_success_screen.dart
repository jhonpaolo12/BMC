import 'dart:async';

import 'package:flutter/material.dart';

import '../data/cart_data.dart';
import '../services/last_order_store.dart';
import '../services/order_history_store.dart';
import '../services/order_service.dart';
import '../services/payment_service.dart';

class PaymentSuccessScreen extends StatefulWidget {
  final String orderId;
  final String? sessionId;

  const PaymentSuccessScreen({
    super.key,
    required this.orderId,
    this.sessionId,
  });

  @override
  State<PaymentSuccessScreen> createState() =>
      _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState
    extends State<PaymentSuccessScreen> {
  String? _sessionId;
  String? _paymentStatus;
  String? _orderStatus;
  String? _xenditStatus;
  String? _error;
  Map<String, dynamic>? _order;

  bool _isChecking = false;
  bool _requestInFlight = false;

  bool get _isPaid => _paymentStatus == 'paid';

  bool get _isUnsuccessful {
    return _paymentStatus == 'failed' ||
        _paymentStatus == 'cancelled' ||
        _paymentStatus == 'canceled';
  }

  @override
  void initState() {
    super.initState();
    _isChecking = true;
    _initialize();
  }

  Future<void> _initialize() async {
    _sessionId =
        widget.sessionId ?? await LastOrderStore.readSessionId();

    await _loadOrder();
    await _checkPayment(showSpinner: true);
    await _autoRetryWhilePending();
  }

  Future<void> _loadOrder() async {
    try {
      final order = await OrderService.getOrder(widget.orderId);

      if (!mounted) return;

      setState(() {
        _order = order;
      });

      if (order != null) {
        try {
          await OrderHistoryStore.applyOrderSnapshot(
            widget.orderId,
            order,
          );
        } catch (error) {
          debugPrint('Unable to update order history: $error');
        }
      }
    } catch (error) {
      debugPrint('Unable to read order: $error');
    }
  }

  Future<void> _checkPayment({
    bool showSpinner = true,
  }) async {
    if (_requestInFlight) return;

    _requestInFlight = true;

    if (showSpinner && mounted) {
      setState(() {
        _isChecking = true;
        _error = null;
      });
    }

    try {
      final result = await PaymentService.verifyPayment(
        orderId: widget.orderId,
        sessionId: _sessionId,
      );

      if (!mounted) return;

      setState(() {
        _paymentStatus = result.paymentStatus;
        _orderStatus = result.orderStatus;
        _xenditStatus = result.xenditStatus;
        _error = null;
      });

      try {
        await OrderHistoryStore.updateStatus(
          widget.orderId,
          paymentStatus: result.paymentStatus,
          orderStatus: result.orderStatus,
        );
      } catch (error) {
        debugPrint('Unable to update order history: $error');
      }

      if (result.isPaid) {
        cartItems.clear();
        await LastOrderStore.clear();
      }

      await _loadOrder();
    } catch (error) {
      debugPrint('Payment verification failed: $error');

      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    } finally {
      _requestInFlight = false;

      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _autoRetryWhilePending() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted || _isPaid || _isUnsuccessful) return;

      await Future<void>.delayed(
        const Duration(seconds: 2),
      );

      if (!mounted || _isPaid || _isUnsuccessful) return;

      await _checkPayment(showSpinner: false);
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil(
      (route) => route.isFirst,
    );
  }

  String get _title {
    if (_isChecking && _paymentStatus == null) {
      return 'Checking Payment';
    }

    if (_isPaid) {
      return 'Payment Successful';
    }

    if (_isUnsuccessful) {
      return 'Payment Not Completed';
    }

    return 'Payment Pending';
  }

  String get _message {
    if (_isChecking && _paymentStatus == null) {
      return 'Please wait while we confirm your payment with Xendit.';
    }

    if (_isPaid) {
      return 'Thank you for your order from PlainTees. '
          'Your payment has been confirmed.';
    }

    if (_isUnsuccessful) {
      return 'This payment was not completed. '
          'Your cart is still saved, so you can try again.';
    }

    return 'We have not received confirmation from Xendit yet. '
        'If you just paid, wait a few seconds and check again.';
  }

  IconData get _icon {
    if (_isChecking && _paymentStatus == null) {
      return Icons.hourglass_top_rounded;
    }

    if (_isPaid) {
      return Icons.check_rounded;
    }

    if (_isUnsuccessful) {
      return Icons.priority_high_rounded;
    }

    return Icons.schedule_rounded;
  }

  Color get _accentColor {
    if (_isPaid) {
      return const Color(0xFF1B7F4C);
    }

    if (_isUnsuccessful) {
      return const Color(0xFFB3261E);
    }

    return const Color(0xFF9A6A00);
  }

  String get _paymentStatusLabel {
    switch (_paymentStatus) {
      case 'paid':
        return 'Paid';
      case 'failed':
        return 'Failed';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      case 'awaiting_payment':
        return 'Awaiting payment';
      case 'pending':
        return 'Pending';
      default:
        return 'Checking';
    }
  }

  List<Map<String, dynamic>> get _items {
    final raw = _order?['items'];

    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _money(num value) {
    return '₱${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final orderTotal = OrderService.totalOf(_order);
    final itemCount = OrderService.itemCountOf(_order);
    final customerName = OrderService.customerNameOf(_order);
    final items = _items;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _goHome();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Order Status'),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _goHome,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusCard(),
              const SizedBox(height: 18),
              _buildReceipt(
                orderTotal: orderTotal,
                itemCount: itemCount,
                customerName: customerName,
                items: items,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  'Status check failed: $_error',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Color(0xFFB3261E),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 22),
              if (!_isPaid) ...[
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _requestInFlight
                        ? null
                        : () {
                            _checkPayment();
                          },
                    child: _isChecking
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'CHECK AGAIN',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                height: 52,
                child: _isPaid
                    ? FilledButton(
                        onPressed: _goHome,
                        child: const Text(
                          'BACK TO HOME',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: _goHome,
                        child: const Text(
                          'BACK TO HOME',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
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

  Widget _buildStatusCard() {
    final isBusy = _isChecking && _paymentStatus == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _accentColor.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: isBusy
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: _accentColor,
                    ),
                  )
                : Icon(
                    _icon,
                    size: 38,
                    color: _accentColor,
                  ),
          ),
          const SizedBox(height: 18),
          Text(
            _title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _paymentStatusLabel.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: _accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceipt({
    required double orderTotal,
    required int itemCount,
    required String customerName,
    required List<Map<String, dynamic>> items,
  }) {
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
          Row(
            children: [
              const Text(
                'ORDER SUMMARY',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: Color(0xFF8A8A90),
                ),
              ),
              const Spacer(),
              Text(
                'Xendit',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final item in items.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ItemLine(item: item),
              ),
            if (items.length > 4)
              Text(
                '+ ${items.length - 4} more item'
                '${items.length - 4 == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
          ] else
            const SizedBox(height: 14),
          _StatusRow(
            label: 'Total',
            value: orderTotal > 0 ? _money(orderTotal) : '—',
            emphasise: true,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          _StatusRow(
            label: 'Order ID',
            value: widget.orderId,
            small: true,
          ),
          const SizedBox(height: 10),
          _StatusRow(
            label: 'Items',
            value: itemCount > 0
                ? '$itemCount item${itemCount == 1 ? '' : 's'}'
                : '—',
          ),
          const SizedBox(height: 10),
          _StatusRow(
            label: 'Payment',
            value: _paymentStatusLabel,
            valueColor: _accentColor,
            emphasise: true,
          ),
          if (customerName.isNotEmpty) ...[
            const SizedBox(height: 10),
            _StatusRow(
              label: 'Customer',
              value: customerName,
            ),
          ],
          if (_orderStatus != null) ...[
            const SizedBox(height: 10),
            _StatusRow(
              label: 'Order',
              value: _orderStatus!,
            ),
          ],
          if (_xenditStatus != null) ...[
            const SizedBox(height: 10),
            _StatusRow(
              label: 'Xendit',
              value: _xenditStatus!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ItemLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = item['product_name']?.toString() ?? 'Item';
    final size = item['size']?.toString() ?? '-';
    final quantity = item['quantity'];
    final subtotalRaw = item['subtotal'];
    final priceRaw = item['price'];

    final amount = subtotalRaw is num
        ? subtotalRaw
        : (priceRaw is num
            ? priceRaw * (quantity is int ? quantity : 1)
            : 0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Size $size  ·  Qty ${quantity ?? 1}',
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
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasise;
  final bool small;

  const _StatusRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasise = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: small ? 11.5 : 13,
              fontWeight:
                  emphasise ? FontWeight.w800 : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
