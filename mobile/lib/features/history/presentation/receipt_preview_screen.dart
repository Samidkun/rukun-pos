import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/app_database.dart';
import '../../cashier/domain/cart_notifier.dart';

final _currencyFormatter = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

final _dateFormatter = DateFormat('yyyy-MM-dd HH:mm');

String generateReceiptText({
  required Sale sale,
  required List<SaleItem> items,
  bool is80mm = false,
}) {
  final width = is80mm ? 48 : 32;
  final buffer = StringBuffer();

  String center(String text) {
    if (text.length >= width) return text;
    final pad = (width - text.length) ~/ 2;
    return ' ' * pad + text;
  }

  String line() => '=' * width;
  String dash() => '-' * width;

  String row(String left, String right) {
    final totalLen = left.length + right.length;
    if (totalLen >= width) {
      return '$left $right';
    }
    final spaces = width - totalLen;
    return left + (' ' * spaces) + right;
  }

  buffer.writeln(line());
  buffer.writeln(center('RUKUN POS'));
  buffer.writeln(center('Jl. Kemakmuran No. 42'));
  buffer.writeln(line());

  final invoiceStr = '${sale.invoiceSeries}-${sale.invoiceNumber.toString().padLeft(6, '0')}';
  buffer.writeln(row('Invoice:', invoiceStr));
  buffer.writeln(row('Waktu  :', _dateFormatter.format(sale.occurredAt.toLocal())));
  buffer.writeln(row('Kasir  :', sale.terminalId));
  final syncStatus = sale.syncedAt == null ? 'PENDING (OFFLINE)' : 'TERKIRIM';
  buffer.writeln(row('Status :', syncStatus));
  buffer.writeln(dash());

  for (final item in items) {
    buffer.writeln(item.name);
    final qtyPrice = '  ${item.qty} x ${_currencyFormatter.format(item.priceCents)}';
    final subtotal = _currencyFormatter.format(item.priceCents * item.qty);
    buffer.writeln(row(qtyPrice, subtotal));
  }

  buffer.writeln(dash());
  buffer.writeln(row('TOTAL', _currencyFormatter.format(sale.totalCents)));
  buffer.writeln(row('METODE BAYAR', sale.paymentMethod.toUpperCase()));
  buffer.writeln(line());
  buffer.writeln(center('Terima kasih atas kunjungannya'));
  buffer.writeln(center('Simpan struk ini sebagai bukti'));
  buffer.writeln(line());

  return buffer.toString();
}

class ReceiptPreviewScreen extends ConsumerStatefulWidget {
  final Sale sale;
  final List<SaleItem>? initialItems;

  const ReceiptPreviewScreen({
    super.key,
    required this.sale,
    this.initialItems,
  });

  @override
  ConsumerState<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends ConsumerState<ReceiptPreviewScreen> {
  bool _is80mm = false;
  List<SaleItem>? _items;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialItems != null) {
      _items = widget.initialItems;
      _isLoading = false;
    } else {
      _loadItems();
    }
  }

  Future<void> _loadItems() async {
    final db = ref.read(databaseProvider);
    final items = await db.getSaleItems(widget.sale.id);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Struk berhasil disalin ke clipboard!'),
        backgroundColor: AppColors.accentSuccess,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoiceStr = '${widget.sale.invoiceSeries}-${widget.sale.invoiceNumber.toString().padLeft(6, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Struk #$invoiceStr'),
        actions: [
          IconButton(
            icon: Icon(_is80mm ? Icons.format_align_left : Icons.format_align_center),
            tooltip: _is80mm ? 'Beralih ke 58mm' : 'Beralih ke 80mm',
            onPressed: () {
              setState(() => _is80mm = !_is80mm);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Receipt Card (Monospaced Thermal Preview)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfacePrimary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderHairline),
                    ),
                    child: SelectableText(
                      generateReceiptText(
                        sale: widget.sale,
                        items: _items ?? [],
                        is80mm: _is80mm,
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Actions
                  ElevatedButton.icon(
                    onPressed: () {
                      final text = generateReceiptText(
                        sale: widget.sale,
                        items: _items ?? [],
                        is80mm: _is80mm,
                      );
                      _copyToClipboard(text);
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Salin Teks Struk'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentPrimary,
                      foregroundColor: AppColors.bgPrimary,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
