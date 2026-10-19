import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';
import 'purchase_editor.dart';

/// الموردون والتوريد (للمدير): فواتير التوريد + قائمة الموردين.
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});
  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _newPurchase() async {
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
          fullscreenDialog: true, builder: (_) => const PurchaseEditorPage()),
    );
  }

  Future<void> _addSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مورد جديد'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 10),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الهاتف')),
            const SizedBox(height: 10),
            TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'العنوان')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await ref.read(databaseProvider).addSupplier(
          name: name.text.trim(),
          phone: phone.text.trim(),
          address: address.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(sessionProvider)?.isAdmin ?? false;
    if (!isAdmin) return const Center(child: Text('هذه الشاشة للمدير فقط'));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: _newPurchase,
              icon: const Icon(Icons.add),
              label: const Text('توريد جديد'))
          : FloatingActionButton.extended(
              onPressed: _addSupplier,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('مورد جديد')),
      body: Column(children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            labelColor: kGreen,
            indicatorColor: kGreen,
            tabs: const [Tab(text: 'فواتير التوريد'), Tab(text: 'الموردون')],
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: const [
            _PurchasesTab(),
            _SuppliersTab(),
          ]),
        ),
      ]),
    );
  }
}

class _PurchasesTab extends ConsumerWidget {
  const _PurchasesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(purchasesProvider);
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('لا توجد فواتير توريد بعد.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final p = rows[i];
            final cancelled = p.status == 'cancelled';
            return Card(
              child: ListTile(
                onTap: () => _details(context, ref, p),
                title: Row(children: [
                  Text(p.number,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (cancelled) ...[
                    const SizedBox(width: 8),
                    const Chip(
                        label: Text('ملغاة'), visualDensity: VisualDensity.compact),
                  ],
                ]),
                subtitle: Text(
                    '${formatDateTime(p.purchasedAt)} · ${p.supplierName ?? "شراء نقدي"}'),
                trailing: Text(formatMoney(p.total),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        decoration:
                            cancelled ? TextDecoration.lineThrough : null)),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _details(BuildContext context, WidgetRef ref, PurchaseRow p) async {
    final db = ref.read(databaseProvider);
    final lines = await db.purchaseLinesFor(p.id);
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('فاتورة توريد ${p.number}'),
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
                            '${l.name}  ×${formatQty(l.qtyMilli)} ${l.unitName} @ ${formatMoney(l.unitCost)}')),
                    Text(formatMoney(l.total),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('الإجمالي'),
                Text(formatMoney(p.total),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('المدفوع'),
                Text(formatMoney(p.paid)),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          if (p.status == 'completed')
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA23B2A)),
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('إلغاء الفاتورة'),
            ),
        ],
      ),
    );
    if (action != 'cancel' || !context.mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإلغاء'),
        content: const Text(
            'سيتم خصم الأصناف من المخزون وعكس الدفعة المسجّلة للمورد. لا يمكن التراجع.'),
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
      await db.cancelPurchase(p.id, userId: ref.read(sessionProvider)?.id);
    }
  }
}

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(suppliersProvider);
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (rows) {
        if (rows.isEmpty) return const Center(child: Text('لا يوجد موردون بعد.'));
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final s = rows[i];
            final sub = [s.phone, s.address]
                .where((e) => e != null && e.isNotEmpty)
                .join(' · ');
            return Card(
              child: ListTile(
                title: Text(s.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: sub.isEmpty ? null : Text(sub),
                trailing: s.balance == 0
                    ? null
                    : Text('له: ${formatMoney(s.balance)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8A5A00))),
              ),
            );
          },
        );
      },
    );
  }
}
