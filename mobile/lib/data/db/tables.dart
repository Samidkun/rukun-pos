import 'package:drift/drift.dart';

// --- Tables definition ---

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text().nullable()();
  IntColumn get priceCents => integer()();
  IntColumn get baseStock => integer().withDefault(const Constant(0))();
  TextColumn get updatedHlc => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get catalogVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceSeries => text()();
  IntColumn get invoiceNumber => integer()();
  TextColumn get terminalId => text()();
  IntColumn get totalCents => integer()();
  TextColumn get paymentMethod => text()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text()();
  TextColumn get name => text()();
  IntColumn get priceCents => integer()();
  IntColumn get qty => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  IntColumn get delta => integer()(); // -2 sale, +5 restock
  TextColumn get reason => text()();  // sale, return, purchase, adjust, wastage
  TextColumn get saleId => text().nullable()();
  TextColumn get hlc => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class OutboxEvents extends Table {
  TextColumn get eventId => text()(); // Idempotency key
  TextColumn get entityType => text()(); // sale, product, stock
  TextColumn get entityId => text()();
  TextColumn get op => text()(); // create, update, delete
  TextColumn get payload => text()(); // JSON payload
  TextColumn get hlc => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, inflight, done, rejected
  IntColumn get attempt => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {eventId};
}

class SyncStates extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
