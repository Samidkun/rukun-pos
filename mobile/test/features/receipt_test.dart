import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukun_mobile/core/theme/app_theme.dart';
import 'package:rukun_mobile/data/db/app_database.dart';
import 'package:rukun_mobile/features/cashier/domain/cart_notifier.dart';
import 'package:rukun_mobile/features/history/presentation/history_screen.dart';
import 'package:rukun_mobile/features/history/presentation/receipt_preview_screen.dart';

void main() {
  group('Receipt Formatting Unit Tests', () {
    final testSale = Sale(
      id: 'sale-001',
      invoiceSeries: 'T01',
      invoiceNumber: 42,
      terminalId: 'T01',
      totalCents: 52000,
      paymentMethod: 'cash',
      occurredAt: DateTime(2026, 9, 14, 16, 30),
      syncedAt: null,
    );

    final testItems = [
      const SaleItem(
        id: 'item-01',
        saleId: 'sale-001',
        productId: 'p1',
        name: 'Kopi Susu Aren',
        priceCents: 18000,
        qty: 2,
      ),
      const SaleItem(
        id: 'item-02',
        saleId: 'sale-001',
        productId: 'p2',
        name: 'Roti Bakar',
        priceCents: 16000,
        qty: 1,
      ),
    ];

    test('generateReceiptText 58mm contains header, items, total, and offline status', () {
      final receipt58 = generateReceiptText(
        sale: testSale,
        items: testItems,
        is80mm: false,
      );

      expect(receipt58.contains('RUKUN POS'), isTrue);
      expect(receipt58.contains('Invoice:'), isTrue);
      expect(receipt58.contains('T01-000042'), isTrue);
      expect(receipt58.contains('Kopi Susu Aren'), isTrue);
      expect(receipt58.contains('Roti Bakar'), isTrue);
      expect(receipt58.contains('PENDING (OFFLINE)'), isTrue);
      expect(receipt58.contains('TOTAL'), isTrue);
      expect(receipt58.contains('Rp 52.000'), isTrue);
    });

    test('generateReceiptText 80mm produces wider formatted receipt', () {
      final receipt80 = generateReceiptText(
        sale: testSale,
        items: testItems,
        is80mm: true,
      );

      expect(receipt80.contains('RUKUN POS'), isTrue);
      expect(receipt80.contains('T01-000042'), isTrue);
      // 80mm separator length is 48 characters
      expect(receipt80.contains('=' * 48), isTrue);
    });
  });

  group('HistoryScreen and ReceiptPreviewScreen Widget Tests', () {
    testWidgets('HistoryScreen displays transactions with invoice and status', (tester) async {
      final inMemoryDb = AppDatabase(NativeDatabase.memory());

      // Seed a sale with items
      await inMemoryDb.recordSaleTransaction(
        terminalId: 'T01',
        invoiceSeries: 'T01',
        paymentMethod: 'cash',
        items: [
          (productId: 'prod-1', name: 'Kopi Aren', priceCents: 18000, qty: 1),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(inMemoryDb),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const HistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify list contains invoice T01-000001 and status Tertunda
      expect(find.text('T01-000001'), findsOneWidget);
      expect(find.text('Tertunda'), findsOneWidget);
      expect(find.text('Rp 18.000'), findsOneWidget);

      await inMemoryDb.close();
    });

    testWidgets('ReceiptPreviewScreen renders receipt text and copy button', (tester) async {
      final inMemoryDb = AppDatabase(NativeDatabase.memory());

      final testSale = Sale(
        id: 'sale-002',
        invoiceSeries: 'T01',
        invoiceNumber: 1,
        terminalId: 'T01',
        totalCents: 18000,
        paymentMethod: 'cash',
        occurredAt: DateTime(2026, 9, 14, 16, 30),
        syncedAt: null,
      );

      const testItems = [
        SaleItem(
          id: 'item-1',
          saleId: 'sale-002',
          productId: 'prod-1',
          name: 'Kopi Aren',
          priceCents: 18000,
          qty: 1,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(inMemoryDb),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: ReceiptPreviewScreen(
              sale: testSale,
              initialItems: testItems,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Struk #T01-000001'), findsOneWidget);
      expect(find.text('Salin Teks Struk'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);

      await inMemoryDb.close();
    });
  });
}
