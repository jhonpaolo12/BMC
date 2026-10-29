import 'package:flutter/material.dart';

enum StatusTone { positive, warning, negative, neutral }

/// Small uppercase pill used for payment and order statuses.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusTone tone;

  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });

  factory StatusBadge.payment(String status) {
    return StatusBadge(
      label: paymentLabel(status),
      tone: paymentTone(status),
    );
  }

  factory StatusBadge.order(String status) {
    return StatusBadge(
      label: orderLabel(status),
      tone: status.toLowerCase() == 'completed'
          ? StatusTone.positive
          : StatusTone.neutral,
    );
  }

  static String paymentLabel(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return 'PAID';
      case 'awaiting_payment':
        return 'AWAITING PAYMENT';
      case 'failed':
        return 'FAILED';
      case 'cancelled':
      case 'canceled':
        return 'CANCELLED';
      case 'pending':
        return 'PENDING';
      default:
        return status.isEmpty ? 'UNKNOWN' : status.toUpperCase();
    }
  }

  static StatusTone paymentTone(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return StatusTone.positive;
      case 'awaiting_payment':
      case 'pending':
        return StatusTone.warning;
      case 'failed':
      case 'cancelled':
      case 'canceled':
        return StatusTone.negative;
      default:
        return StatusTone.neutral;
    }
  }

  static String orderLabel(String status) {
    if (status.isEmpty) return 'UNKNOWN';

    return status.toUpperCase();
  }

  static Color colorFor(StatusTone tone) {
    switch (tone) {
      case StatusTone.positive:
        return const Color(0xFF1B7F4C);
      case StatusTone.warning:
        return const Color(0xFF9A6A00);
      case StatusTone.negative:
        return const Color(0xFFB3261E);
      case StatusTone.neutral:
        return const Color(0xFF4A4A50);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(tone);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}
