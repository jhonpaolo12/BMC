import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cart_item.dart';
import '../models/order_summary.dart';
import '../services/auth_service.dart';
import '../services/last_order_store.dart';
import '../services/order_history_store.dart';
import '../services/order_service.dart';
import '../services/payment_service.dart';
import 'auth_screen.dart';
import 'payment_success_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final List<CartItem> cartItems;

  const CheckoutScreen({
    super.key,
    required this.cartItems,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _postalController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool isLoading = false;

  String? _lastOrderId;
  String? _lastPaymentUrl;
  String? _lastSessionId;
  double _lastTotal = 0;

  double get total {
    return widget.cartItems.fold(
      0,
      (totalAmount, item) => totalAmount + item.subtotal,
    );
  }

  int get itemCount {
    return widget.cartItems.fold(
      0,
      (totalQuantity, item) => totalQuantity + item.quantity,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _postalController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> proceedToPayment() async {
    if (widget.cartItems.isEmpty) {
      _showMessage('Your cart is empty.');
      return;
    }

    // Reuse the payment link if one was already created for this
    // checkout attempt. This avoids duplicate pending orders.
    if (_lastPaymentUrl != null) {
      await _reopenPayment();
      return;
    }

    FocusScope.of(context).unfocus();

    final form = _formKey.currentState;

    if (form == null || !form.validate()) {
      _showMessage(
        'Please complete the required customer information.',
      );
      return;
    }

    // Orders are owned by the account so they can sync between the
    // website and the app. Nothing about the Xendit flow changes.
    if (!AuthService.isSignedIn) {
      final signedIn = await _ensureSignedIn();

      if (!signedIn) {
        _showMessage(
          'Sign in to place your order. Your order history is '
          'linked to your account.',
        );
        return;
      }
    }

    setState(() {
      isLoading = true;
    });

    try {
      final items = widget.cartItems.map((item) {
        return {
          'product_name': item.name,
          'size': item.size,
          'quantity': item.quantity,
          'price': item.price,
          'subtotal': item.subtotal,
          'image_path': item.imagePath,
        };
      }).toList();

      final orderTotal = total;

      final orderId = await OrderService.createOrder(
        items: items,
        total: orderTotal,
        customerName: _nameController.text.trim(),
        phone: _normalisedPhone(_phoneController.text),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        postalCode: _postalController.text.trim(),
        orderNotes: _notesController.text.trim(),
      );

      debugPrint('Firebase order created: $orderId');

      try {
        await OrderHistoryStore.add(
          OrderSummary(
            orderId: orderId,
            createdAt: DateTime.now(),
            items: items,
            total: orderTotal,
            paymentMethod: 'Xendit',
            paymentStatus: 'pending',
            orderStatus: 'pending',
            customerName: _nameController.text.trim(),
          ),
        );
      } catch (error) {
        debugPrint('Unable to save order history: $error');
      }

      final session = await PaymentService.createPayment(
        orderId: orderId,
        amount: orderTotal,
        items: items,
      );

      await LastOrderStore.save(
        orderId: orderId,
        sessionId: session.sessionId,
      );

      if (!mounted) return;

      setState(() {
        _lastOrderId = orderId;
        _lastPaymentUrl = session.paymentUrl;
        _lastSessionId = session.sessionId;
        _lastTotal = orderTotal;
      });

      final opened = await _openPaymentPage(
        session.paymentUrl,
      );

      if (!opened) {
        throw const PaymentException(
          'Payment was created, but the browser could not be '
          'opened. Tap "Open Payment Again" to retry.',
        );
      }

      if (!mounted) return;

      await _showPaymentDialog();
    } on OrderException catch (error) {
      if (!mounted) return;

      _showMessage(error.message);
    } on FirebaseException catch (error) {
      debugPrint(
        'Firestore error code: ${error.code}',
      );
      debugPrint(
        'Firestore error message: ${error.message}',
      );

      if (!mounted) return;

      _showMessage(
        error.message ?? 'Failed to create order.',
      );
    } on PaymentException catch (error) {
      if (!mounted) return;

      _showMessage(error.message);
    } catch (error) {
      debugPrint('Checkout error: $error');

      if (!mounted) return;

      _showMessage('Checkout failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<bool> _ensureSignedIn() async {
    final signedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AuthScreen(
          message: 'Sign in to place your order. Your orders are '
              'saved to this account, so they appear on both the '
              'website and the app.',
        ),
      ),
    );

    return signedIn == true && AuthService.isSignedIn;
  }

  Future<void> _reopenPayment() async {
    final paymentUrl = _lastPaymentUrl;

    if (paymentUrl == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      final opened = await _openPaymentPage(paymentUrl);

      if (!opened) {
        throw const PaymentException(
          'Unable to open the payment page. '
          'Please try again.',
        );
      }

      if (!mounted) return;

      await _showPaymentDialog();
    } on PaymentException catch (error) {
      if (!mounted) return;

      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<bool> _openPaymentPage(String url) async {
    final uri = Uri.parse(url);

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (opened) return true;
    } catch (error) {
      debugPrint('External browser launch failed: $error');
    }

    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );
    } catch (error) {
      debugPrint('Default browser launch failed: $error');
      return false;
    }
  }

  Future<void> _showPaymentDialog() async {
    final orderId = _lastOrderId;

    if (orderId == null) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Payment Page Opened'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Complete your payment in the browser, then '
                'return to PlainTees.',
              ),
              const SizedBox(height: 16),
              _DialogDetail(
                label: 'Order ID',
                value: orderId,
              ),
              _DialogDetail(
                label: 'Total',
                value:
                    '₱${_lastTotal.toStringAsFixed(2)}',
              ),
              const _DialogDetail(
                label: 'Status',
                value: 'Waiting for payment',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('CLOSE'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PaymentSuccessScreen(
                      orderId: orderId,
                      sessionId: _lastSessionId,
                    ),
                  ),
                );
              },
              child: const Text('CHECK STATUS'),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  String _normalisedPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[\s-]'), '');

    if (digits.startsWith('+63')) {
      return '0${digits.substring(3)}';
    }

    return digits;
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';

    if (name.isEmpty) {
      return 'Please enter your full name.';
    }

    if (name.length < 2) {
      return 'That name looks a little short.';
    }

    return null;
  }

  String? _validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';

    if (trimmed.isEmpty) {
      return 'Please enter your contact number.';
    }

    final normalised = _normalisedPhone(trimmed);

    if (!RegExp(r'^09\d{9}$').hasMatch(normalised)) {
      return 'Use a valid mobile number, e.g. 09171234567.';
    }

    return null;
  }

  String? _validateAddress(String? value) {
    final address = value?.trim() ?? '';

    if (address.isEmpty) {
      return 'Please enter your complete address.';
    }

    if (address.length < 5) {
      return 'Add a little more detail so we can find you.';
    }

    return null;
  }

  String? _validateCity(String? value) {
    final city = value?.trim() ?? '';

    if (city.isEmpty) {
      return 'Please enter your city or municipality.';
    }

    return null;
  }

  String? _validatePostalCode(String? value) {
    final postal = value?.trim() ?? '';

    if (postal.isEmpty) {
      return 'Please enter your postal code.';
    }

    if (!RegExp(r'^\d{4}$').hasMatch(postal)) {
      return 'Postal code should be 4 digits.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
      ),
      body: SafeArea(
        bottom: false,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: widget.cartItems.isEmpty
                    ? _buildEmptyState()
                    : _buildScrollContent(context),
              ),
              _buildBottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 56,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your cart is empty.',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add a plain tee before checking out.',
            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollContent(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior:
          ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            title: 'Customer Information',
            subtitle:
                'Tell us where to send your order. Fields marked * are required.',
          ),
          const SizedBox(height: 18),
          _buildField(
            controller: _nameController,
            label: 'Full Name',
            hint: 'Enter your full name',
            isRequired: true,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            validator: _validateName,
          ),
          _buildField(
            controller: _phoneController,
            label: 'Contact Number',
            hint: '09XXXXXXXXX',
            isRequired: true,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'[0-9+\s-]'),
              ),
            ],
            validator: _validatePhone,
          ),
          _buildField(
            controller: _addressController,
            label: 'Complete Address',
            hint: 'House/Unit, Street, Barangay',
            isRequired: true,
            minLines: 2,
            maxLines: 3,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [
              AutofillHints.streetAddressLine1,
            ],
            validator: _validateAddress,
          ),
          _buildField(
            controller: _cityController,
            label: 'City / Municipality',
            hint: 'Enter your city or municipality',
            isRequired: true,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.addressCity],
            validator: _validateCity,
          ),
          _buildField(
            controller: _postalController,
            label: 'Postal Code',
            hint: 'Enter postal code',
            isRequired: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            maxLength: 4,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            autofillHints: const [AutofillHints.postalCode],
            validator: _validatePostalCode,
          ),
          _buildField(
            controller: _notesController,
            label: 'Order Notes',
            hint: 'Add special instructions...',
            isRequired: false,
            optional: true,
            minLines: 3,
            maxLines: 4,
            maxLength: 300,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 10),
          _SectionHeading(
            title: 'Order Summary',
            subtitle:
                '$itemCount item${itemCount == 1 ? '' : 's'} in this order',
          ),
          const SizedBox(height: 12),
          _buildOrderSummary(context),
          const SizedBox(height: 26),
          const _SectionHeading(
            title: 'Payment Method',
          ),
          const SizedBox(height: 12),
          _buildPaymentMethod(),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'You will be redirected to Xendit to complete '
                  'your payment securely.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isRequired,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization =
        TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    List<String>? autofillHints,
    int? minLines,
    int? maxLines = 1,
    int? maxLength,
    bool optional = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        autofillHints: autofillHints,
        minLines: minLines,
        maxLines: maxLines,
        maxLength: maxLength,
        validator: validator,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          hintText: hint,
          counterText: '',
          alignLabelWithHint: (maxLines ?? 1) > 1,
          suffixIcon: optional
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      'Optional',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderSummary(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var index = 0;
              index < widget.cartItems.length;
              index++) ...[
            _SummaryLine(item: widget.cartItems[index]),
            if (index != widget.cartItems.length - 1)
              const SizedBox(height: 12),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const Spacer(),
              Text(
                '₱${total.toStringAsFixed(2)}',
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

  Widget _buildPaymentMethod() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.credit_card_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Xendit',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Cards, e-wallets, and online banking',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'SECURE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final hasPaymentLink = _lastPaymentUrl != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed:
                      isLoading ? null : proceedToPayment,
                  child: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          hasPaymentLink
                              ? 'OPEN PAYMENT AGAIN'
                              : 'PLACE ORDER & PAY',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeading({
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final CartItem item;

  const _SummaryLine({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 52,
            height: 62,
            color: const Color(0xFFF4F4F6),
            child: Image.asset(
              item.imagePath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
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
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Size ${item.size}  ·  Qty ${item.quantity}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '₱${item.subtotal.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DialogDetail extends StatelessWidget {
  final String label;
  final String value;

  const _DialogDetail({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
