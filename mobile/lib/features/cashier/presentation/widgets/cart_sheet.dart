import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/db/app_database.dart';
import '../../domain/cart_notifier.dart';

final _currencyFormatter = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

class CartSheet extends ConsumerStatefulWidget {
  final VoidCallback onCheckoutSuccess;

  const CartSheet({super.key, required this.onCheckoutSuccess});

  @override
  ConsumerState<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<CartSheet> {
  String _paymentMethod = 'cash';
  bool _isProcessing = false;

  Future<void> _handleCheckout(CartState cart) async {
    if (cart.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final db = ref.read(databaseProvider);
      final items = cart.items.values.map((item) {
        return (
          productId: item.product.id,
          name: item.product.name,
          priceCents: item.product.priceCents,
          qty: item.qty,
        );
      }).toList();

      final sale = await db.recordSaleTransaction(
        terminalId: 'T01',
        invoiceSeries: 'T01',
        paymentMethod: _paymentMethod,
        items: items,
      );

      ref.read(cartProvider.notifier).clear();

      if (!mounted) return;
      Navigator.pop(context); // Close sheet
      widget.onCheckoutSuccess();
      _showSuccessReceiptDialog(context, sale);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transaksi gagal: $e'),
          backgroundColor: AppColors.accentDanger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSuccessReceiptDialog(BuildContext context, Sale sale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderHairline),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.accentSuccess, size: 24),
            SizedBox(width: 8),
            Text(
              'Transaksi Berhasil',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invoice: ${sale.invoiceSeries}-${sale.invoiceNumber.toString().padLeft(6, '0')}',
              style: const TextStyle(
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Total: ${_currencyFormatter.format(sale.totalCents)}',
              style: const TextStyle(
                color: AppColors.accentPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfacePrimary,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderHairline),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_upload_outlined, color: AppColors.accentWarning, size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tersimpan lokal & masuk antrean outbox sync',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentPrimary,
              foregroundColor: AppColors.bgPrimary,
            ),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final formattedTotal = _currencyFormatter.format(cart.totalCents);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Keranjang Belanja',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfacePrimary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${cart.totalQuantity} item',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 16),

          // Items list
          if (cart.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Keranjang masih kosong',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: cart.items.values.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_currencyFormatter.format(item.product.priceCents)} x ${item.qty}',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, size: 18, color: AppColors.textPrimary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () {
                                ref.read(cartProvider.notifier).decrementItem(item.product.id);
                              },
                            ),
                            Text(
                              '${item.qty}',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18, color: AppColors.accentPrimary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () {
                                ref.read(cartProvider.notifier).addItem(item.product);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          const Divider(height: 24),

          // Total & Payment method
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Pembayaran',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              Text(
                formattedTotal,
                style: const TextStyle(
                  color: AppColors.accentPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Payment method buttons
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Tunai (Cash)'),
                  selected: _paymentMethod == 'cash',
                  onSelected: (selected) {
                    if (selected) setState(() => _paymentMethod = 'cash');
                  },
                  selectedColor: AppColors.surfacePrimary,
                  backgroundColor: AppColors.bgPrimary,
                  labelStyle: TextStyle(
                    color: _paymentMethod == 'cash'
                        ? AppColors.accentPrimary
                        : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('QRIS Offline'),
                  selected: _paymentMethod == 'qris',
                  onSelected: (selected) {
                    if (selected) setState(() => _paymentMethod = 'qris');
                  },
                  selectedColor: AppColors.surfacePrimary,
                  backgroundColor: AppColors.bgPrimary,
                  labelStyle: TextStyle(
                    color: _paymentMethod == 'qris'
                        ? AppColors.accentPrimary
                        : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Pay CTA Button
          ElevatedButton(
            onPressed: cart.isEmpty || _isProcessing
                ? null
                : () => _handleCheckout(cart),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentPrimary,
              foregroundColor: AppColors.bgPrimary,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bgPrimary),
                  )
                : Text(
                    'Bayar $formattedTotal',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
