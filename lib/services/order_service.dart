import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order_summary.dart';
import 'auth_service.dart';

/// Raised when an order cannot be created for a shopper-actionable reason.
class OrderException implements Exception {
  final String message;

  const OrderException(this.message);

  @override
  String toString() => message;
}

class OrderService {
  OrderService._();

  static CollectionReference<Map<String, dynamic>> get _orders {
    return FirebaseFirestore.instance.collection('orders');
  }

  /// Creates an order owned by the signed-in account.
  ///
  /// `user_id` is the only addition to the previous payload; every field
  /// the Xendit relay and the payment screens rely on is unchanged.
  /// Firestore rules reject a write where `user_id` does not match the
  /// caller's auth uid, so the owner cannot be spoofed.
  static Future<String> createOrder({
    required List<Map<String, dynamic>> items,
    required double total,
    required String customerName,
    required String phone,
    required String address,
    required String city,
    required String postalCode,
    String orderNotes = '',
    String? userId,
  }) async {
    final ownerId = userId ?? AuthService.uid;

    if (ownerId == null || ownerId.isEmpty) {
      throw const OrderException(
        'Please sign in before placing an order.',
      );
    }

    final orderRef = await _orders.add({
      'user_id': ownerId,
      'items': items,
      'total': total,
      'payment_method': 'Xendit',
      'payment_status': 'pending',
      'order_status': 'pending',
      'status': 'PENDING',
      'customer_name': customerName,
      'phone': phone,
      'address': address,
      'city': city,
      'postal_code': postalCode,
      'order_notes': orderNotes,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    return orderRef.id;
  }

  /// Returns the signed-in shopper's orders, newest first.
  ///
  /// The query is restricted to `user_id == uid`, which is exactly what
  /// the Firestore rule checks. Sorting is done here so the query needs
  /// no composite index and stays a pure equality filter.
  static Future<List<OrderSummary>> fetchMyOrders({
    int limit = 50,
    String? userId,
  }) async {
    final ownerId = userId ?? AuthService.uid;

    if (ownerId == null || ownerId.isEmpty) return const [];

    final snapshot = await _orders
        .where(AuthService.collectionField, isEqualTo: ownerId)
        .limit(limit)
        .get();

    final orders = snapshot.docs
        .map(
          (document) => OrderSummary.fromOrderDocument(
            document.id,
            document.data(),
          ),
        )
        .where((order) => order.orderId.isNotEmpty)
        .toList();

    orders.sort(
      (first, second) => second.createdAt.compareTo(first.createdAt),
    );

    return orders;
  }

  static Future<Map<String, dynamic>?> getOrder(String orderId) async {
    final snapshot = await _orders.doc(orderId).get();

    if (!snapshot.exists) {
      return null;
    }

    return snapshot.data();
  }

  static double totalOf(Map<String, dynamic>? order) {
    final total = order?['total'];

    if (total is num) {
      return total.toDouble();
    }

    return 0;
  }

  static int itemCountOf(Map<String, dynamic>? order) {
    final items = order?['items'];

    if (items is List) {
      return items.length;
    }

    return 0;
  }

  static String customerNameOf(Map<String, dynamic>? order) {
    final name = order?['customer_name'];

    if (name is String) {
      return name;
    }

    return '';
  }
}
