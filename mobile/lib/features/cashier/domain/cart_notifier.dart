import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/app_database.dart';

class CartItem {
  final Product product;
  final int qty;

  const CartItem({
    required this.product,
    required this.qty,
  });

  int get subtotalCents => product.priceCents * qty;

  CartItem copyWith({
    Product? product,
    int? qty,
  }) {
    return CartItem(
      product: product ?? this.product,
      qty: qty ?? this.qty,
    );
  }
}

class CartState {
  final Map<String, CartItem> items;

  const CartState({this.items = const {}});

  int get totalCents =>
      items.values.fold(0, (sum, item) => sum + item.subtotalCents);

  int get totalQuantity =>
      items.values.fold(0, (sum, item) => sum + item.qty);

  bool get isEmpty => items.isEmpty;

  CartState copyWith({Map<String, CartItem>? items}) {
    return CartState(items: items ?? this.items);
  }
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    return const CartState();
  }

  void addItem(Product product) {
    final current = Map<String, CartItem>.from(state.items);
    if (current.containsKey(product.id)) {
      final existing = current[product.id]!;
      current[product.id] = existing.copyWith(qty: existing.qty + 1);
    } else {
      current[product.id] = CartItem(product: product, qty: 1);
    }
    state = state.copyWith(items: current);
  }

  void decrementItem(String productId) {
    final current = Map<String, CartItem>.from(state.items);
    if (!current.containsKey(productId)) return;

    final existing = current[productId]!;
    if (existing.qty <= 1) {
      current.remove(productId);
    } else {
      current[productId] = existing.copyWith(qty: existing.qty - 1);
    }
    state = state.copyWith(items: current);
  }

  void removeItem(String productId) {
    final current = Map<String, CartItem>.from(state.items);
    current.remove(productId);
    state = state.copyWith(items: current);
  }

  void clear() {
    state = const CartState();
  }
}

final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

final activeProductsProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchActiveProducts();
});

final pendingOutboxCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchPendingOutboxCount();
});
