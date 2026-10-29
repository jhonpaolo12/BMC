import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_summary.dart';

/// Offline mirror of the signed-in shopper's Firestore order history.
///
/// The source of truth is the `orders` collection, queried by `user_id`
/// (the Firebase Auth uid), so Chrome and Android show the same list.
/// This cache only exists so the history still opens without a network
/// connection and so the payment screens can merge live statuses.
///
/// The cache is cleared on sign-out, so one account's orders never leak
/// into another account using the same device.
class OrderHistoryStore {
  OrderHistoryStore._();

  static const String preferencesKey = 'plaintees_order_history_v1';

  /// Keeps SharedPreferences small and the history easy to scroll.
  static const int maxEntries = 50;

  static Future<List<OrderSummary>> readAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(preferencesKey);

    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map(
            (entry) =>
                OrderSummary.fromJson(Map<String, dynamic>.from(entry)),
          )
          .where((order) => order.orderId.isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('Unable to read order history: $error');
      return [];
    }
  }

  static Future<void> saveAll(List<OrderSummary> orders) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      orders.map((order) => order.toJson()).toList(),
    );

    await preferences.setString(preferencesKey, encoded);
  }

  /// Replaces the mirror with the server list for the signed-in account.
  static Future<List<OrderSummary>> cacheRemote(
    List<OrderSummary> remote,
  ) async {
    final capped = List<OrderSummary>.from(remote);

    if (capped.length > maxEntries) {
      capped.removeRange(maxEntries, capped.length);
    }

    await saveAll(capped);

    return capped;
  }

  /// Adds a new order at the top, replacing any entry with the same ID.
  static Future<void> add(OrderSummary order) async {
    if (order.orderId.isEmpty) return;

    final orders = await readAll();

    orders.removeWhere((entry) => entry.orderId == order.orderId);
    orders.insert(0, order);

    if (orders.length > maxEntries) {
      orders.removeRange(maxEntries, orders.length);
    }

    await saveAll(orders);
  }

  static Future<OrderSummary?> find(String orderId) async {
    final orders = await readAll();

    for (final order in orders) {
      if (order.orderId == orderId) return order;
    }

    return null;
  }

  /// Applies the latest server status. Does nothing if the order was not
  /// saved on this device.
  static Future<void> updateStatus(
    String orderId, {
    String? paymentStatus,
    String? orderStatus,
  }) async {
    final orders = await readAll();
    final index =
        orders.indexWhere((entry) => entry.orderId == orderId);

    if (index == -1) return;

    orders[index] = orders[index].copyWith(
      paymentStatus: paymentStatus,
      orderStatus: orderStatus,
    );

    await saveAll(orders);
  }

  /// Merges a freshly fetched `orders/{orderId}` document into the cached
  /// summary. Unknown order IDs are ignored so the cache never grows from
  /// data the shopper did not load.
  static Future<void> applyOrderSnapshot(
    String orderId,
    Map<String, dynamic> order,
  ) async {
    final orders = await readAll();
    final index =
        orders.indexWhere((entry) => entry.orderId == orderId);

    if (index == -1) return;

    final existing = orders[index];
    final fresh = OrderSummary.fromOrderDocument(
      orderId,
      order,
      fallbackDate: existing.createdAt,
    );

    orders[index] = OrderSummary(
      orderId: orderId,
      createdAt: fresh.createdAt,
      items: fresh.items.isEmpty ? existing.items : fresh.items,
      total: fresh.total > 0 ? fresh.total : existing.total,
      paymentMethod: fresh.paymentMethod.isEmpty
          ? existing.paymentMethod
          : fresh.paymentMethod,
      paymentStatus: order['payment_status'] == null
          ? existing.paymentStatus
          : fresh.paymentStatus,
      orderStatus: order['order_status'] == null
          ? existing.orderStatus
          : fresh.orderStatus,
      customerName: fresh.customerName.isEmpty
          ? existing.customerName
          : fresh.customerName,
    );

    await saveAll(orders);
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(preferencesKey);
  }
}
