import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/app_database.dart';
import '../../../data/sync/conflict_resolver.dart';
import '../../cashier/domain/cart_notifier.dart';

final oversoldProductsProvider = FutureProvider<List<OversoldIncident>>((ref) async {
  final db = ref.watch(databaseProvider);
  final products = await db.getActiveProducts();
  final incidents = <OversoldIncident>[];

  for (final p in products) {
    final stock = await db.calculateStock(p.id);
    if (stock < 0) {
      incidents.add(
        OversoldIncident(
          productId: p.id,
          productName: p.name,
          currentStock: stock,
          deficit: -stock,
          detectedAt: DateTime.now(),
        ),
      );
    }
  }

  return incidents;
});

class OversoldScreen extends ConsumerStatefulWidget {
  const OversoldScreen({super.key});

  @override
  ConsumerState<OversoldScreen> createState() => _OversoldScreenState();
}

class _OversoldScreenState extends ConsumerState<OversoldScreen> {
  Future<void> _quickRestock(String productId, int addQuantity) async {
    final db = ref.read(databaseProvider);
    const uuid = Uuid();

    await db.into(db.stockMovements).insert(
          StockMovementsCompanion.insert(
            id: uuid.v4(),
            productId: productId,
            delta: addQuantity,
            reason: 'adjust_oversold',
            createdAt: DateTime.now().toUtc(),
            syncedAt: const drift.Value.absent(),
          ),
        );

    ref.invalidate(oversoldProductsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restock berhasil: +$addQuantity unit'),
          backgroundColor: AppColors.accentSuccess,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final oversoldAsync = ref.watch(oversoldProductsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Stok Oversold (C1)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Explanation Alert Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentDanger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accentDanger, width: 0.8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.accentDanger, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Konflik Stok Minus (Overselling)',
                      style: TextStyle(
                        color: AppColors.accentDanger,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Terjadi ketika 2 terminal menjual unit terakhir bersamaan saat offline. '
                  'Semua penjualan tetap sah dan tidak dihapus. Pilih tindakan operasional di bawah:',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Incident List
          oversoldAsync.when(
            data: (incidents) {
              if (incidents.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline, color: AppColors.accentSuccess, size: 40),
                        SizedBox(height: 8),
                        Text(
                          'Tidak ada stok oversold',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Semua produk memiliki stok >= 0 unit',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: incidents.map((incident) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfacePrimary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderHairline),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                incident.productName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentDanger.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Defisit: ${incident.deficit} unit (Stok: ${incident.currentStock})',
                                      style: const TextStyle(
                                        color: AppColors.accentDanger,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => _quickRestock(
                            incident.productId,
                            incident.deficit + 5,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentPrimary,
                            foregroundColor: AppColors.bgPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: const Size(90, 36),
                          ),
                          child: Text(
                            '+${incident.deficit + 5} Restock',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text('Error: $err', style: const TextStyle(color: AppColors.accentDanger)),
            ),
          ),
        ],
      ),
    );
  }
}
