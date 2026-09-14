import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukun_mobile/core/theme/app_theme.dart';
import 'package:rukun_mobile/data/db/app_database.dart';
import 'package:rukun_mobile/features/cashier/domain/cart_notifier.dart';
import 'package:rukun_mobile/features/cashier/presentation/cashier_screen.dart';

void main() {
  group('CartNotifier Unit Tests', () {
    test('Cart handles add, decrement, and totals correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const p1 = Product(
        id: 'p1',
        name: 'Kopi Susu',
        priceCents: 15000,
        baseStock: 10,
        deleted: false,
        catalogVersion: 1,
      );

      const p2 = Product(
        id: 'p2',
        name: 'Roti Bakar',
        priceCents: 20000,
        baseStock: 5,
        deleted: false,
        catalogVersion: 1,
      );

      // Add p1
      container.read(cartProvider.notifier).addItem(p1);
      expect(container.read(cartProvider).totalQuantity, equals(1));
      expect(container.read(cartProvider).totalCents, equals(15000));

      // Add p1 again (qty 2) and p2 (qty 1)
      container.read(cartProvider.notifier).addItem(p1);
      container.read(cartProvider.notifier).addItem(p2);
      expect(container.read(cartProvider).totalQuantity, equals(3));
      expect(container.read(cartProvider).totalCents, equals(50000)); // (15000*2) + 20000

      // Decrement p1
      container.read(cartProvider.notifier).decrementItem('p1');
      expect(container.read(cartProvider).items['p1']!.qty, equals(1));
      expect(container.read(cartProvider).totalCents, equals(35000));

      // Decrement p1 again (should remove)
      container.read(cartProvider.notifier).decrementItem('p1');
      expect(container.read(cartProvider).items.containsKey('p1'), isFalse);
      expect(container.read(cartProvider).totalQuantity, equals(1));

      // Clear
      container.read(cartProvider.notifier).clear();
      expect(container.read(cartProvider).isEmpty, isTrue);
    });
  });

  group('Cashier Screen Widget Tests', () {
    testWidgets('Renders Rukun POS, terminal badge, and seed button when empty', (tester) async {
      final inMemoryDb = AppDatabase(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(inMemoryDb),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const CashierScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Rukun POS'), findsOneWidget);
      expect(find.text('T01'), findsOneWidget);
      expect(find.text('Katalog produk kosong'), findsOneWidget);
      expect(find.text('Muat 6 Produk Demo'), findsOneWidget);

      // Tap seed demo products
      await tester.tap(find.text('Muat 6 Produk Demo'));
      await tester.pumpAndSettle();

      // Verify products appear
      expect(find.text('Kopi Susu Aren'), findsOneWidget);
      expect(find.text('Americano Dingin'), findsOneWidget);

      // Tap on a product to add to cart
      await tester.tap(find.text('Kopi Susu Aren'));
      await tester.pumpAndSettle();

      // Bottom bar appears with 1 item
      expect(find.text('1 item dalam keranjang'), findsOneWidget);
      expect(find.text('Bayar'), findsOneWidget);

      await inMemoryDb.close();
    });
  });
}
