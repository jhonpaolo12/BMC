import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'data/product_data.dart';
import 'models/product.dart';
import 'screens/auth_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/order_history_screen.dart';
import 'screens/payment_success_screen.dart';
import 'screens/product_details_screen.dart';
import 'services/auth_service.dart';
import 'services/last_order_store.dart';
import 'services/order_history_store.dart';
import 'services/product_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await AuthService.preparePersistence();

  runApp(const PlainTeesApp());
}

class PlainTeesApp extends StatefulWidget {
  const PlainTeesApp({super.key});

  @override
  State<PlainTeesApp> createState() => _PlainTeesAppState();
}

class _PlainTeesAppState extends State<PlainTeesApp> {
  final AppLinks _appLinks = AppLinks();

  final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  StreamSubscription<Uri>? _linkSubscription;

  String? _lastHandledLink;
  DateTime? _lastHandledAt;

  @override
  void initState() {
    super.initState();
    _setupDeepLinks();
  }

  Future<void> _setupDeepLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();

      if (initialUri != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleDeepLink(initialUri);
        });
      }
    } catch (error) {
      debugPrint('Initial deep link error: $error');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (error) {
        debugPrint('Deep link stream error: $error');
      },
    );
  }

  Future<void> _handleDeepLink(Uri uri) async {
    debugPrint('Received deep link: $uri');

    if (uri.scheme != 'plaintees' ||
        uri.host != 'payment-return') {
      return;
    }

    // Ignore duplicate deliveries of the same link from the initial
    // link and the stream.
    final linkKey = uri.toString();
    final now = DateTime.now();

    if (_lastHandledLink == linkKey &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) <
            const Duration(seconds: 3)) {
      return;
    }

    final navigator = _navigatorKey.currentState;

    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleDeepLink(uri);
      });
      return;
    }

    _lastHandledLink = linkKey;
    _lastHandledAt = now;

    String? orderId =
        uri.queryParameters['order_id'] ??
        uri.queryParameters['orderId'];

    final referenceId = uri.queryParameters['reference_id'];

    if ((orderId == null || orderId.isEmpty) &&
        referenceId != null &&
        referenceId.isNotEmpty) {
      orderId = referenceId.replaceFirst('plaintees-', '');
    }

    orderId ??= await LastOrderStore.readOrderId();

    final sessionId =
        uri.queryParameters['session_id'] ??
        await LastOrderStore.readSessionId();

    if (!mounted) return;

    if (orderId == null || orderId.isEmpty) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Returned to PlainTees. No pending order was found.',
          ),
        ),
      );
      return;
    }

    final resolvedOrderId = orderId;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        settings: const RouteSettings(
          name: '/payment-status',
        ),
        builder: (_) => PaymentSuccessScreen(
          orderId: resolvedOrderId,
          sessionId: sessionId,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.black,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarThemeData(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: BorderSide(
            color: Colors.grey.shade300,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.black,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF6F6F7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          fontSize: 13.5,
          color: Colors.grey.shade500,
        ),
        labelStyle: TextStyle(
          fontSize: 13.5,
          color: Colors.grey.shade600,
        ),
        floatingLabelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.black,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFB3261E),
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFB3261E),
            width: 1.4,
          ),
        ),
        errorStyle: const TextStyle(
          fontSize: 11.5,
          color: Color(0xFFB3261E),
        ),
        errorMaxLines: 2,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Colors.black,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black,
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        actionTextColor: Colors.white,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PlainTees',
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      theme: _buildTheme(),
      home: const HomeScreen(),
    );
  }
}

// ==========================================================
// HOME SCREEN
// ==========================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Firestore catalog, with the bundled catalog as an offline fallback.
  List<Product> _products = ProductCatalog.products;

  StreamSubscription<bool>? _authSubscription;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();

    _signedIn = AuthService.isSignedIn;

    if (AuthService.isAvailable) {
      _authSubscription =
          AuthService.signedInChanges().listen((signedIn) {
        if (!mounted) return;

        setState(() {
          _signedIn = signedIn;
        });
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final products = await ProductService.fetchProducts();

    if (!mounted || products.isEmpty) return;

    setState(() {
      _products = products;
    });
  }

  void _openCart() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CartScreen(),
      ),
    );
  }

  Future<void> _openAccount() async {
    if (!_signedIn) {
      final signedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const AuthScreen(),
        ),
      );

      if (signedIn == true && mounted) {
        setState(() {
          _signedIn = true;
        });
      }

      return;
    }

    final shouldSignOut = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SIGNED IN',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Color(0xFF8A8A90),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AuthService.email,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This account keeps your order history in sync '
                  'between the website and the app.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop(true);
                    },
                    child: const Text('SIGN OUT'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldSignOut != true) return;

    await AuthService.signOut();
    await OrderHistoryStore.clear();

    if (!mounted) return;

    setState(() {
      _signedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PlainTees'),
        actions: [
          IconButton(
            tooltip: _signedIn ? 'Account' : 'Sign in',
            icon: Icon(
              _signedIn
                  ? Icons.account_circle_outlined
                  : Icons.person_outline_rounded,
            ),
            onPressed: _openAccount,
          ),
          IconButton(
            tooltip: 'Order history',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OrderHistoryScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'My cart',
            icon: const Icon(Icons.shopping_bag_outlined),
            onPressed: _openCart,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Our Collection',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Premium plain tees. No logos. Just quality.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _HeaderPill(
                        label: '${_products.length} styles',
                      ),
                      const SizedBox(width: 8),
                      const _HeaderPill(label: 'Sizes S – XL'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverGrid(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                childAspectRatio: 0.56,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final product = _products[index];

                  return _ProductCard(
                    product: product,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductDetailsScreen(
                            productId: product.id,
                            name: product.name,
                            price: product.price,
                            color: product.color,
                            imagePath: product.image,
                            description: product.description,
                            availableSizes:
                                product.availableSizes,
                          ),
                        ),
                      );
                    },
                  );
                },
                childCount: _products.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final String label;

  const _HeaderPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Color(0xFF4A4A50),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFFF4F4F6),
                child: Image.asset(
                  product.image,
                  fit: BoxFit.cover,
                  errorBuilder: (
                    context,
                    error,
                    stackTrace,
                  ) {
                    return Icon(
                      Icons.image_not_supported_outlined,
                      size: 32,
                      color: Colors.grey.shade400,
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.color,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '₱${product.price.toStringAsFixed(2)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_outward_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
