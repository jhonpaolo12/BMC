import 'package:flutter_test/flutter_test.dart';
import 'package:plain_tees/data/product_data.dart';
import 'package:plain_tees/models/product.dart';

void main() {
  group('Product', () {
    test('parses a Firestore product document', () {
      final product = Product.fromFirestore('white_tee', {
        'id': 'white_tee',
        'name': 'Plain White Tee',
        'price': 399,
        'color': 'White',
        'image': 'assets/images/white_tee.png.jpg',
        'available_sizes': ['S', 'M', 'L', 'XL'],
        'description': 'A clean and comfortable plain white T-shirt.',
        'category': 'Plain T-Shirt',
        'sort_order': 1,
      });

      expect(product.id, 'white_tee');
      expect(product.price, 399.0);
      expect(product.availableSizes, ['S', 'M', 'L', 'XL']);
      expect(product.sortOrder, 1);
      expect(product.isValid, isTrue);
    });

    test('falls back to default sizes and stays usable', () {
      final product = Product.fromFirestore('navy_tee', {
        'name': 'Plain Navy Tee',
        'price': 399.0,
        'image': 'assets/images/navy_tee.png.png',
      });

      expect(product.id, 'navy_tee');
      expect(product.availableSizes, ['S', 'M', 'L', 'XL']);
      expect(product.category, 'Plain T-Shirt');
      expect(product.isValid, isTrue);
    });

    test('rejects a document without a name or image', () {
      final product = Product.fromFirestore('broken', {
        'price': 399,
      });

      expect(product.isValid, isFalse);
    });
  });

  group('ProductCatalog fallback', () {
    test('contains the same 10 products as the Firestore catalog', () {
      expect(ProductCatalog.products.length, 10);

      final ids = ProductCatalog.products
          .map((product) => product.id)
          .toSet();

      expect(ids, {
        'white_tee',
        'black_tee',
        'beige_tee',
        'blue_tee',
        'brown_tee',
        'cream_tee',
        'gray_tee',
        'green_tee',
        'navy_tee',
        'neon_tee',
      });

      for (final product in ProductCatalog.products) {
        expect(product.name, isNotEmpty);
        expect(product.price, 399.0);
        expect(product.color, isNotEmpty);
        expect(product.image, startsWith('assets/images/'));
        expect(
          product.availableSizes,
          containsAll(['S', 'M', 'L', 'XL']),
        );
        expect(product.description, isNotEmpty);
        expect(product.category, 'Plain T-Shirt');
      }
    });
  });
}
