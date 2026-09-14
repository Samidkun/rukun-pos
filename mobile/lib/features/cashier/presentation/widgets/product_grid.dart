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

class ProductGrid extends ConsumerWidget {
  final List<Product> products;

  const ProductGrid({super.key, required this.products});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (products.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada produk yang cocok',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.25,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _ProductCard(product: product);
      },
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final Product product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formattedPrice = _currencyFormatter.format(product.priceCents);

    return Material(
      color: AppColors.surfacePrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderHairline, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          ref.read(cartProvider.notifier).addItem(product);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.category != null && product.category!.isNotEmpty)
                    Text(
                      product.category!.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    product.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formattedPrice,
                    style: const TextStyle(
                      color: AppColors.accentPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.borderHairline, width: 0.5),
                    ),
                    child: Text(
                      'Stok: ${product.baseStock}',
                      style: TextStyle(
                        color: product.baseStock <= 0
                            ? AppColors.accentDanger
                            : AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
