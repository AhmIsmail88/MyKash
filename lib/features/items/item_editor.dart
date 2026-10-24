import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';
import '../scanning/scanner_page.dart';

String _err(Object e) => e is StateError ? e.message : '$e';

/// حقل نص مع زر مسح بالكاميرا (على الموبايل فقط).
Widget scanField(BuildContext ctx, TextEditingController c, String label) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          child: TextField(
              controller: c, decoration: InputDecoration(labelText: label)),
        ),
        if (canScanWithCamera)
          IconButton(
            tooltip: 'مسح',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final code = await scanOnce(ctx);
              if (code != null) c.text = code;
            },
          ),
      ]),
    );

/// محرّر الصنف للمدير: البيانات الأساسية + تسوية الكمية + الوحدات والباركودات.
Future<void> showItemEditor(
    BuildContext context, WidgetRef ref, ItemRow it) async {
  final db = ref.read(databaseProvider);
  final name = TextEditingController(text: it.name);
  final baseUnit = TextEditingController(text: it.baseUnit);
  final price = TextEditingController(text: moneyInput(it.salePrice));
  final cost = TextEditingController(text: moneyInput(it.costPrice));
  final qty = TextEditingController(text: formatQty(it.stockMilli));
  final reorder = TextEditingController(
      text: it.reorderMilli > 0 ? formatQty(it.reorderMilli) : '');

  Future<(List<ItemUnit>, List<ItemBarcode>)> load() async =>
      (await db.unitsOf(it.id), await db.barcodesOf(it.id));
  var future = load();

  void snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget field(TextEditingController c, String label, {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType:
              number ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Future<void> addUnitDialog(BuildContext ctx) async {
    final uName = TextEditingController();
    final factor = TextEditingController();
    final uPrice = TextEditingController();
    final barcode = TextEditingController();
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c2) => AlertDialog(
        title: const Text('وحدة جديدة'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              field(uName, 'اسم الوحدة (مثل: كيس، طن، كرتونة)'),
              field(factor,
                  'كم ${baseUnit.text.trim().isEmpty ? "وحدة أساسية" : baseUnit.text.trim()} في هذه الوحدة؟ (مثال: 25)',
                  number: true),
              field(uPrice, 'سعر بيع هذه الوحدة', number: true),
              scanField(c2, barcode, 'باركود هذه الوحدة (اختياري)'),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c2, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(c2, true),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (ok != true) return;
    if (uName.text.trim().isEmpty || parseMoney(uPrice.text) <= 0) {
      snack('اكتب اسم الوحدة وسعرها');
      return;
    }
    try {
      await db.addUnit(
        itemId: it.id,
        name: uName.text.trim(),
        factorMilli: parseQty(factor.text),
        salePrice: parseMoney(uPrice.text),
        barcode: barcode.text,
      );
    } catch (e) {
      snack(_err(e));
    }
  }

  Future<void> bindBarcodeDialog(BuildContext ctx, ItemUnit u) async {
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c2) => AlertDialog(
        title: Text('ربط باركود بوحدة ${u.name}'),
        content: SizedBox(
          width: 360,
          child: scanField(c2, code, 'الباركود (امسحه أو اكتبه)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c2, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(c2, true),
              child: const Text('ربط')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.addBarcode(itemId: it.id, unitId: u.id, code: code.text);
    } catch (e) {
      snack(_err(e));
    }
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      void refresh() => setD(() {
            future = load();
          });
      return AlertDialog(
        title: const Text('تعديل الصنف'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              field(name, 'اسم الصنف'),
              field(baseUnit, 'اسم الوحدة الأساسية (مثل: كجم، قطعة)'),
              field(price, 'سعر بيع الوحدة الأساسية', number: true),
              field(cost, 'تكلفة الوحدة الأساسية', number: true),
              field(qty, 'الكمية الفعلية بالوحدة الأساسية (تسوية/جرد)',
                  number: true),
              field(reorder, 'حد إعادة الطلب (تنبيه النواقص، اختياري)',
                  number: true),
              const Divider(),
              Row(children: [
                const Expanded(
                  child: Text('الوحدات والباركودات',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await addUnitDialog(ctx);
                    refresh();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('وحدة'),
                ),
              ]),
              FutureBuilder<(List<ItemUnit>, List<ItemBarcode>)>(
                future: future,
                builder: (_, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator());
                  }
                  final (units, barcodes) = snap.data!;
                  return Column(children: [
                    for (final u in units)
                      _unitTile(ctx, db, it, u, barcodes, baseUnit.text.trim(),
                          refresh, snack, bindBarcodeDialog),
                  ]);
                },
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إغلاق')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ البيانات')),
        ],
      );
    }),
  );

  if (ok == true && name.text.trim().isNotEmpty && parseMoney(price.text) > 0) {
    final newQty = parseQty(qty.text);
    try {
      await db.updateItem(
        id: it.id,
        name: name.text.trim(),
        salePrice: parseMoney(price.text),
        costPrice: parseMoney(cost.text),
        newStockMilli: newQty == it.stockMilli ? null : newQty,
        baseUnitName: baseUnit.text,
        reorderMilli: parseQty(reorder.text),
        userId: ref.read(sessionProvider)?.id,
      );
    } catch (e) {
      snack(_err(e));
    }
  }
}

Widget _unitTile(
  BuildContext ctx,
  AppDatabase db,
  ItemRow it,
  ItemUnit u,
  List<ItemBarcode> barcodes,
  String baseName,
  void Function() refresh,
  void Function(String) snack,
  Future<void> Function(BuildContext, ItemUnit) bind,
) {
  final mine = barcodes
      .where((b) => b.unitId == u.id || (b.unitId == null && u.isDefault))
      .toList();
  return Column(children: [
    ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(u.factorMilli == 1000
          ? 'الوحدة الأساسية'
          : '1 ${u.name} = ${formatQty(u.factorMilli)} $baseName · ${formatMoney(u.salePrice)}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'ربط باركود',
          icon: const Icon(Icons.qr_code_2),
          onPressed: () async {
            await bind(ctx, u);
            refresh();
          },
        ),
        IconButton(
          tooltip: 'أسعار متدرجة',
          icon: const Icon(Icons.trending_down),
          onPressed: () async {
            await _editTiers(ctx, db, u, snack);
            refresh();
          },
        ),
        IconButton(
          tooltip: 'وحدة البيع الافتراضية',
          icon: Icon(u.isDefault ? Icons.star : Icons.star_border,
              color: u.isDefault ? const Color(0xFFF2A71B) : null),
          onPressed: () async {
            await db.setDefaultUnit(it.id, u.id);
            refresh();
          },
        ),
        if (u.factorMilli != 1000)
          IconButton(
            tooltip: 'حذف الوحدة',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              try {
                await db.deleteUnit(u.id);
              } catch (e) {
                snack(_err(e));
              }
              refresh();
            },
          ),
      ]),
    ),
    if (mine.isNotEmpty)
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final b in mine)
              InputChip(
                label: Text(b.code, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onDeleted: () async {
                  await db.removeBarcode(b.id);
                  refresh();
                },
              ),
          ]),
        ),
      ),
  ]);
}
/// محرّر الأسعار المتدرجة لوحدة: كل صف = أقل كمية + سعر الوحدة عندها.
Future<void> _editTiers(
  BuildContext ctx,
  AppDatabase db,
  ItemUnit u,
  void Function(String) snack,
) async {
  final existing = await db.tiersForUnit(u.id);
  final rows = <({TextEditingController minQty, TextEditingController price})>[
    for (final r in existing)
      (
        minQty: TextEditingController(text: formatQty(r.minQtyMilli)),
        price: TextEditingController(text: moneyInput(r.unitPrice)),
      ),
  ];

  if (!ctx.mounted) return;
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (c) => StatefulBuilder(
      builder: (c, setLocal) => AlertDialog(
        title: Text('أسعار متدرجة — ${u.name}'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'كل صف: أقل كمية يبدأ عندها السعر الجديد. الكميات الأقل من أول حد بتفضل على سعر الوحدة.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: [
                  for (var i = 0; i < rows.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: rows[i].minQty,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'من كمية', isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: rows[i].price,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'سعر الوحدة', isDense: true),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setLocal(() => rows.removeAt(i)),
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
            TextButton.icon(
              onPressed: () => setLocal(() => rows.add((
                    minQty: TextEditingController(),
                    price: TextEditingController(),
                  ))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة فئة'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حفظ')),
        ],
      ),
    ),
  );

  if (ok == true) {
    await db.saveTiersForUnit(u.id, [
      for (final r in rows)
        if (parseQty(r.minQty.text) > 0 && parseMoney(r.price.text) > 0)
          PriceTierInput(
            minQtyMilli: parseQty(r.minQty.text),
            unitPrice: parseMoney(r.price.text),
          ),
    ]);
    snack('تم حفظ الأسعار المتدرجة');
  }
}