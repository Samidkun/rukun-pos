import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:http/http.dart' as http;
import '../db/app_database.dart';

class SyncResult {
  final bool success;
  final int pushedEventsCount;
  final int pulledEventsCount;
  final String? errorMessage;
  final bool isOffline;

  const SyncResult({
    required this.success,
    this.pushedEventsCount = 0,
    this.pulledEventsCount = 0,
    this.errorMessage,
    this.isOffline = false,
  });

  factory SyncResult.offline([String? reason]) => SyncResult(
        success: false,
        isOffline: true,
        errorMessage: reason ?? 'Perangkat offline',
      );

  factory SyncResult.failure(String message) => SyncResult(
        success: false,
        errorMessage: message,
      );

  factory SyncResult.success({int pushed = 0, int pulled = 0}) => SyncResult(
        success: true,
        pushedEventsCount: pushed,
        pulledEventsCount: pulled,
      );
}

class SyncWorker {
  final AppDatabase db;
  final http.Client client;
  final String baseUrl;
  final String terminalId;
  final String deviceId;

  SyncWorker({
    required this.db,
    required this.client,
    this.baseUrl = 'http://localhost:8080',
    this.terminalId = 'T01',
    this.deviceId = 'dev-mobile-t01',
  });

  /// Executes full sync cycle: Push pending local events, then pull remote changes.
  Future<SyncResult> syncOnce({bool simulateOffline = false}) async {
    if (simulateOffline) {
      return SyncResult.offline('Simulasi mode offline aktif');
    }

    try {
      final pushedCount = await _pushPendingEvents();
      final pulledCount = await _pullRemoteEvents();

      return SyncResult.success(pushed: pushedCount, pulled: pulledCount);
    } catch (e) {
      return SyncResult.failure(e.toString());
    }
  }

  Future<int> _pushPendingEvents() async {
    final pending = await db.getPendingOutboxEvents(limit: 50);
    if (pending.isEmpty) return 0;

    final eventsPayload = pending.map((e) {
      return {
        'event_id': e.eventId,
        'entity_type': e.entityType,
        'op': e.op,
        'hlc': e.hlc,
        'payload': jsonDecode(e.payload),
      };
    }).toList();

    final body = jsonEncode({
      'terminal_id': terminalId,
      'device_id': deviceId,
      'events': eventsPayload,
    });

    final response = await client.post(
      Uri.parse('$baseUrl/api/v1/sync/push'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('Gagal push sync (HTTP ${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final accepted = (data['accepted'] as List<dynamic>?)?.cast<String>() ?? [];

    final now = DateTime.now().toUtc();
    for (final eventId in accepted) {
      await db.markEventDone(eventId);

      // Find matching outbox event to check if it was a sale
      final match = pending.firstWhere((e) => e.eventId == eventId);
      if (match.entityType == 'sale') {
        await db.markSaleSynced(match.entityId, now);
      }
    }

    return accepted.length;
  }

  Future<int> _pullRemoteEvents() async {
    final lastSeqStr = await db.getSyncState('last_pulled_seq');
    final lastSeq = int.tryParse(lastSeqStr ?? '0') ?? 0;

    final catalogVerStr = await db.getSyncState('catalog_version');
    final catalogVer = int.tryParse(catalogVerStr ?? '0') ?? 0;

    final uri = Uri.parse('$baseUrl/api/v1/sync/pull').replace(
      queryParameters: {
        'since': lastSeq.toString(),
        'catalog_version': catalogVer.toString(),
        'limit': '100',
      },
    );

    final response = await client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Gagal pull sync (HTTP ${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    // 1. Apply catalog updates if received
    if (data['catalog'] != null && data['catalog'] is List) {
      final catalogList = data['catalog'] as List<dynamic>;
      for (final item in catalogList) {
        final p = item as Map<String, dynamic>;
        await db.upsertProduct(
          ProductsCompanion(
            id: drift.Value(p['id'] as String),
            name: drift.Value(p['name'] as String),
            category: drift.Value(p['category'] as String?),
            priceCents: drift.Value((p['price_cents'] as num).toInt()),
            baseStock: drift.Value(p['base_stock'] != null ? (p['base_stock'] as num).toInt() : 0),
            catalogVersion: drift.Value((p['catalog_version'] as num?)?.toInt() ?? 1),
            deleted: drift.Value(p['deleted'] as bool? ?? false),
          ),
        );
      }
    }

    // 2. Process incoming events from other devices
    final events = (data['events'] as List<dynamic>?) ?? [];
    var processedCount = 0;

    for (final rawEvent in events) {
      final ev = rawEvent as Map<String, dynamic>;
      final eventDeviceId = ev['device_id'] as String?;

      // Skip own events to prevent duplication of sales / local ledger
      if (eventDeviceId == deviceId) {
        continue;
      }

      processedCount++;
      // If sale event from another terminal, record stock movement to maintain stock convergence
      if (ev['entity_type'] == 'sale' && ev['op'] == 'create') {
        final payload = ev['payload'] as Map<String, dynamic>?;
        if (payload != null && payload['items'] is List) {
          for (final item in payload['items'] as List<dynamic>) {
            final it = item as Map<String, dynamic>;
            await db.into(db.stockMovements).insert(
                  StockMovementsCompanion.insert(
                    id: 'remote-mv-${ev['event_id']}-${it['product_id']}',
                    productId: it['product_id'] as String,
                    delta: -((it['qty'] as num).toInt()),
                    reason: 'remote_sale',
                    saleId: drift.Value(payload['sale_id'] as String?),
                    hlc: drift.Value(ev['hlc'] as String?),
                    createdAt: DateTime.now().toUtc(),
                    syncedAt: drift.Value(DateTime.now().toUtc()),
                  ),
                );
          }
        }
      }
    }

    // 3. Update sync state
    final nextSince = (data['next_since'] as num?)?.toInt() ?? lastSeq;
    await db.setSyncState('last_pulled_seq', nextSince.toString());

    final currentCatVer = (data['current_catalog_version'] as num?)?.toInt();
    if (currentCatVer != null) {
      await db.setSyncState('catalog_version', currentCatVer.toString());
    }

    return processedCount;
  }
}
