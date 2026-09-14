import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukun_mobile/data/db/app_database.dart';
import 'package:rukun_mobile/data/sync/conflict_resolver.dart';

void main() {
  group('HLC (Hybrid Logical Clock) Tests', () {
    test('HLC correctly parses and formats string representation', () {
      const raw = '1766000000123-2-device-t01';
      final hlc = Hlc.parse(raw);

      expect(hlc.physicalMs, equals(1766000000123));
      expect(hlc.logical, equals(2));
      expect(hlc.deviceId, equals('device-t01'));
      expect(hlc.toString(), equals(raw));
    });

    test('HLC comparison orders by physical timestamp first', () {
      final hlc1 = Hlc.parse('1000-0-d1');
      final hlc2 = Hlc.parse('2000-0-d1');

      expect(hlc1.compareTo(hlc2), lessThan(0));
      expect(hlc2.compareTo(hlc1), greaterThan(0));
    });

    test('HLC comparison orders by logical counter on physical collision', () {
      final hlc1 = Hlc.parse('1000-1-d1');
      final hlc2 = Hlc.parse('1000-2-d1');

      expect(hlc1.compareTo(hlc2), lessThan(0));
      expect(hlc2.compareTo(hlc1), greaterThan(0));
    });

    test('HLC comparison breaks ties deterministically via deviceId', () {
      final hlcA = Hlc.parse('1000-0-device-a');
      final hlcB = Hlc.parse('1000-0-device-b');

      expect(hlcA.compareTo(hlcB), lessThan(0));
      expect(hlcB.compareTo(hlcA), greaterThan(0));
    });
  });

  group('Product Conflict Resolver LWW Tests', () {
    test('Incoming HLC wins if strictly greater than current HLC', () {
      const older = '1766000000100-0-t1';
      const newer = '1766000000200-0-t2';

      expect(ProductConflictResolver.incomingWins(incomingHlc: newer, currentHlc: older), isTrue);
      expect(ProductConflictResolver.incomingWins(incomingHlc: older, currentHlc: newer), isFalse);
    });

    test('Incoming HLC wins when current HLC is null or empty', () {
      expect(ProductConflictResolver.incomingWins(incomingHlc: '1000-0-t1', currentHlc: null), isTrue);
      expect(ProductConflictResolver.incomingWins(incomingHlc: '1000-0-t1', currentHlc: ''), isTrue);
    });
  });

  group('Stock Ledger Oversold Detection Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('Simultaneous sales on 2 terminals for last unit produces negative stock without data loss', () async {
      const productId = 'prod-c1';

      // 1. Initial product with only 1 item in stock
      await db.upsertProduct(
        const ProductsCompanion(
          id: Value(productId),
          name: Value('Barang Terakhir'),
          priceCents: Value(50000),
          baseStock: Value(1),
        ),
      );

      expect(await db.calculateStock(productId), equals(1));

      // 2. Terminal 1 sells 1 unit while offline
      await db.recordSaleTransaction(
        terminalId: 'T01',
        invoiceSeries: 'T01',
        paymentMethod: 'cash',
        items: [
          (productId: productId, name: 'Barang Terakhir', priceCents: 50000, qty: 1),
        ],
      );

      // Stock is now 1 - 1 = 0
      expect(await db.calculateStock(productId), equals(0));

      // 3. Terminal 2 also sold 1 unit while offline (synced in via remote stock movement)
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              id: 'mv-remote-t02',
              productId: productId,
              delta: -1,
              reason: 'remote_sale',
              saleId: const Value('sale-t02-uuid'),
              createdAt: DateTime.now().toUtc(),
              syncedAt: Value(DateTime.now().toUtc()),
            ),
          );

      // Stock is now 0 - 1 = -1 (Oversold!)
      final finalStock = await db.calculateStock(productId);
      expect(finalStock, equals(-1));

      // Both sales exist intact
      final allMovements = await (db.select(db.stockMovements)
            ..where((m) => m.productId.equals(productId)))
          .get();
      expect(allMovements.length, equals(2));
      expect(allMovements.every((m) => m.delta == -1), isTrue);
    });
  });
}
