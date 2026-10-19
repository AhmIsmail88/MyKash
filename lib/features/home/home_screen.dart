import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';

class HomeData {
  final ReportData today;
  final int receivables;
  final List<ItemRow> low;
  const HomeData(this.today, this.receivables, this.low);
}

final homeProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final today = await db.report(start.millisecondsSinceEpoch,
      start.add(const Duration(days: 1)).millisecondsSinceEpoch);
  return HomeData(today, await db.receivablesTotal(), await db.lowStockItems());
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Widget _card(String label, String value, {Color? color}) => SizedBox(
        width: 200,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(sessionProvider)?.isAdmin ?? false;
    final data = ref.watch(homeProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(homeProvider),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
            onPressed: () => context.go('/sales'),
            icon: const Icon(Icons.point_of_sale),
            label: const Text('بيع جديد'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(160, 52)),
            onPressed: () => context.go('/payments'),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('تحصيل'),
          ),
        ]),
        const SizedBox(height: 16),
        data.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('خطأ: $e'),
          data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 10, runSpacing: 10, children: [
              _card('مبيعات اليوم', formatMoney(d.today.salesTotal)),
              _card('فواتير اليوم', '${d.today.salesCount}'),
              if (isAdmin)
                _card('ربح اليوم (تقريبي)', formatMoney(d.today.profit),
                    color: d.today.profit >= 0
                        ? const Color(0xFF0B6B57)
                        : const Color(0xFFA23B2A)),
              _card('مديونيات العملاء', formatMoney(d.receivables),
                  color: const Color(0xFFA23B2A)),
              _card('أصناف ناقصة', '${d.low.length}',
                  color: d.low.isEmpty ? null : const Color(0xFFA23B2A)),
            ]),
            if (d.low.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 20, bottom: 6),
                child: Text('تنبيهات النواقص',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              for (final i in d.low.take(8))
                Card(
                  child: ListTile(
                    title: Text(i.name),
                    trailing: Text('${formatQty(i.stockMilli)} ${i.baseUnit}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, color: Color(0xFFA23B2A))),
                  ),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}
