import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plain_tees/models/order_summary.dart';
import 'package:plain_tees/screens/order_history_screen.dart';
import 'package:plain_tees/services/order_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

OrderSummary buildSummary({
  required String orderId,
  String paymentStatus = 'pending',
  DateTime? createdAt,
}) {
  return OrderSummary(
    orderId: orderId,
    createdAt: createdAt ?? DateTime(2026, 10, 29, 14, 30),
    items: const [
      {
        'product_name': 'Plain Black Tee',
        'size': 'M',
        'quantity': 1,
        'price': 399.0,
        'subtotal': 399.0,
        'image_path': 'assets/images/black_tee.png.jpg',
      },
    ],
    total: 399.0,
    paymentMethod: 'Xendit',
    paymentStatus: paymentStatus,
    orderStatus: 'pending',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OrderHistoryStore', () {
    test('keeps multiple orders, newest first, without duplicates',
        () async {
      await OrderHistoryStore.add(buildSummary(orderId: 'order_aaa'));
      await OrderHistoryStore.add(buildSummary(orderId: 'order_bbb'));

      var orders = await OrderHistoryStore.readAll();

      expect(orders.length, 2);
      expect(orders.first.orderId, 'order_bbb');
      expect(orders.last.orderId, 'order_aaa');

      await OrderHistoryStore.add(buildSummary(orderId: 'order_aaa'));

      orders = await OrderHistoryStore.readAll();

      expect(orders.length, 2);
      expect(orders.first.orderId, 'order_aaa');
    });

    test('updates a saved status and ignores unknown orders', () async {
      await OrderHistoryStore.add(buildSummary(orderId: 'order_aaa'));

      await OrderHistoryStore.updateStatus(
        'order_aaa',
        paymentStatus: 'paid',
        orderStatus: 'completed',
      );

      await OrderHistoryStore.updateStatus(
        'order_unknown',
        paymentStatus: 'paid',
      );

      final orders = await OrderHistoryStore.readAll();

      expect(orders.length, 1);
      expect(orders.first.paymentStatus, 'paid');
      expect(orders.first.orderStatus, 'completed');
    });

    test('merges a fetched order document into the saved summary',
        () async {
      await OrderHistoryStore.add(buildSummary(orderId: 'order_aaa'));

      await OrderHistoryStore.applyOrderSnapshot('order_aaa', {
        'items': [
          {
            'product_name': 'Plain White Tee',
            'size': 'L',
            'quantity': 2,
            'price': 399.0,
            'subtotal': 798.0,
          },
        ],
        'total': 798.0,
        'payment_method': 'Xendit',
        'payment_status': 'awaiting_payment',
        'order_status': 'pending',
        'customer_name': 'Maria Santos',
      });

      final order = await OrderHistoryStore.find('order_aaa');

      expect(order, isNotNull);
      expect(order!.total, 798.0);
      expect(order.paymentStatus, 'awaiting_payment');
      expect(order.items.first['product_name'], 'Plain White Tee');
      expect(order.customerName, 'Maria Santos');
    });

    test('keeps the customer name through the local cache', () async {
      await OrderHistoryStore.add(
        buildSummary(orderId: 'order_ccc').copyWith(
          customerName: 'Juan Dela Cruz',
        ),
      );

      final orders = await OrderHistoryStore.readAll();

      expect(orders.single.customerName, 'Juan Dela Cruz');
    });

    test('replaces the mirror with the account list from Firestore',
        () async {
      await OrderHistoryStore.add(buildSummary(orderId: 'device_only'));

      await OrderHistoryStore.cacheRemote([
        OrderSummary.fromOrderDocument(
          'server_order',
          {
            'customer_name': 'Maria Santos',
            'items': const [
              {
                'product_name': 'Plain White Tee',
                'size': 'M',
                'quantity': 1,
                'price': 399.0,
                'subtotal': 399.0,
              },
            ],
            'total': 399.0,
            'payment_method': 'Xendit',
            'payment_status': 'paid',
            'order_status': 'completed',
            'created_at': DateTime(2026, 10, 29, 9, 15),
          },
        ),
      ]);

      final orders = await OrderHistoryStore.readAll();

      expect(orders.length, 1);
      expect(orders.single.orderId, 'server_order');
      expect(orders.single.paymentStatus, 'paid');
      expect(orders.single.customerName, 'Maria Santos');
    });
  });

  group('OrderHistoryScreen', () {
    testWidgets('shows the empty state with a shop button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OrderHistoryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('No orders yet'), findsOneWidget);
      expect(
        find.text('Your PlainTees orders will appear here.'),
        findsOneWidget,
      );
      expect(find.text('SHOP NOW'), findsOneWidget);
    });

    testWidgets('renders locally saved orders', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        OrderHistoryStore.preferencesKey: jsonEncode([
          {
            'order_id': 'ABC12345XYZ',
            'created_at': '2026-10-29T10:30:00.000',
            'items': [
              {
                'product_name': 'Plain Black Tee',
                'size': 'M',
                'quantity': 1,
                'price': 399.0,
                'subtotal': 399.0,
              }
            ],
            'total': 399.0,
            'payment_method': 'Xendit',
            'payment_status': 'paid',
            'order_status': 'pending',
          }
        ]),
      });

      await tester.pumpWidget(
        const MaterialApp(home: OrderHistoryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Order #ABC12345'), findsOneWidget);
      expect(find.text('Plain Black Tee'), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('VIEW DETAILS'), findsOneWidget);
    });
  });
}
