import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/printing/print_service.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';

class ReportExtras {
  final int inventoryValue, receivables, payables;
  final List<ItemRow> low;
  const ReportExtras(this.inventoryValue, this.receivables, this.payables, this.low);
}

final reportExtrasProvider = FutureProvider.autoDispose<ReportExtras>((ref) async {
  final db = ref.watch(databaseProvider);
  return ReportExtras(
    await db.inventoryValue(),
    await db.receivablesTotal(),
    await db.payablesTotal(),
    await db.lowStockItems(),
  );
});

(int, int) _rangeFor(String key, DateTimeRange? custom) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  int ms(DateTime d) => d.millisecondsSinceEpoch;
  switch (key) {
    case 'yesterday':
      return (ms(today.subtract(const Duration(days: 1))), ms(today));
    case '7d':
      return (ms(today.subtract(const Duration(days: 6))),
          ms(today.add(const Duration(days: 1))));
    case 'month':
      return (ms(DateTime(now.year, now.month, 1)),
          ms(DateTime(now.year, now.month + 1, 1)));
    case 'custom':
      if (custom != null) {
        return (ms(custom.start),
            ms(DateTime(custom.end.year, custom.end.month, custom.end.day + 1)));
      }
      return (ms(today), ms(today.add(const Duration(days: 1))));
    default:
      return (ms(today), ms(today.add(const Duration(days: 1))));
  }
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _key = 'today';
  DateTimeRange? _custom;

  static const _labels = {
    'today': 'اليوم',
    'yesterday': 'أمس',
    '7d': 'آخر 7 أيام',
    'month': 'هذا الشهر',
    'custom': 'فترة محددة',
  };

  Future<void> _pick(String key) async {
    if (key == 'custom') {
      final now = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _custom,
      );
      if (r == null) return;
      setState(() {
        _custom = r;
        _key = 'custom';
      });
    } else {
      setState(() => _key = key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(sessionProvider)?.isAdmin ?? false;
    if (!isAdmin) return const Center(child: Text('هذه الشاشة للمدير فقط'));
    final range = _rangeFor(_key, _custom);
    final report = ref.watch(reportProvider(range));
    final extras = ref.watch(reportExtrasProvider);
    return ListView(padding: const EdgeInsets.all(16), children: [
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final e in _labels.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(e.key == 'custom' && _custom != null && _key == 'custom'
                    ? '${_custom!.start.year}/${_custom!.start.month}/${_custom!.start.day} → ${_custom!.end.month}/${_custom!.end.day}'
                    : e.value),
                selected: _key == e.key,
                onSelected: (_) => _pick(e.key),
              ),
            ),
        ]),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: report.valueOrNull == null
              ? null
              : () async {
                  try {
                    final db = ref.read(databaseProvider);
                    final x = extras.valueOrNull;
                    final period = _key == 'custom' && _custom != null
                        ? '${_custom!.start.year}/${_custom!.start.month}/${_custom!.start.day} → ${_custom!.end.year}/${_custom!.end.month}/${_custom!.end.day}'
                        : _labels[_key]!;
                    final bytes = await buildReportPdf(
                      shop: await loadShopInfo(db),
                      period: period,
                      r: report.value!,
                      inventoryValue: x?.inventoryValue,
                      receivables: x?.receivables,
                      payables: x?.payables,
                    );
                    await printPdf(bytes, 'تقرير المبيعات');
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تعذّرت الطباعة: $e')));
                    }
                  }
                },
          icon: const Icon(Icons.print_outlined),
          label: const Text('طباعة / PDF'),
        ),
      ),
      report.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text('خطأ: $e'),
        data: (r) => _salesSection(context, r),
      ),
      const SizedBox(height: 16),
      extras.when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Text('خطأ: $e'),
        data: (x) => _extrasSection(context, x),
      ),
    ]);
  }

  Widget _stat(String label, String value, {Color? color}) => SizedBox(
        width: 190,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            ]),
          ),
        ),
      );

  Widget _salesSection(BuildContext context, ReportData r) {
    final summary = 'المبيعات: ${formatMoney(r.salesTotal)} (${r.salesCount} فاتورة)\n'
        'كاش: ${formatMoney(r.cashTotal)} · آجل: ${formatMoney(r.creditTotal)}\n'
        'المرتجعات: ${formatMoney(r.returnsTotal)}\n'
        'صافي المبيعات: ${formatMoney(r.net)}\n'
        'الربح التقريبي: ${formatMoney(r.profit)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('إجمالي المبيعات', formatMoney(r.salesTotal)),
        _stat('عدد الفواتير', '${r.salesCount}'),
        _stat('كاش', formatMoney(r.cashTotal)),
        _stat('آجل', formatMoney(r.creditTotal)),
        _stat('المرتجعات', formatMoney(r.returnsTotal),
            color: r.returnsTotal > 0 ? const Color(0xFFA23B2A) : null),
        _stat('صافي المبيعات', formatMoney(r.net)),
        _stat('الربح التقريبي', formatMoney(r.profit),
            color: r.profit >= 0 ? const Color(0xFF0B6B57) : const Color(0xFFA23B2A)),
      ]),
      const SizedBox(height: 6),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: summary));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ الملخص')));
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('نسخ الملخص'),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 8, bottom: 6),
        child: Text('الأكثر مبيعًا',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      if (r.top.isEmpty)
        const Text('لا توجد مبيعات في هذه الفترة')
      else
        for (final t in r.top)
          Card(
            child: ListTile(
              title: Text(t.name),
              subtitle: Text('${formatQty(t.baseQtyMilli)} ${t.baseUnit}'),
              trailing: Text(formatMoney(t.revenue),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
    ]);
  }

  Widget _extrasSection(BuildContext context, ReportExtras x) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('الوضع الحالي',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('قيمة المخزون (بالتكلفة)', formatMoney(x.inventoryValue)),
        _stat('مستحقات عند العملاء', formatMoney(x.receivables),
            color: const Color(0xFFA23B2A)),
        _stat('مستحقات للموردين', formatMoney(x.payables),
            color: const Color(0xFF8A5A00)),
      ]),
      const Padding(
        padding: EdgeInsets.only(top: 16, bottom: 6),
        child: Text('النواقص',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      if (x.low.isEmpty)
        const Text('لا توجد أصناف ناقصة')
      else
        for (final i in x.low)
          Card(
            child: ListTile(
              title: Text(i.name),
              subtitle: i.reorderMilli > 0
                  ? Text('حد إعادة الطلب: ${formatQty(i.reorderMilli)} ${i.baseUnit}')
                  : null,
              trailing: Text('${formatQty(i.stockMilli)} ${i.baseUnit}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFFA23B2A))),
            ),
          ),
    ]);
  }
}
