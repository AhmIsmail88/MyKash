import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';
import '../scanning/scanner_page.dart';

class _PLine {
  final ItemRow item;
  ItemUnit unit;
  final TextEditingController qty = TextEditingController(text: '1');
  final TextEditingController cost;
  _PLine(this.item, this.unit)
      : cost = TextEditingController(
            text: moneyInput((item.costPrice * unit.factorMilli / 1000).round()));

  int get qtyMilli => parseQty(qty.text);
  int get unitCost => parseMoney(cost.text);
  int get total => (unitCost * qtyMilli / 1000).round();

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

/// شاشة كاملة لإنشاء فاتورة توريد. تُرجع true عند الحفظ.
class PurchaseEditorPage extends ConsumerStatefulWidget {
  const PurchaseEditorPage({super.key});
  @override
  ConsumerState<PurchaseEditorPage> createState() => _PurchaseEditorPageState();
}

class _PurchaseEditorPageState extends ConsumerState<PurchaseEditorPage> {
  final _search = TextEditingController();
  final _paid = TextEditingController();
  final List<_PLine> _lines = [];
  String _q = '';
  String? _supplierId;

  @override
  void dispose() {
    _search.dispose();
    _paid.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  int get _total => _lines.fold<int>(0, (s, l) => s + l.total);

  Future<void> _addItem(ItemRow it, {ItemUnit? unit}) async {
    final u = unit ?? await ref.read(databaseProvider).defaultUnit(it.id);
    final i = _lines.indexWhere((l) => l.item.id == it.id && l.unit.id == u.id);
    setState(() {
      if (i >= 0) {
        _lines[i].qty.text = formatQty(_lines[i].qtyMilli + 1000);
      } else {
        _lines.add(_PLine(it, u));
      }
      _search.clear();
      _q = '';
    });
  }

  Future<String?> _handleCode(String code) async {
    final db = ref.read(databaseProvider);
    final m = await db.matchBarcode(code);
    if (m == null) return 'غير موجود: $code';
    final it = await db.itemRowById(m.item.id);
    if (it == null) return 'غير موجود: $code';
    await _addItem(it, unit: m.unit);
    return 'أُضيف: ${it.name} (${m.unit.name})';
  }

  Future<void> _submitSearch(String text) async {
    final code = text.trim();
    if (code.isEmpty) return;
    await _handleCode(code);
  }

  Future<void> _openScanner() async {
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ScannerPage(title: 'مسح أصناف التوريد', onCode: _handleCode),
    ));
  }

  Future<void> _addSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مورد جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 10),
          TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'الهاتف')),
        ]),
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
      final id = await ref
          .read(databaseProvider)
          .addSupplier(name: name.text.trim(), phone: phone.text.trim());
      if (mounted) setState(() => _supplierId = id);
    }
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      _snack('أضف صنفًا واحدًا على الأقل');
      return;
    }
    for (final l in _lines) {
      if (l.qtyMilli <= 0 || l.unitCost < 0) {
        _snack('راجع الكمية والتكلفة في ${l.item.name}');
        return;
      }
    }
    try {
      final number = await ref.read(databaseProvider).createPurchase(
            supplierId: _supplierId,
            lines: [
              for (final l in _lines)
                PurchaseLineInput(
                  itemId: l.item.id,
                  unitId: l.unit.id,
                  qtyMilli: l.qtyMilli,
                  unitCost: l.unitCost,
                  factorMilli: l.unit.factorMilli,
                ),
            ],
            paidNow: parseMoney(_paid.text),
            userId: ref.read(sessionProvider)?.id,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تم حفظ فاتورة التوريد $number')));
    } catch (e) {
      _snack(e is StateError ? e.message : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).valueOrNull ?? [];
    final selected =
        suppliers.any((s) => s.id == _supplierId) ? _supplierId : null;
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة توريد جديدة')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'المورد'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('بدون مورد (شراء نقدي)')),
                  for (final s in suppliers)
                    DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _supplierId = v),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'مورد جديد',
              onPressed: _addSupplier,
              icon: const Icon(Icons.person_add_alt),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _q = v),
                onSubmitted: _submitSearch,
                decoration: const InputDecoration(
                  hintText: 'ابحث عن صنف أو امسح الباركود',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (canScanWithCamera) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'مسح بالكاميرا',
                style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                onPressed: _openScanner,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ],
          ]),
        ),
        Expanded(
          child: _q.trim().isNotEmpty
              ? Consumer(builder: (context, ref, _) {
                  final res = ref.watch(itemSearchProvider(_q.trim()));
                  return res.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('خطأ: $e')),
                    data: (list) => list.isEmpty
                        ? const Center(child: Text('لا توجد أصناف مطابقة'))
                        : ListView(children: [
                            for (final it in list)
                              ListTile(
                                title: Text(it.name),
                                subtitle: Text(
                                    'المخزون: ${formatQty(it.stockMilli)} ${it.baseUnit}'),
                                onTap: () => _addItem(it),
                              ),
                          ]),
                  );
                })
              : _lines.isEmpty
                  ? const Center(child: Text('أضف الأصناف الموردة'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _lines.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _lineTile(_lines[i]),
                    ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFDDE5E1))),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('الإجمالي'),
              Text(formatMoney(_total),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            ]),
            if (selected != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _paid,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'المدفوع الآن (الباقي دين للمورد)', isDense: true),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGreen),
                onPressed: _save,
                child: const Text('حفظ فاتورة التوريد',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _lineTile(_PLine l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text(l.item.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text(formatMoney(l.total),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _lines.remove(l);
              l.dispose();
            }),
          ),
        ]),
        Row(children: [
          Consumer(builder: (context, ref, _) {
            final units = ref.watch(itemUnitsProvider(l.item.id)).valueOrNull ?? [];
            if (units.length <= 1) return Text(l.unit.name);
            return PopupMenuButton<ItemUnit>(
              tooltip: 'تغيير الوحدة',
              onSelected: (u) => setState(() {
                l.unit = u;
                l.cost.text =
                    moneyInput((l.item.costPrice * u.factorMilli / 1000).round());
              }),
              itemBuilder: (_) => [
                for (final u in units)
                  PopupMenuItem(value: u, child: Text(u.name)),
              ],
              child: Chip(
                  label: Text('${l.unit.name}  ▾'),
                  visualDensity: VisualDensity.compact),
            );
          }),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: l.qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'الكمية', isDense: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: l.cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration:
                  const InputDecoration(labelText: 'تكلفة الوحدة', isDense: true),
            ),
          ),
        ]),
      ]),
    );
  }
}
