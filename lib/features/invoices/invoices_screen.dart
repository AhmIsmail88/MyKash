import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/printing/print_service.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});
  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  String _q = '';
  String _filter = 'all';

  static const _filters = {
    'all': 'الكل',
    'cash': 'كاش',
    'credit': 'آجل',
    'cancelled': 'ملغاة',
  };

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(salesListProvider((_q, _filter)));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(
            hintText: 'ابحث برقم الفاتورة أو اسم العميل',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final e in _filters.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _filter == e.key,
                  onSelected: (_) => setState(() => _filter = e.key),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: sales.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
          data: (list) {
            if (list.isEmpty) return const Center(child: Text('لا توجد فواتير'));
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _SaleTile(sale: list[i]),
            );
          },
        ),
      ),
    ]);
  }
}

class _SaleTile extends ConsumerWidget {
  final SaleRow sale;
  const _SaleTile({required this.sale});

  void _snack(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cancelled = sale.status == 'cancelled';
    final sub = [
      formatDateTime(sale.soldAt),
      sale.type == 'credit' ? 'آجل' : 'كاش',
      if (sale.customerName != null) sale.customerName!,
    ].join(' · ');
    return Card(
      child: ListTile(
        onTap: () => _showDetails(context, ref),
        title: Row(children: [
          Text(sale.number, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (cancelled) ...[
            const SizedBox(width: 8),
            const Chip(
              label: Text('ملغاة'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ]),
        subtitle: Text(sub),
        trailing: Text(
          formatMoney(sale.total),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            decoration: cancelled ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final lines = await db.saleLinesFor(sale.id);
    if (!context.mounted) return;
    final isAdmin = ref.read(sessionProvider)?.isAdmin ?? false;
    final completed = sale.status == 'completed';
    final canReturn =
        isAdmin && completed && lines.any((l) => l.remainingMilli > 0);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('فاتورة ${sale.number}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                          '${l.name}  ×${formatQty(l.qtyMilli)} ${l.unitName}'
                          '${l.returnedMilli > 0 ? "  (مرتجع ${formatQty(l.returnedMilli)})" : ""}'),
                    ),
                    Text(formatMoney(l.total),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('الإجمالي'),
                Text(formatMoney(sale.total),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('المدفوع'),
                Text(formatMoney(sale.paid)),
              ]),
              if (sale.status == 'cancelled')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('هذه الفاتورة ملغاة',
                      style: TextStyle(color: Color(0xFFA23B2A))),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'print'),
            icon: const Icon(Icons.print_outlined),
            label: const Text('طباعة'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'share'),
            icon: const Icon(Icons.ios_share),
            label: const Text('PDF'),
          ),
          if (canReturn)
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'return'),
              child: const Text('مرتجع جزئي'),
            ),
          if (isAdmin && completed)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA23B2A)),
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('إلغاء الفاتورة'),
            ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'return') {
      await _returnDialog(context, ref, lines);
    } else if (action == 'cancel') {
      await _cancelFlow(context, ref);
    } else if (action == 'print' || action == 'share') {
      try {
        final db = ref.read(databaseProvider);
        if (action == 'print') {
          await printInvoice(db, sale.id);
        } else {
          await shareInvoice(db, sale.id);
        }
      } catch (e) {
        if (context.mounted) _snack(context, 'تعذّرت الطباعة: $e');
      }
    }
  }

  Future<void> _cancelFlow(BuildContext context, WidgetRef ref) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإلغاء'),
        content: const Text(
            'سيتم إرجاع المتبقي من الأصناف للمخزون وعكس أي دفعة. لا يمكن التراجع عن الإلغاء.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، ألغِ')),
        ],
      ),
    );
    if (sure == true) {
      await ref
          .read(databaseProvider)
          .cancelSale(sale.id, userId: ref.read(sessionProvider)?.id);
    }
  }

  Future<void> _returnDialog(
      BuildContext context, WidgetRef ref, List<SaleDetailLine> lines) async {
    final returnable = lines.where((l) => l.remainingMilli > 0).toList();
    final ctrls = {for (final l in returnable) l.lineId: TextEditingController()};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('مرتجع من فاتورة ${sale.number}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final l in returnable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: ctrls[l.lineId],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          '${l.name} — المتاح للإرجاع ${formatQty(l.remainingMilli)} ${l.unitName}',
                      hintText: '0',
                    ),
                  ),
                ),
              const Text('قيمة الاسترداد تُحسب بسعر البيع (بعد نسبة خصم الفاتورة).',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد المرتجع')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final qty = <String, int>{
      for (final e in ctrls.entries) e.key: parseQty(e.value.text),
    }..removeWhere((_, v) => v <= 0);
    if (qty.isEmpty) return;
    try {
      final refund = await ref
          .read(databaseProvider)
          .returnItems(sale.id, qty, userId: ref.read(sessionProvider)?.id);
      if (context.mounted) {
        _snack(context, 'تم المرتجع، قيمة الاسترداد ${formatMoney(refund)}');
      }
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'تعذّر المرتجع: ${e is StateError ? e.message : e}');
      }
    }
  }
}
