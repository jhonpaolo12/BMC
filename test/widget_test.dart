import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plain_tees/main.dart';
import 'package:plain_tees/models/cart_item.dart';
import 'package:plain_tees/screens/checkout_screen.dart';

void main() {
  testWidgets('PlainTees app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const PlainTeesApp());

    expect(find.text('PlainTees'), findsOneWidget);
    expect(find.text('Our Collection'), findsOneWidget);
    expect(find.text('Plain Black Tee'), findsOneWidget);
  });

  testWidgets(
    'checkout requires customer information before payment',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CheckoutScreen(
            cartItems: [
              CartItem(
                name: 'Plain Black Tee',
                price: 399,
                size: 'M',
                quantity: 1,
                imagePath: 'assets/images/black_tee.png.jpg',
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Customer Information'), findsOneWidget);
      expect(find.text('Order Summary'), findsOneWidget);
      expect(find.text('Payment Method'), findsOneWidget);

      await tester.tap(find.text('PLACE ORDER & PAY'));
      await tester.pump();

      expect(find.text('Please enter your full name.'), findsOneWidget);
      expect(
        find.text('Please enter your contact number.'),
        findsOneWidget,
      );
    },
  );
}
