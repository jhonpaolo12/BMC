/// A PlainTees catalog product.
///
/// Catalog data lives in the Firestore `products` collection. The bundled
/// copy in `lib/data/product_data.dart` is only an offline fallback.
class Product {
  final String id;
  final String name;
  final double price;
  final String color;
  final String image;
  final List<String> availableSizes;
  final String description;
  final String category;
  final int sortOrder;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.color,
    required this.image,
    required this.availableSizes,
    required this.description,
    required this.category,
    this.sortOrder = 999,
  });

  factory Product.fromFirestore(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final sizes = <String>[];
    final rawSizes = data['available_sizes'];

    if (rawSizes is List) {
      for (final size in rawSizes) {
        if (size is String && size.trim().isNotEmpty) {
          sizes.add(size.trim());
        }
      }
    }

    final price = data['price'];

    return Product(
      id: data['id']?.toString() ?? documentId,
      name: data['name']?.toString() ?? '',
      price: price is num ? price.toDouble() : 0,
      color: data['color']?.toString() ?? '',
      image: data['image']?.toString() ?? '',
      availableSizes:
          sizes.isEmpty ? const ['S', 'M', 'L', 'XL'] : sizes,
      description: data['description']?.toString() ?? '',
      category: data['category']?.toString() ?? 'Plain T-Shirt',
      sortOrder:
          data['sort_order'] is num
              ? (data['sort_order'] as num).toInt()
              : 999,
    );
  }

  bool get isValid {
    return id.isNotEmpty && name.isNotEmpty && image.isNotEmpty;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'color': color,
      'image': image,
      'available_sizes': availableSizes,
      'description': description,
      'category': category,
      'sort_order': sortOrder,
    };
  }
}
