import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/app_database.dart';
import '../domain/cart_notifier.dart';
import '../../history/presentation/history_screen.dart';
import '../../sync/presentation/sync_badge.dart';
import '../../sync_inspector/presentation/sync_inspector_screen.dart';
import '../../../data/sync/sync_status_notifier.dart';
import 'widgets/cart_sheet.dart';
import 'widgets/product_grid.dart';

final _currencyFormatter = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

class CashierScreen extends ConsumerStatefulWidget {
  const CashierScreen({super.key});

  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CartSheet(
        onCheckoutSuccess: () {
          setState(() {});
        },
      ),
    );
  }

  Future<void> _seedDemoProducts() async {
    final db = ref.read(databaseProvider);
    final demoProducts = [
      (id: 'prod-001', name: 'Kopi Susu Aren', cat: 'Minuman', price: 18000, stock: 25),
      (id: 'prod-002', name: 'Americano Dingin', cat: 'Minuman', price: 15000, stock: 30),
      (id: 'prod-003', name: 'Matcha Latte', cat: 'Minuman', price: 22000, stock: 15),
      (id: 'prod-004', name: 'Roti Bakar Cokelat', cat: 'Makanan', price: 16000, stock: 20),
      (id: 'prod-005', name: 'Pisang Goreng Crispy', cat: 'Makanan', price: 14000, stock: 18),
      (id: 'prod-006', name: 'Mie Goreng Spesial', cat: 'Makanan', price: 20000, stock: 10),
    ];

    for (final p in demoProducts) {
      await db.upsertProduct(
        ProductsCompanion.insert(
          id: p.id,
          name: p.name,
          category: drift.Value(p.cat),
          priceCents: p.price,
          baseStock: drift.Value(p.stock),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(activeProductsProvider);
    final pendingOutboxAsync = ref.watch(pendingOutboxCountProvider);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Rukun POS'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfacePrimary,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.borderHairline),
              ),
              child: const Text(
                'T01',
                style: TextStyle(
                  color: AppColors.accentPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined, color: AppColors.textPrimary),
            tooltip: 'Riwayat Transaksi',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          // Live Sync Indicator Badge
          pendingOutboxAsync.when(
            data: (count) {
              // Synchronize notifier with current DB count
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  ref.read(syncStatusProvider.notifier).updatePendingCount(count);
                }
              });

              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: SyncBadge(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SyncInspectorScreen()),
                      );
                    },
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (err, stack) => const SizedBox.shrink(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Cari produk atau kategori...',
                prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: AppColors.textMuted),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: productsAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Katalog produk kosong',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _seedDemoProducts,
                    child: const Text('Muat 6 Produk Demo'),
                  ),
                ],
              ),
            );
          }

          final filtered = products.where((p) {
            if (_searchQuery.isEmpty) return true;
            final matchName = p.name.toLowerCase().contains(_searchQuery);
            final matchCat = (p.category ?? '').toLowerCase().contains(_searchQuery);
            return matchName || matchCat;
          }).toList();

          return ProductGrid(products: filtered);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error: $err', style: const TextStyle(color: AppColors.accentDanger)),
        ),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surfaceElevated,
                border: Border(top: BorderSide(color: AppColors.borderHairline)),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${cart.totalQuantity} item dalam keranjang',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _currencyFormatter.format(cart.totalCents),
                          style: const TextStyle(
                            color: AppColors.accentPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _openCartSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentPrimary,
                        foregroundColor: AppColors.bgPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        minimumSize: const Size(120, 46),
                      ),
                      child: const Text(
                        'Bayar',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
