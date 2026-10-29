import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/product.dart';

/// Reads the public, read-only `products` catalog from Firestore.
class ProductService {
  ProductService._();

  /// Returns the catalog sorted by `sort_order`.
  ///
  /// Returns an empty list when Firestore is unavailable (offline, or no
  /// Firebase app in unit tests) so the caller can fall back to the
  /// bundled catalog.
  static Future<List<Product>> fetchProducts() async {
    try {
      if (Firebase.apps.isEmpty) return [];

      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .get();

      final products = snapshot.docs
          .map(
            (document) => Product.fromFirestore(
              document.id,
              document.data(),
            ),
          )
          .where((product) => product.isValid)
          .toList();

      products.sort((first, second) {
        final byOrder =
            first.sortOrder.compareTo(second.sortOrder);

        if (byOrder != 0) return byOrder;

        return first.name.compareTo(second.name);
      });

      return products;
    } catch (error) {
      debugPrint('Unable to load products: $error');
      return [];
    }
  }
}
