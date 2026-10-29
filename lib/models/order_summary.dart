import 'package:cloud_firestore/cloud_firestore.dart';

/// A summary of one PlainTees order.
///
/// Orders are owned by a Firebase Auth account (`user_id`), so the same
/// account signed in on Chrome and on Android reads the same documents
/// from Firestore. The local SharedPreferences copy is only an offline
/// mirror of that server list.
class OrderSummary {
  final String orderId;
  final DateTime createdAt;
  final List<Map<String, dynamic>> items;
  final double total;
  final String paymentMethod;
  final String paymentStatus;
  final String orderStatus;
  final String customerName;

  const OrderSummary({
    required this.orderId,
    required this.createdAt,
    required this.items,
    required this.total,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.orderStatus,
    this.customerName = '',
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    return OrderSummary(
      orderId: json['order_id']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
              DateTime.now(),
      items: _itemsFrom(json['items']),
      total: _doubleFrom(json['total']),
      paymentMethod: json['payment_method']?.toString() ?? 'Xendit',
      paymentStatus: json['payment_status']?.toString() ?? 'pending',
      orderStatus: json['order_status']?.toString() ?? 'pending',
      customerName: json['customer_name']?.toString() ?? '',
    );
  }

  factory OrderSummary.fromOrderDocument(
    String orderId,
    Map<String, dynamic> order, {
    DateTime? fallbackDate,
  }) {
    return OrderSummary(
      orderId: orderId,
      createdAt: _dateFrom(order['created_at']) ??
          fallbackDate ??
          DateTime.now(),
      items: _itemsFrom(order['items']),
      total: _doubleFrom(order['total']),
      paymentMethod:
          order['payment_method']?.toString() ?? 'Xendit',
      paymentStatus:
          order['payment_status']?.toString() ?? 'pending',
      orderStatus: order['order_status']?.toString() ?? 'pending',
      customerName: order['customer_name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
      'created_at': createdAt.toIso8601String(),
      'items': items,
      'total': total,
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      'order_status': orderStatus,
      'customer_name': customerName,
    };
  }

  OrderSummary copyWith({
    DateTime? createdAt,
    List<Map<String, dynamic>>? items,
    double? total,
    String? paymentMethod,
    String? paymentStatus,
    String? orderStatus,
    String? customerName,
  }) {
    return OrderSummary(
      orderId: orderId,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
      total: total ?? this.total,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      orderStatus: orderStatus ?? this.orderStatus,
      customerName: customerName ?? this.customerName,
    );
  }

  int get itemCount {
    return items.fold<int>(
      0,
      (accumulated, item) {
        final quantity = item['quantity'];

        return accumulated + (quantity is int ? quantity : 1);
      },
    );
  }

  /// Short, human-friendly form of the document ID (never re-generated).
  String get shortId {
    final upper = orderId.toUpperCase();

    if (upper.length <= 8) return upper;

    return upper.substring(0, 8);
  }

  String get formattedDate {
    return '${_months[createdAt.month - 1]} '
        '${createdAt.day}, ${createdAt.year}';
  }

  String get formattedDateTime {
    final hour24 = createdAt.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = hour24 < 12 ? 'AM' : 'PM';

    return '$formattedDate · $hour12:$minute $period';
  }

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static List<Map<String, dynamic>> _itemsFrom(dynamic raw) {
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static double _doubleFrom(dynamic raw) {
    if (raw is num) return raw.toDouble();

    if (raw is String) return double.tryParse(raw) ?? 0;

    return 0;
  }

  static DateTime? _dateFrom(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate().toLocal();
    }

    if (raw is DateTime) {
      return raw.toLocal();
    }

    if (raw is String) {
      return DateTime.tryParse(raw)?.toLocal();
    }

    return null;
  }
}
