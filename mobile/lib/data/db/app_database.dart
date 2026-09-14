import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Products,
  Sales,
  SaleItems,
  StockMovements,
  OutboxEvents,
  SyncStates,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'rukun_pos',
      native: const DriftNativeOptions(
        shareAcrossIsolates: true,
      ),
    );
  }

  // ==================== PRODUCTS ====================

  Stream<List<Product>> watchActiveProducts() {
    return (select(products)..where((p) => p.deleted.equals(false))).watch();
  }

  Future<List<Product>> getActiveProducts() {
    return (select(products)..where((p) => p.deleted.equals(false))).get();
  }

  Future<Product?> getProductById(String id) {
    return (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  Future<void> upsertProduct(ProductsCompanion product) async {
    await into(products).insertOnConflictUpdate(product);
  }

  Future<int> calculateStock(String productId) async {
    final product = await getProductById(productId);
    if (product == null) return 0;

    final movements = await (select(stockMovements)
          ..where((m) => m.productId.equals(productId)))
        .get();

    final deltaSum = movements.fold<int>(0, (sum, m) => sum + m.delta);
    return product.baseStock + deltaSum;
  }

  // ==================== SALES & ATOMIC CHECKOUT ====================

  Stream<List<Sale>> watchSales() {
    return (select(sales)..orderBy([(s) => OrderingTerm.desc(s.occurredAt)])).watch();
  }

  Future<List<Sale>> getSales() {
    return (select(sales)..orderBy([(s) => OrderingTerm.desc(s.occurredAt)])).get();
  }

  Future<int> getNextInvoiceNumber(String series) async {
    final lastSale = await (select(sales)
          ..where((s) => s.invoiceSeries.equals(series))
          ..orderBy([(s) => OrderingTerm.desc(s.invoiceNumber)])
          ..limit(1))
        .getSingleOrNull();

    if (lastSale == null) return 1;
    return lastSale.invoiceNumber + 1;
  }

  /// Atomic transaction:
  /// 1. Insert sale record
  /// 2. Insert each sale item snapshot (name & price)
  /// 3. Insert stock movement (-qty) for each item
  /// 4. Insert outbox event for sync engine
  Future<Sale> recordSaleTransaction({
    required String terminalId,
    required String invoiceSeries,
    required String paymentMethod,
    required List<({String productId, String name, int priceCents, int qty})> items,
    String? hlc,
  }) async {
    const uuid = Uuid();
    final saleId = uuid.v4();
    final now = DateTime.now().toUtc();
    final invoiceNumber = await getNextInvoiceNumber(invoiceSeries);

    final totalCents = items.fold<int>(
      0,
      (sum, item) => sum + (item.priceCents * item.qty),
    );

    final saleCompanion = SalesCompanion.insert(
      id: saleId,
      invoiceSeries: invoiceSeries,
      invoiceNumber: invoiceNumber,
      terminalId: terminalId,
      totalCents: totalCents,
      paymentMethod: paymentMethod,
      occurredAt: now,
      syncedAt: const Value.absent(),
    );

    return transaction(() async {
      // 1. Insert Sale
      await into(sales).insert(saleCompanion);

      // 2. Insert Sale Items and Stock Movements
      final itemsPayload = <Map<String, dynamic>>[];
      for (final item in items) {
        final itemId = uuid.v4();
        await into(saleItems).insert(
          SaleItemsCompanion.insert(
            id: itemId,
            saleId: saleId,
            productId: item.productId,
            name: item.name,
            priceCents: item.priceCents,
            qty: item.qty,
          ),
        );

        final movementId = uuid.v4();
        await into(stockMovements).insert(
          StockMovementsCompanion.insert(
            id: movementId,
            productId: item.productId,
            delta: -item.qty,
            reason: 'sale',
            saleId: Value(saleId),
            hlc: Value(hlc),
            createdAt: now,
            syncedAt: const Value.absent(),
          ),
        );

        itemsPayload.add({
          'id': itemId,
          'product_id': item.productId,
          'name': item.name,
          'price_cents': item.priceCents,
          'qty': item.qty,
        });
      }

      // 3. Outbox Event
      final eventId = uuid.v4();
      final payloadJson = jsonEncode({
        'sale_id': saleId,
        'invoice_series': invoiceSeries,
        'invoice_number': invoiceNumber,
        'terminal_id': terminalId,
        'total_cents': totalCents,
        'payment_method': paymentMethod,
        'occurred_at': now.toIso8601String(),
        'items': itemsPayload,
      });

      await into(outboxEvents).insert(
        OutboxEventsCompanion.insert(
          eventId: eventId,
          entityType: 'sale',
          entityId: saleId,
          op: 'create',
          payload: payloadJson,
          hlc: Value(hlc),
          status: const Value('pending'),
          createdAt: now,
        ),
      );

      return (select(sales)..where((s) => s.id.equals(saleId))).getSingle();
    });
  }

  // ==================== OUTBOX & SYNC ====================

  Future<List<OutboxEvent>> getPendingOutboxEvents({int limit = 50}) {
    return (select(outboxEvents)
          ..where((e) => e.status.equals('pending'))
          ..orderBy([(e) => OrderingTerm.asc(e.createdAt)])
          ..limit(limit))
        .get();
  }

  Stream<int> watchPendingOutboxCount() {
    final count = outboxEvents.eventId.count();
    final query = selectOnly(outboxEvents)
      ..addColumns([count])
      ..where(outboxEvents.status.equals('pending'));

    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  Future<void> markEventDone(String eventId) async {
    await (update(outboxEvents)..where((e) => e.eventId.equals(eventId)))
        .write(const OutboxEventsCompanion(status: Value('done')));
  }

  Future<void> markSaleSynced(String saleId, DateTime syncedAt) async {
    await (update(sales)..where((s) => s.id.equals(saleId)))
        .write(SalesCompanion(syncedAt: Value(syncedAt)));
  }

  // ==================== SYNC STATE ====================

  Future<String?> getSyncState(String key) async {
    final state = await (select(syncStates)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return state?.value;
  }

  Future<void> setSyncState(String key, String value) async {
    await into(syncStates).insertOnConflictUpdate(
      SyncStatesCompanion.insert(key: key, value: value),
    );
  }
}
