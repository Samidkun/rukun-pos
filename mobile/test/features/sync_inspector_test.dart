import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukun_mobile/core/theme/app_theme.dart';
import 'package:rukun_mobile/data/db/app_database.dart';
import 'package:rukun_mobile/features/cashier/domain/cart_notifier.dart';
import 'package:rukun_mobile/features/sync_inspector/presentation/sync_inspector_screen.dart';

void main() {
  group('SyncInspectorScreen Widget Tests', () {
    testWidgets('Renders outbox events, toggle offline switch, and switches tabs', (tester) async {
      final inMemoryDb = AppDatabase(NativeDatabase.memory());

      // Seed a sale (which creates an outbox event)
      await inMemoryDb.recordSaleTransaction(
        terminalId: 'T01',
        invoiceSeries: 'T01',
        paymentMethod: 'cash',
        items: [
          (productId: 'p-insp', name: 'Item Demo Inspector', priceCents: 25000, qty: 1),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(inMemoryDb),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const SyncInspectorScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header and controls
      expect(find.text('Sync Inspector & Live Demo'), findsOneWidget);
      expect(find.text('Simulasi Mode Offline'), findsOneWidget);
      expect(find.text('Force Sync Sekarang'), findsOneWidget);

      // Check outbox event rendered in Tab 1
      expect(find.text('SALE · CREATE'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);

      // Toggle offline switch
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Switch to Tab 2: State & Cursors
      await tester.tap(find.text('State & Cursors'));
      await tester.pumpAndSettle();

      expect(find.text('Kursor Sinkronisasi Terminal'), findsOneWidget);
      expect(find.text('Terminal ID'), findsOneWidget);
      expect(find.text('T01'), findsOneWidget);

      await inMemoryDb.close();
    });
  });
}
