import 'dart:convert';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukun_mobile/data/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase & Stock Ledger Tests', () {
    test('Calculates stock correctly from baseStock + stock_movements', () async {
      const productId = 'prod-kopi-01';

      await db.upsertProduct(
        const ProductsCompanion(
          id: Value(productId),
          name: Value('Kopi Susu Gula Aren'),
          priceCents: Value(18000),
          baseStock: Value(20),
        ),
      );

      // Initial stock
      var currentStock = await db.calculateStock(productId);
      expect(currentStock, equals(20));

      // Record a sale of 3 cups
      await db.recordSaleTransaction(
        terminalId: 'T01',
        invoiceSeries: 'T01',
        paymentMethod: 'cash',
        items: [
          (productId: productId, name: 'Kopi Susu Gula Aren', priceCents: 18000, qty: 3),
        ],
      );

      // Stock should now be 20 - 3 = 17
      currentStock = await db.calculateStock(productId);
      expect(currentStock, equals(17));
    });

    test('Atomic transaction creates sale, items, stock movement, and pending outbox event', () async {
      const productId = 'prod-roti-01';

      await db.upsertProduct(
        const ProductsCompanion(
          id: Value(productId),
          name: Value('Roti Bakar Cokelat'),
          priceCents: Value(15000),
          baseStock: Value(10),
        ),
      );

      final sale = await db.recordSaleTransaction(
        terminalId: 'T01',
        invoiceSeries: 'T01',
        paymentMethod: 'cash',
        items: [
          (productId: productId, name: 'Roti Bakar Cokelat', priceCents: 15000, qty: 2),
        ],
      );

      // Verify Sale details
      expect(sale.terminalId, equals('T01'));
      expect(sale.invoiceSeries, equals('T01'));
      expect(sale.invoiceNumber, equals(1));
      expect(sale.totalCents, equals(30000));
      expect(sale.syncedAt, isNull);

      // Verify Outbox Event created
      final pendingEvents = await db.getPendingOutboxEvents();
      expect(pendingEvents.length, equals(1));

      final outboxEvent = pendingEvents.first;
      expect(outboxEvent.entityType, equals('sale'));
      expect(outboxEvent.entityId, equals(sale.id));
      expect(outboxEvent.status, equals('pending'));

      final payload = jsonDecode(outboxEvent.payload) as Map<String, dynamic>;
      expect(payload['sale_id'], equals(sale.id));
      expect(payload['total_cents'], equals(30000));
      expect(payload['items'], isNotEmpty);

      // Next sale should have invoiceNumber 2 (gapless sequence)
      final sale2 = await db.recordSaleTransaction(
        terminalId: 'T01',
        invoiceSeries: 'T01',
        paymentMethod: 'cash',
        items: [
          (productId: productId, name: 'Roti Bakar Cokelat', priceCents: 15000, qty: 1),
        ],
      );
      expect(sale2.invoiceNumber, equals(2));

      // Mark first outbox event done
      await db.markEventDone(outboxEvent.eventId);
      await db.markSaleSynced(sale.id, DateTime.now().toUtc());

      final updatedPending = await db.getPendingOutboxEvents();
      expect(updatedPending.length, equals(1)); // Only sale2 event is pending
      expect(updatedPending.first.entityId, equals(sale2.id));
    });
  });
}
