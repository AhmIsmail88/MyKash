import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../core/printing/print_service.dart';
import '../../sync/sync_providers.dart';
import '../auth/session.dart';
import '../scanning/scanner_page.dart';
import 'cart.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addItem(ItemRow it) async {
    final db = ref.read(databaseProvider);
    final unit = await db.defaultUnit(it.id);
    final tier = await db.priceForUnit(unit.id, 1000);
    if (!mounted) return;
    ref.read(cartProvider.notifier).add(CartLine.of(
          itemId: it.id,
          name: it.name,
          baseCost: it.costPrice,
          unit: unit,
          unitPrice: tier,
        ));
  }

  /// يضيف للسلة بحسب الباركود ويعيد رسالة للعرض (null = غير موجود).
  Future<String?> _handleCode(String code) async {
    final m = await ref.read(databaseProvider).matchBarcode(code);
    if (m == null) return 'غير موجود: $code';
    final tier = await ref.read(databaseProvider).priceForUnit(m.unit.id, 1000);
    ref.read(cartProvider.notifier).add(CartLine.of(
          itemId: m.item.id,
          name: m.item.name,
          baseCost: m.item.costPrice,
          unit: m.unit,
          unitPrice: tier,
        ));
    return 'أُضيف: ${m.item.name} (${m.unit.name})';
  }

  /// Enter في حقل البحث: لو الكود باركود صنف/وحدة يُضاف للسلة مباشرة (قارئ USB).
  Future<void> _submit(String text) async {
    final code = text.trim();
    if (code.isEmpty) return;
    final msg = await _handleCode(code);
    if (msg != null && msg.startsWith('أُضيف')) {
      _search.clear();
      if (mounted) setState(() => _q = '');
    }
  }

  Future<void> _openScanner() async {
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ScannerPage(
        title: 'مسح الأصناف',
        onCode: _handleCode,
        footer: const _ScanCartSummary(),
      ),
    ));
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو امسح الباركود',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _q = '');
                        },
                      ),
              ),
            ),
          ),
          if (canScanWithCamera) ...[
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'مسح بالكاميرا',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
                minimumSize: const Size(52, 52),
              ),
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    if (wide) {
      return Row(
        children: [
          Expanded(
            child: Column(children: [
              _searchField(),
              Expanded(child: _Results(query: _q, grid: true, onTap: _addItem)),
            ]),
          ),
          Container(
            width: 400,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFDDE5E1))),
            ),
            child: const CartPanel(),
          ),
        ],
      );
    }
    return Column(children: [
      _searchField(),
      Expanded(
        child: _q.trim().isEmpty
            ? const CartPanel()
            : _Results(
                query: _q,
                grid: false,
                onTap: (it) async {
                  await _addItem(it);
                  _search.clear();
                  if (mounted) setState(() => _q = '');
                },
              ),
      ),
    ]);
  }
}

class _Results extends ConsumerWidget {
  final String query;
  final bool grid;
  final void Function(ItemRow) onTap;
  const _Results({required this.query, required this.grid, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final res = ref.watch(itemSearchProvider(query.trim()));
    return res.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('لا توجد أصناف مطابقة'));
        }
        if (!grid) {
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(list[i].name),
              subtitle: Text(
                  'المتاح: ${formatQty(list[i].stockMilli)} ${list[i].baseUnit}'),
              trailing: Text(
                  '${formatMoney(list[i].defUnitPrice)} / ${list[i].defUnitName}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => onTap(list[i]),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 230,
            mainAxisExtent: 116,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final it = list[i];
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onTap(it),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${formatMoney(it.defUnitPrice)} / ${it.defUnitName}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary)),
                      Text('المتاح: ${formatQty(it.stockMilli)} ${it.baseUnit}',
                          style: TextStyle(
                              fontSize: 12,
                              color: it.stockMilli <= 0
                                  ? const Color(0xFFA23B2A)
                                  : Colors.black54)),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key});

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  bool _credit = false;
  String? _customerId;
  final _discount = TextEditingController();
  final _paid = TextEditingController();

  @override
  void dispose() {
    _discount.dispose();
    _paid.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  int _discountValue(int subtotal) =>
      parseMoney(_discount.text).clamp(0, subtotal).toInt();

  Future<void> _checkout({List<SalePaymentInput>? splits}) async {
    final lines = ref.read(cartProvider);
    if (lines.isEmpty) return;
    final subtotal = cartTotal(lines);
    final discount = _discountValue(subtotal);
    final total = computeVat(subtotal - discount, kVatRate,
            inclusive: kVatInclusive)
        .total;

    if (_credit && _customerId == null) {
      _snack('اختر العميل للبيع الآجل');
      return;
    }
    final paidNow =
        _credit ? parseMoney(_paid.text).clamp(0, total).toInt() : 0;

    if (_credit) {
      final customers = ref.read(customersProvider).valueOrNull ?? [];
      final c = customers.where((x) => x.id == _customerId).firstOrNull;
      if (c != null && c.creditLimit > 0) {
        final after = c.balance + (total - paidNow);
        if (after > c.creditLimit) {
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('تجاوز حد الائتمان'),
              content: Text(
                  'رصيد ${c.name} بعد هذه الفاتورة ${formatMoney(after)} وحده ${formatMoney(c.creditLimit)}. المتابعة؟'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('تراجع')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('متابعة')),
              ],
            ),
          );
          if (go != true) return;
        }
      }
    }

    final db = ref.read(databaseProvider);
    final res = await db.completeSale(
          lines: [
            for (final l in lines)
              SaleLineInput(
                itemId: l.itemId,
                unitId: l.unitId,
                qtyMilli: l.qtyMilli,
                unitPrice: l.unitPrice,
                unitCost: l.unitCost,
                factorMilli: l.factorMilli,
              ),
          ],
          credit: _credit,
          paymentSplits: splits,
          customerId: _credit ? _customerId : null,
          discount: discount,
          paidNow: paidNow,
          userId: ref.read(sessionProvider)?.id,
        );
    ref.read(cartProvider.notifier).clear();
    _discount.clear();
    _paid.clear();
    if (mounted) _snack('تم حفظ الفاتورة ${res.number}');
    ref.read(syncControllerProvider.notifier).triggerSoon();
    if (await db.getSetting('auto_print') == '1') {
      try {
        await printInvoice(db, res.id);
      } catch (e) {
        if (mounted) _snack('تعذّرت الطباعة: $e');
      }
    }
  }

  Future<void> _editQty(CartLine l) async {
    final c = TextEditingController(text: formatQty(l.qtyMilli));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('الكمية (${l.unitName})'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (_) => Navigator.pop(ctx, true),
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
    if (ok == true) {
      final qty = parseQty(c.text);
      ref.read(cartProvider.notifier).setQty(l.key, qty);
      if (qty > 0) {
        // التسعير المتدرج بيتطبّق على الكمية الجديدة.
        final db = ref.read(databaseProvider);
        final tier = await db.priceForUnit(l.unitId, qty);
        final units = await db.unitsOf(l.itemId);
        final matches = units.where((u) => u.id == l.unitId).toList();
        final base = matches.isEmpty ? null : matches.first.salePrice;
        final price = tier ?? base;
        if (price != null) {
          ref.read(cartProvider.notifier).setPrice(l.key, price);
        }
      }
    }
  }

  /// حوار الدفع المقسّم: كاش + كارت لازم يساووا الإجمالي.
  Future<List<SalePaymentInput>?> _askSplit(int total) async {
    final cash = TextEditingController();
    final card = TextEditingController();
    final result = await showDialog<List<SalePaymentInput>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final c = parseMoney(cash.text);
          final k = parseMoney(card.text);
          final remaining = total - c - k;
          return AlertDialog(
            title: Text('دفع مقسّم — ${formatMoney(total)}'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: cash,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'كاش'),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: card,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'كارت / محفظة'),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('المتبقي'),
                const Spacer(),
                Text(formatMoney(remaining < 0 ? 0 : remaining),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: remaining == 0
                            ? const Color(0xFF0B6B57)
                            : const Color(0xFFA23B2A))),
              ]),
              if (remaining != 0)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('لازم مجموع الدفعتين يساوي الإجمالي',
                      style:
                          TextStyle(fontSize: 12, color: Color(0xFFA23B2A))),
                ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(
                onPressed: remaining != 0
                    ? null
                    : () => Navigator.pop(ctx, <SalePaymentInput>[
                          if (c > 0)
                            SalePaymentInput(method: 'cash', amount: c),
                          if (k > 0)
                            SalePaymentInput(method: 'card', amount: k),
                        ]),
                child: const Text('تأكيد'),
              ),
            ],
          );
        },
      ),
    );
    cash.dispose();
    card.dispose();
    return result;
  }

  Future<void> _quickAddCustomer() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('عميل جديد'),
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
      final id = await ref.read(databaseProvider).addCustomer(
          name: name.text.trim(), phone: phone.text.trim());
      if (mounted) setState(() => _customerId = id);
    }
  }

  void _hold() {
    final lines = ref.read(cartProvider);
    if (lines.isEmpty) return;
    ref.read(heldCartsProvider.notifier).hold(lines);
    ref.read(cartProvider.notifier).clear();
    _discount.clear();
    _paid.clear();
    _snack('تم تعليق الفاتورة');
  }

  void _showHeld() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final held = ref.watch(heldCartsProvider);
        if (held.isEmpty) {
          return const SizedBox(
              height: 120, child: Center(child: Text('لا توجد فواتير معلّقة')));
        }
        return ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < held.length; i++)
              ListTile(
                title: Text(held[i].label),
                subtitle: Text(
                    '${held[i].lines.length} أصناف · ${formatMoney(cartTotal(held[i].lines))}'),
                onTap: () {
                  if (ref.read(cartProvider).isNotEmpty) {
                    _snack('أتمم الفاتورة الحالية أو علّقها أولًا');
                    return;
                  }
                  ref.read(cartProvider.notifier).replaceAll(held[i].lines);
                  ref.read(heldCartsProvider.notifier).removeAt(i);
                  Navigator.pop(ctx);
                },
                trailing: IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      ref.read(heldCartsProvider.notifier).removeAt(i),
                ),
              ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider);
    final held = ref.watch(heldCartsProvider);
    final subtotal = cartTotal(lines);
    final discount = _discountValue(subtotal);
    final total = computeVat(subtotal - discount, kVatRate,
            inclusive: kVatInclusive)
        .total;
    return Column(children: [
      Expanded(
        child: lines.isEmpty
            ? const Center(child: Text('السلة فارغة'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: lines.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _CartLineTile(
                  line: lines[i],
                  onEditQty: () => _editQty(lines[i]),
                ),
              ),
      ),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFDDE5E1))),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: lines.isEmpty ? null : _hold,
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('تعليق'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showHeld,
                icon: const Icon(Icons.history),
                label: Text('المعلّقة (${held.length})'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Text('الخصم'),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _discount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    isDense: true, hintText: '0'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('الإجمالي'),
            Text(formatMoney(total),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('كاش')),
                ButtonSegment(value: true, label: Text('آجل')),
              ],
              selected: {_credit},
              onSelectionChanged: (s) => setState(() => _credit = s.first),
            ),
          ),
          if (_credit) ...[
            const SizedBox(height: 10),
            Consumer(builder: (context, ref, _) {
              final customers = ref.watch(customersProvider).valueOrNull ?? [];
              final selected =
                  customers.any((c) => c.id == _customerId) ? _customerId : null;
              return Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'العميل'),
                    items: [
                      for (final c in customers)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _customerId = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'عميل جديد',
                  onPressed: _quickAddCustomer,
                  icon: const Icon(Icons.person_add_alt),
                ),
              ]);
            }),
            const SizedBox(height: 10),
            TextField(
              controller: _paid,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'المدفوع الآن (اختياري)', isDense: true),
            ),
          ],
          if (!_credit && lines.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final s = await _askSplit(total);
                  if (s == null) return;
                  await _checkout(splits: s);
                },
                icon: const Icon(Icons.call_split),
                label: const Text('دفع مقسّم (كاش + كارت)'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
              ),
              onPressed: lines.isEmpty ? null : () => _checkout(),
              child: const Text('إتمام البيع',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _CartLineTile extends ConsumerWidget {
  final CartLine line;
  final VoidCallback onEditQty;
  const _CartLineTile({required this.line, required this.onEditQty});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartProvider.notifier);
    final units = ref.watch(itemUnitsProvider(line.itemId)).valueOrNull ?? const [];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text(line.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text(formatMoney(line.total),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          if (units.length > 1)
            PopupMenuButton<ItemUnit>(
              tooltip: 'تغيير الوحدة',
              onSelected: (u) => cart.switchUnit(line.key, u),
              itemBuilder: (_) => [
                for (final u in units)
                  PopupMenuItem(
                      value: u,
                      child: Text('${u.name} — ${formatMoney(u.salePrice)}')),
              ],
              child: Chip(
                label: Text('${line.unitName}  ▾'),
                visualDensity: VisualDensity.compact,
              ),
            )
          else
            Text(line.unitName,
                style: const TextStyle(color: Colors.black54)),
          const SizedBox(width: 8),
          Text(formatMoney(line.unitPrice),
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const Spacer(),
          IconButton.outlined(
            tooltip: 'إنقاص',
            onPressed: () => cart.change(line.key, -1000),
            icon: const Icon(Icons.remove),
          ),
          InkWell(
            onTap: onEditQty,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44),
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: Text(formatQty(line.qtyMilli),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline)),
            ),
          ),
          IconButton.filled(
            tooltip: 'زيادة',
            onPressed: () => cart.change(line.key, 1000),
            icon: const Icon(Icons.add),
          ),
        ]),
      ]),
    );
  }
}

/// ملخص السلة داخل شاشة المسح بالكاميرا.
class _ScanCartSummary extends ConsumerWidget {
  const _ScanCartSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartProvider);
    return Text(
      'السلة: ${lines.length} بند · ${formatMoney(cartTotal(lines))}',
      style: const TextStyle(color: Colors.black54),
    );
  }
}
