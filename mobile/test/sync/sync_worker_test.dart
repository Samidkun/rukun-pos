import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rukun_mobile/data/db/app_database.dart';
import 'package:rukun_mobile/data/sync/sync_worker.dart';

void main() {
  group('SyncWorker Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('Full sync cycle: pushes pending sale and pulls catalog updates', () async {
      // 1. Create a local sale
      final sale = await db.recordSaleTransaction(
        terminalId: 'T01',
        invoiceSeries: 'T01',
        paymentMethod: 'cash',
        items: [
          (productId: 'prod-local', name: 'Es Teh Manis', priceCents: 5000, qty: 2),
        ],
      );

      final pendingBefore = await db.getPendingOutboxEvents();
      expect(pendingBefore.length, equals(1));
      final eventId = pendingBefore.first.eventId;

      // 2. Mock HTTP Client
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/sync/push' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['terminal_id'], equals('T01'));

          return http.Response(
            jsonEncode({
              'accepted': [eventId],
              'rejected': [],
              'server_seq_max': 42,
              'catalog_version': 2,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/api/v1/sync/pull' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'events': [],
              'catalog': [
                {
                  'id': 'prod-pulled-1',
                  'name': 'Kopi Cold Brew',
                  'category': 'Minuman',
                  'price_cents': 25000,
                  'base_stock': 30,
                  'catalog_version': 2,
                }
              ],
              'next_since': 42,
              'current_catalog_version': 2,
              'has_more': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      final worker = SyncWorker(
        db: db,
        client: mockClient,
        baseUrl: 'http://example.test',
        terminalId: 'T01',
        deviceId: 'd-t01',
      );

      // 3. Perform sync
      final result = await worker.syncOnce();
      expect(result.success, isTrue);
      expect(result.pushedEventsCount, equals(1));

      // 4. Verify local state after push
      final pendingAfter = await db.getPendingOutboxEvents();
      expect(pendingAfter.isEmpty, isTrue);

      final sales = await db.getSales();
      expect(sales.first.id, equals(sale.id));
      expect(sales.first.syncedAt, isNotNull);

      // 5. Verify local state after pull
      final pulledProduct = await db.getProductById('prod-pulled-1');
      expect(pulledProduct, isNotNull);
      expect(pulledProduct!.name, equals('Kopi Cold Brew'));
      expect(pulledProduct.priceCents, equals(25000));

      final lastSeq = await db.getSyncState('last_pulled_seq');
      expect(lastSeq, equals('42'));
    });

    test('Simulate offline aborts sync immediately and preserves outbox', () async {
      await db.recordSaleTransaction(
        terminalId: 'T01',
        invoiceSeries: 'T01',
        paymentMethod: 'cash',
        items: [
          (productId: 'p1', name: 'Item', priceCents: 10000, qty: 1),
        ],
      );

      final mockClient = MockClient((_) async => http.Response('error', 500));
      final worker = SyncWorker(db: db, client: mockClient);

      final result = await worker.syncOnce(simulateOffline: true);
      expect(result.isOffline, isTrue);
      expect(result.success, isFalse);

      final pending = await db.getPendingOutboxEvents();
      expect(pending.length, equals(1));
    });
  });
}
