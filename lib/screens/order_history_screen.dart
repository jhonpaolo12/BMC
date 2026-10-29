import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/order_summary.dart';
import '../services/auth_service.dart';
import '../services/order_history_store.dart';
import '../services/order_service.dart';
import '../widgets/status_badge.dart';
import 'auth_screen.dart';
import 'order_details_screen.dart';

/// Order history for the signed-in account.
///
/// Firestore is the source of truth: the list is queried by `user_id`,
/// so the same account shows the same orders on Chrome and on Android.
/// The local cache is used only when the server cannot be reached.
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() =>
      _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<OrderSummary> _orders = const [];
  bool _loaded = false;
  bool _refreshing = false;
  bool _offline = false;
  bool _signedOut = false;

  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _load();

    if (AuthService.isAvailable) {
      _authSubscription = AuthService.authStateChanges().listen((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Paints the cached list immediately, then replaces it with the
  /// account's server list when Firestore answers.
  Future<void> _load() async {
    final cached = await OrderHistoryStore.readAll();

    if (!mounted) return;

    setState(() {
      _orders = _sorted(cached);
      _loaded = true;
    });

    if (!AuthService.isAvailable) return;

    final signedIn = AuthService.isSignedIn;

    if (!signedIn) {
      if (!mounted) return;

      setState(() {
        _signedOut = true;
        _offline = false;
      });
      return;
    }

    if (mounted && _signedOut) {
      setState(() {
        _signedOut = false;
      });
    }

    await _pullFromServer();
  }

  Future<void> _pullFromServer() async {
    try {
      final remote = await OrderService.fetchMyOrders();
      final saved = await OrderHistoryStore.cacheRemote(remote);

      if (!mounted) return;

      setState(() {
        _orders = _sorted(saved);
        _offline = false;
      });
    } catch (error) {
      debugPrint('Unable to load synced orders: $error');

      if (!mounted) return;

      setState(() {
        _offline = true;
      });
    }
  }

  /// Re-queries the account's orders, which also picks up Xendit status
  /// changes written by the relay/webhook on the server.
  Future<void> _refreshStatuses() async {
    if (_refreshing) return;

    if (AuthService.isAvailable && !AuthService.isSignedIn) {
      await _signIn();
      return;
    }

    setState(() {
      _refreshing = true;
    });

    try {
      if (AuthService.isAvailable) {
        await _pullFromServer();
      } else {
        // No Firebase (offline-only build/test): fall back to per-order reads.
        for (final order in List<OrderSummary>.from(_orders)) {
          try {
            final document = await OrderService.getOrder(order.orderId);

            if (document != null) {
              await OrderHistoryStore.applyOrderSnapshot(
                order.orderId,
                document,
              );
            }
          } catch (error) {
            debugPrint(
              'Unable to refresh order ${order.orderId}: $error',
            );
          }
        }

        final orders = await OrderHistoryStore.readAll();

        if (!mounted) return;

        setState(() {
          _orders = _sorted(orders);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _signIn() async {
    final signedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AuthScreen(
          message: 'Sign in to see the orders linked to your '
              'PlainTees account on every device.',
        ),
      ),
    );

    if (signedIn == true && mounted) {
      await _load();
    }
  }

  Future<void> _openOrder(OrderSummary order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(
          orderId: order.orderId,
          cached: order,
        ),
      ),
    );

    if (mounted) {
      await _load();
    }
  }

  void _goShopping() {
    Navigator.of(context).popUntil(
      (route) => route.isFirst,
    );
  }

  List<OrderSummary> _sorted(List<OrderSummary> orders) {
    final sorted = List<OrderSummary>.from(orders);

    sorted.sort(
      (first, second) => second.createdAt.compareTo(first.createdAt),
    );

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _refreshing ? null : _refreshStatuses,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _signedOut
              ? _buildSignInState()
              : RefreshIndicator(
                  onRefresh: _refreshStatuses,
                  child: ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      28,
                    ),
                    children: [
                      if (_offline) _buildOfflineNote(),
                      if (_orders.isEmpty)
                        _buildEmptyState()
                      else
                        for (var index = 0;
                            index < _orders.length;
                            index++) ...[
                          if (index > 0) const SizedBox(height: 14),
                          _OrderCard(
                            order: _orders[index],
                            onTap: () => _openOrder(_orders[index]),
                          ),
                        ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildOfflineNote() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 14,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Showing orders saved on this device. Pull down to '
              'sync with your account.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0xFFF4F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_outline_rounded,
                size: 42,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Sign in to see your orders',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your order history is saved to your PlainTees account, '
              'so the same orders appear on the website and in the app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton(
                onPressed: _signIn,
                child: const Text('SIGN IN'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _goShopping,
              child: const Text('CONTINUE SHOPPING'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 48,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFF4F4F6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'No orders yet',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your PlainTees orders will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _goShopping,
              child: const Text('SHOP NOW'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderSummary order;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final previewItems = order.items.take(2).toList();
    final remaining = order.items.length - previewItems.length;

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Order #${order.shortId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge.payment(order.paymentStatus),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                order.formattedDate,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              if (order.customerName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 13,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        order.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              for (final item in previewItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ItemPreview(item: item),
                ),
              if (remaining > 0)
                Text(
                  '+ $remaining more item${remaining == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '₱${order.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.credit_card_rounded,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.paymentMethod,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge.order(order.orderStatus),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: onTap,
                  child: const Text(
                    'VIEW DETAILS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
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
}

class _ItemPreview extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ItemPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = item['product_name']?.toString() ?? 'Item';
    final size = item['size']?.toString() ?? '-';
    final quantity = item['quantity'];
    final subtotal = item['subtotal'];
    final price = item['price'];

    final amount = subtotal is num
        ? subtotal
        : (price is num
            ? price * (quantity is int ? quantity : 1)
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
                'Size $size × ${quantity ?? 1}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '₱${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
