import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/providers.dart';
import '../auth/session.dart';
import '../labels/labels_page.dart';
import 'item_editor.dart';

/// المدير: إضافة وتعديل الأصناف والوحدات والباركودات وتسوية المخزون وطباعة الملصقات.
/// الكاشير: عرض فقط بدون تكلفة.
class ItemsScreen extends ConsumerWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(sessionProvider)?.isAdmin ?? false;
    final items = ref.watch(itemSearchProvider(''));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _addDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('صنف جديد'),
            )
          : null,
      body: Column(children: [
        if (isAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                      fullscreenDialog: true, builder: (_) => const LabelsPage()),
                ),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('طباعة ملصقات باركود'),
              ),
            ),
          ),
        Expanded(
          child: items.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('خطأ: $e')),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                    child: Text(isAdmin
                        ? 'لا توجد أصناف بعد. أضف أول صنف.'
                        : 'لا توجد أصناف بعد.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final it = list[i];
                  final low = it.stockMilli <= 0;
                  return Card(
                    child: ListTile(
                      onTap: isAdmin ? () => showItemEditor(context, ref, it) : null,
                      title: Text(it.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(isAdmin
                          ? '${formatMoney(it.salePrice)} لكل ${it.baseUnit} · التكلفة: ${formatMoney(it.costPrice)}'
                          : '${formatMoney(it.defUnitPrice)} / ${it.defUnitName}'),
                      trailing: Text(
                        'المخزون: ${formatQty(it.stockMilli)} ${it.baseUnit}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: low ? const Color(0xFFA23B2A) : null),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType:
              number ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final unit = TextEditingController(text: 'قطعة');
    final price = TextEditingController();
    final cost = TextEditingController();
    final barcode = TextEditingController();
    final qty = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('صنف جديد'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(name, 'اسم الصنف'),
              _field(unit, 'الوحدة الأساسية (كجم، قطعة، لتر...)'),
              _field(price, 'سعر بيع الوحدة الأساسية', number: true),
              _field(cost, 'تكلفة الوحدة الأساسية (اختياري)', number: true),
              scanField(ctx, barcode, 'الباركود (اختياري)'),
              _field(qty, 'الكمية الافتتاحية (اختياري)', number: true),
              const Text('يمكن إضافة وحدات أخرى (كيس، طن...) بعد الحفظ من تعديل الصنف.',
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
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && parseMoney(price.text) > 0) {
      try {
        await ref.read(databaseProvider).addItem(
              name: name.text.trim(),
              salePrice: parseMoney(price.text),
              costPrice: parseMoney(cost.text),
              barcode: barcode.text,
              openingQtyMilli: parseQty(qty.text),
              unitName: unit.text,
            );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(e is StateError ? e.message : '$e')));
        }
      }
    }
  }
}
