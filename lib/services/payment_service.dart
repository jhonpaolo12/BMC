import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/payment_config.dart';

class PaymentException implements Exception {
  final String message;

  const PaymentException(this.message);

  @override
  String toString() => message;
}

class PaymentSession {
  final String orderId;
  final String paymentUrl;
  final String sessionId;
  final String referenceId;

  const PaymentSession({
    required this.orderId,
    required this.paymentUrl,
    required this.sessionId,
    required this.referenceId,
  });
}

class PaymentVerification {
  final String orderId;
  final String paymentStatus;
  final String orderStatus;
  final String xenditStatus;

  const PaymentVerification({
    required this.orderId,
    required this.paymentStatus,
    required this.orderStatus,
    required this.xenditStatus,
  });

  bool get isPaid => paymentStatus == 'paid';

  bool get isUnsuccessful {
    return paymentStatus == 'failed' ||
        paymentStatus == 'cancelled' ||
        paymentStatus == 'canceled';
  }
}

class PaymentService {
  PaymentService._();

  static const Duration _requestTimeout = Duration(seconds: 30);

  static Future<PaymentSession> createPayment({
    required String orderId,
    required double amount,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _post(
      'create-xendit-payment',
      {
        'order_id': orderId,
        'amount': amount,
        'items': items,
      },
    );

    final paymentUrl = data['payment_link_url']?.toString();
    final sessionId = data['payment_session_id']?.toString();

    if (paymentUrl == null ||
        paymentUrl.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      throw const PaymentException(
        'Xendit did not return a payment link. Please try again.',
      );
    }

    return PaymentSession(
      orderId: data['order_id']?.toString() ?? orderId,
      paymentUrl: paymentUrl,
      sessionId: sessionId,
      referenceId:
          data['reference_id']?.toString() ?? 'plaintees-$orderId',
    );
  }

  static Future<PaymentVerification> verifyPayment({
    required String orderId,
    String? sessionId,
  }) async {
    final data = await _post(
      'verify-xendit-payment',
      {
        'order_id': orderId,
        if (sessionId != null && sessionId.isNotEmpty)
          'session_id': sessionId,
      },
    );

    return PaymentVerification(
      orderId: data['order_id']?.toString() ?? orderId,
      paymentStatus:
          data['payment_status']?.toString() ?? 'pending',
      orderStatus: data['order_status']?.toString() ?? 'pending',
      xenditStatus:
          data['xendit_status']?.toString() ?? 'UNKNOWN',
    );
  }

  static Future<Map<String, dynamic>> _post(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    final uri = PaymentConfig.functionUri(functionName);

    http.Response response;

    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'apikey': PaymentConfig.supabaseAnonKey,
              'Authorization':
                  'Bearer ${PaymentConfig.supabaseAnonKey}',
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const PaymentException(
        'The payment service timed out. '
        'Please check your connection and try again.',
      );
    } catch (_) {
      throw const PaymentException(
        'Unable to reach the payment service. '
        'Please check your connection and try again.',
      );
    }

    Map<String, dynamic> data = const {};

    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        // Keep the fallback error message below.
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          data['error']?.toString() ??
          data['message']?.toString() ??
          'Payment service error (${response.statusCode}).';

      throw PaymentException(message);
    }

    return data;
  }
}
