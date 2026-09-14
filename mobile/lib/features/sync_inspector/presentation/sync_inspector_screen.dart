import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../data/db/app_database.dart';
import '../../../data/sync/sync_status_notifier.dart';
import '../../../data/sync/sync_worker.dart';
import '../../cashier/domain/cart_notifier.dart';
import '../../oversold/presentation/oversold_screen.dart';

class SyncInspectorScreen extends ConsumerStatefulWidget {
  const SyncInspectorScreen({super.key});

  @override
  ConsumerState<SyncInspectorScreen> createState() => _SyncInspectorScreenState();
}

class _SyncInspectorScreenState extends ConsumerState<SyncInspectorScreen> {
  bool _isManualSyncing = false;
  String? _syncMessage;

  Future<void> _triggerManualSync() async {
    setState(() {
      _isManualSyncing = true;
      _syncMessage = null;
    });

    try {
      final db = ref.read(databaseProvider);
      final syncStatus = ref.read(syncStatusProvider);
      final worker = SyncWorker(db: db, client: http.Client());

      final result = await worker.syncOnce(simulateOffline: syncStatus.simulateOffline);
      if (!mounted) return;

      setState(() {
        if (result.success) {
          _syncMessage = 'Sync berhasil: ${result.pushedEventsCount} push, ${result.pulledEventsCount} pull';
          ref.read(syncStatusProvider.notifier).setSynced(
                at: DateTime.now(),
                remainingPending: 0,
              );
        } else if (result.isOffline) {
          _syncMessage = 'Offline: ${result.errorMessage}';
          ref.read(syncStatusProvider.notifier).setOffline(reason: result.errorMessage ?? 'Offline');
        } else {
          _syncMessage = 'Sync gagal: ${result.errorMessage}';
          ref.read(syncStatusProvider.notifier).setOffline(reason: result.errorMessage ?? 'Gagal');
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _syncMessage = 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isManualSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sync Inspector & Live Demo'),
          bottom: const TabBar(
            indicatorColor: AppColors.accentPrimary,
            labelColor: AppColors.accentPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(text: 'Outbox Event Log'),
              Tab(text: 'State & Cursors'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Interactive Demo Control Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppColors.surfaceElevated,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            syncStatus.simulateOffline ? Icons.cloud_off : Icons.cloud_done,
                            color: syncStatus.simulateOffline
                                ? AppColors.accentDanger
                                : AppColors.accentSuccess,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Simulasi Mode Offline',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: syncStatus.simulateOffline,
                        activeTrackColor: AppColors.accentDanger.withValues(alpha: 0.5),
                        thumbColor: const WidgetStatePropertyAll(AppColors.accentDanger),
                        onChanged: (_) {
                          ref.read(syncStatusProvider.notifier).toggleSimulateOffline();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isManualSyncing ? null : _triggerManualSync,
                          icon: _isManualSyncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.sync, size: 18),
                          label: Text(_isManualSyncing ? 'Sinkronisasi...' : 'Force Sync Sekarang'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const OversoldScreen()),
                          );
                        },
                        icon: const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.accentWarning),
                        label: const Text('Audit C1'),
                      ),
                    ],
                  ),
                  if (_syncMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.bgPrimary,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.borderHairline),
                      ),
                      child: Text(
                        _syncMessage!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Tabs Content
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Outbox Event Log
                  StreamBuilder<List<OutboxEvent>>(
                    stream: db.select(db.outboxEvents).watch(),
                    builder: (context, snapshot) {
                      final events = snapshot.data ?? [];
                      if (events.isEmpty) {
                        return const Center(
                          child: Text(
                            'Belum ada event di outbox lokal',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: events.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final event = events[index];
                          final isPending = event.status == 'pending';

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfacePrimary,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderHairline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${event.entityType.toUpperCase()} · ${event.op.toUpperCase()}',
                                      style: const TextStyle(
                                        color: AppColors.accentPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPending
                                            ? AppColors.accentWarning.withValues(alpha: 0.15)
                                            : AppColors.accentSuccess.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        event.status.toUpperCase(),
                                        style: TextStyle(
                                          color: isPending
                                              ? AppColors.accentWarning
                                              : AppColors.accentSuccess,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ID: ${event.eventId}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.bgPrimary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: SelectableText(
                                    _formatJson(event.payload),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),

                  // Tab 2: State & Cursors
                  FutureBuilder<List<SyncState>>(
                    future: db.select(db.syncStates).get(),
                    builder: (context, snapshot) {
                      final states = snapshot.data ?? [];
                      return ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          const Text(
                            'Kursor Sinkronisasi Terminal',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _StateRow(label: 'Terminal ID', value: 'T01'),
                          _StateRow(label: 'Device ID', value: 'dev-mobile-t01'),
                          ...states.map((s) => _StateRow(label: s.key, value: s.value)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return raw;
    }
  }
}

class _StateRow extends StatelessWidget {
  final String label;
  final String value;

  const _StateRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.accentPrimary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
