class CartItem {
  final String name;
  final double price;
  final String size;
  final int quantity;
  final String imagePath;

  CartItem({
    required this.name,
    required this.price,
    required this.size,
    required this.quantity,
    required this.imagePath,
  });

  double get subtotal {
    return price * quantity;
  }
}