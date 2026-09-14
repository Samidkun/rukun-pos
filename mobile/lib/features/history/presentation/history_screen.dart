import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/app_database.dart';
import '../../cashier/domain/cart_notifier.dart';
import 'receipt_preview_screen.dart';

final _currencyFormatter = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

final _dateFormatter = DateFormat('dd MMM yyyy, HH:mm');

final salesHistoryStreamProvider = StreamProvider<List<Sale>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchSales();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesHistoryStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
      ),
      body: salesAsync.when(
        data: (sales) {
          if (sales.isEmpty) {
            return const Center(
              child: Text(
                'Belum ada transaksi lokal',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: sales.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final sale = sales[index];
              final isSynced = sale.syncedAt != null;
              final invoiceStr = '${sale.invoiceSeries}-${sale.invoiceNumber.toString().padLeft(6, '0')}';

              return Material(
                color: AppColors.surfacePrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.borderHairline),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final items = await ref.read(databaseProvider).getSaleItems(sale.id);
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceiptPreviewScreen(sale: sale, initialItems: items),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // Left: Invoice & Time
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    invoiceStr,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSynced
                                          ? AppColors.accentSuccess.withValues(alpha: 0.1)
                                          : AppColors.accentWarning.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isSynced ? 'Tersinkron' : 'Tertunda',
                                      style: TextStyle(
                                        color: isSynced ? AppColors.accentSuccess : AppColors.accentWarning,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _dateFormatter.format(sale.occurredAt.toLocal()),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Right: Amount & Arrow
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _currencyFormatter.format(sale.totalCents),
                              style: const TextStyle(
                                color: AppColors.accentPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              sale.paymentMethod.toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error: $err', style: const TextStyle(color: AppColors.accentDanger)),
        ),
      ),
    );
  }
}
