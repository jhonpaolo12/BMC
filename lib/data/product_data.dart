import '../models/product.dart';

/// Offline fallback catalog.
///
/// The live catalog lives in the Firestore `products` collection. These
/// entries are identical to the seeded documents and are used only when
/// Firestore is unreachable, so the store still opens offline.
class ProductCatalog {
  ProductCatalog._();

  static const List<String> defaultSizes = ['S', 'M', 'L', 'XL'];

  static const List<Product> products = [
    Product(
      id: 'white_tee',
      name: 'Plain White Tee',
      price: 399.0,
      color: 'White',
      image: 'assets/images/white_tee.png.jpg',
      availableSizes: defaultSizes,
      description:
          'A clean and comfortable plain white T-shirt for everyday wear.',
      category: 'Plain T-Shirt',
      sortOrder: 1,
    ),
    Product(
      id: 'black_tee',
      name: 'Plain Black Tee',
      price: 399.0,
      color: 'Black',
      image: 'assets/images/black_tee.png.jpg',
      availableSizes: defaultSizes,
      description:
          'A classic plain black T-shirt that pairs with everything.',
      category: 'Plain T-Shirt',
      sortOrder: 2,
    ),
    Product(
      id: 'beige_tee',
      name: 'Plain Beige Tee',
      price: 399.0,
      color: 'Beige',
      image: 'assets/images/beige_tee.png.jpg',
      availableSizes: defaultSizes,
      description:
          'A soft beige plain T-shirt for a relaxed, neutral look.',
      category: 'Plain T-Shirt',
      sortOrder: 3,
    ),
    Product(
      id: 'blue_tee',
      name: 'Plain Blue Tee',
      price: 399.0,
      color: 'Blue',
      image: 'assets/images/blue_tee.png.jpg',
      availableSizes: defaultSizes,
      description:
          'A casual plain blue T-shirt that adds a calm pop of color.',
      category: 'Plain T-Shirt',
      sortOrder: 4,
    ),
    Product(
      id: 'brown_tee',
      name: 'Plain Brown Tee',
      price: 399.0,
      color: 'Brown',
      image: 'assets/images/brown_tee.png.jpg',
      availableSizes: defaultSizes,
      description:
          'An earthy plain brown T-shirt with a warm, grounded tone.',
      category: 'Plain T-Shirt',
      sortOrder: 5,
    ),
    Product(
      id: 'cream_tee',
      name: 'Plain Cream Tee',
      price: 399.0,
      color: 'Cream',
      image: 'assets/images/cream_tee.png.jpg',
      availableSizes: defaultSizes,
      description:
          'A light cream plain T-shirt for an easy, off-white finish.',
      category: 'Plain T-Shirt',
      sortOrder: 6,
    ),
    Product(
      id: 'gray_tee',
      name: 'Plain Gray Tee',
      price: 399.0,
      color: 'Gray',
      image: 'assets/images/gray_tee.png.jpg',
      availableSizes: defaultSizes,
      description:
          'A versatile plain gray T-shirt that works with any outfit.',
      category: 'Plain T-Shirt',
      sortOrder: 7,
    ),
    Product(
      id: 'green_tee',
      name: 'Plain Green Tee',
      price: 399.0,
      color: 'Green',
      image: 'assets/images/green_tee.png.jpg',
      availableSizes: defaultSizes,
      description:
          'A fresh plain green T-shirt for a simple everyday look.',
      category: 'Plain T-Shirt',
      sortOrder: 8,
    ),
    Product(
      id: 'navy_tee',
      name: 'Plain Navy Tee',
      price: 399.0,
      color: 'Navy',
      image: 'assets/images/navy_tee.png.png',
      availableSizes: defaultSizes,
      description:
          'A deep navy plain T-shirt with a sharp, understated finish.',
      category: 'Plain T-Shirt',
      sortOrder: 9,
    ),
    Product(
      id: 'neon_tee',
      name: 'Plain Neon Tee',
      price: 399.0,
      color: 'Neon',
      image: 'assets/images/neon_tee.png.jpg',
      availableSizes: defaultSizes,
      description:
          'A bright neon plain T-shirt that stands out from the basics.',
      category: 'Plain T-Shirt',
      sortOrder: 10,
    ),
  ];
}
