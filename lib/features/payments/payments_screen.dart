import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/printing/print_service.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';

const _methods = {'cash': 'نقدي', 'transfer': 'تحويل', 'cheque': 'شيك'};

/// التحصيل من العملاء (الكل) وسداد الموردين (المدير).
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});
  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  bool _all = false;

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(sessionProvider)?.isAdmin ?? false;
    final count = isAdmin ? 2 : 1;
    if (_tabs == null || _tabs!.length != count) {
      _tabs?.dispose();
      _tabs = TabController(length: count, vsync: this);
    }
    return Column(children: [
      Material(
        color: Colors.white,
        child: Row(children: [
          Expanded(
            child: TabBar(
              controller: _tabs,
              labelColor: kGreen,
              indicatorColor: kGreen,
              tabs: [
                const Tab(text: 'العملاء (تحصيل)'),
                if (isAdmin) const Tab(text: 'الموردون (سداد)'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilterChip(
              label: const Text('عرض الكل'),
              selected: _all,
              onSelected: (v) => setState(() => _all = v),
            ),
          ),
        ]),
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          _CustomersTab(showAll: _all),
          if (isAdmin) _SuppliersTab(showAll: _all),
        ]),
      ),
    ]);
  }
}

class _CustomersTab extends ConsumerWidget {
  final bool showAll;
  const _CustomersTab({required this.showAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(customersProvider);
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (all) {
        final rows = all.where((c) => showAll || c.balance != 0).toList()
          ..sort((a, b) => b.balance.compareTo(a.balance));
        if (rows.isEmpty) {
          return const Center(child: Text('لا توجد مديونيات على العملاء'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final c = rows[i];
            return Card(
              child: ListTile(
                title: Text(c.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: c.phone == null || c.phone!.isEmpty
                    ? null
                    : Text(c.phone!),
                trailing: Text(formatMoney(c.balance),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: c.balance > 0
                            ? const Color(0xFFA23B2A)
                            : const Color(0xFF0B6B57))),
                onTap: () => showPartyStatement(
                    context, ref, partyType: 'customer', id: c.id, name: c.name),
              ),
            );
          },
        );
      },
    );
  }
}

class _SuppliersTab extends ConsumerWidget {
  final bool showAll;
  const _SuppliersTab({required this.showAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(suppliersProvider);
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (all) {
        final rows = all.where((c) => showAll || c.balance != 0).toList()
          ..sort((a, b) => b.balance.compareTo(a.balance));
        if (rows.isEmpty) {
          return const Center(child: Text('لا توجد مستحقات للموردين'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final s = rows[i];
            return Card(
              child: ListTile(
                title: Text(s.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: Text(formatMoney(s.balance),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: Color(0xFF8A5A00))),
                onTap: () => showPartyStatement(
                    context, ref, partyType: 'supplier', id: s.id, name: s.name),
              ),
            );
          },
        );
      },
    );
  }
}

/// كشف حساب عميل/مورد مع زر تسجيل دفعة.
Future<void> showPartyStatement(
  BuildContext context,
  WidgetRef ref, {
  required String partyType,
  required String id,
  required String name,
}) async {
  final db = ref.read(databaseProvider);
  final isCustomer = partyType == 'customer';
  Future<List<StatementEntry>> load() =>
      isCustomer ? db.customerStatement(id) : db.supplierStatement(id);
  var future = load();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: FutureBuilder<List<StatementEntry>>(
            future: future,
            builder: (_, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()));
              }
              final entries = snap.data!;
              var running = 0;
              final rows = <Widget>[];
              for (final e in entries) {
                running += e.plus - e.minus;
                rows.add(ListTile(
                  dense: true,
                  title: Text(e.title),
                  subtitle: Text(formatDateTime(e.at)),
                  trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            e.plus > 0
                                ? '+${formatMoney(e.plus)}'
                                : '−${formatMoney(e.minus)}',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: e.plus > 0
                                    ? const Color(0xFFA23B2A)
                                    : const Color(0xFF0B6B57))),
                        Text('الرصيد ${formatMoney(running)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                      ]),
                ));
              }
              final balance = running;
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                      child: Text('كشف حساب $name',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    Text(
                        '${isCustomer ? "عليه" : "له"}: ${formatMoney(balance)}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ]),
                ),
                const Divider(height: 1),
                Flexible(
                  child: entries.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('لا توجد حركات'))
                      : ListView(shrinkWrap: true, children: rows),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إغلاق')),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          final shop = await loadShopInfo(db);
                          final bytes = await buildStatementPdf(
                            title: 'كشف حساب $name',
                            shop: shop,
                            entries: entries,
                            balance: balance,
                            plusLabel: isCustomer ? 'مدين' : 'مستحق',
                            minusLabel: isCustomer ? 'دائن' : 'مسدّد',
                          );
                          await printPdf(bytes, 'كشف حساب $name');
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('تعذّرت الطباعة: $e')));
                          }
                        }
                      },
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('طباعة'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () async {
                        final done = await _paymentDialog(
                            ctx, ref, partyType, id, balance);
                        if (done == true) setD(() => future = load());
                      },
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(isCustomer ? 'تسجيل تحصيل' : 'تسجيل سداد'),
                    ),
                  ]),
                ),
              ]);
            },
          ),
        ),
      );
    }),
  );
}

Future<bool?> _paymentDialog(BuildContext ctx, WidgetRef ref, String partyType,
    String partyId, int balance) async {
  final amount = TextEditingController(
      text: balance > 0 ? moneyInput(balance) : '');
  final note = TextEditingController();
  var method = 'cash';
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (c2) => StatefulBuilder(
      builder: (c2, setD) => AlertDialog(
        title: Text(partyType == 'customer' ? 'تسجيل تحصيل' : 'تسجيل سداد'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: method,
              decoration: const InputDecoration(labelText: 'الطريقة'),
              items: [
                for (final e in _methods.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setD(() => method = v ?? 'cash'),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c2, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(c2, true),
              child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  final value = parseMoney(amount.text);
  if (value <= 0) {
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx)
          .showSnackBar(const SnackBar(content: Text('اكتب مبلغًا صحيحًا')));
    }
    return false;
  }
  await ref.read(databaseProvider).recordPayment(
        partyType: partyType,
        partyId: partyId,
        direction: partyType == 'customer' ? 'in' : 'out',
        amount: value,
        method: method,
        note: note.text.trim(),
        userId: ref.read(sessionProvider)?.id,
      );
  return true;
}
