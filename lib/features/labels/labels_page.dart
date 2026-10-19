import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/printing/print_service.dart';
import '../../data/database.dart';
import '../../data/providers.dart';

/// طباعة ملصقات باركود للأصناف (يولّد باركودًا داخليًا للأصناف التي ليس لها).
class LabelsPage extends ConsumerStatefulWidget {
  const LabelsPage({super.key});
  @override
  ConsumerState<LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends ConsumerState<LabelsPage> {
  final Map<String, int> _copies = {}; // itemId → عدد النسخ
  String _q = '';
  String _size = 'l4030';
  bool _busy = false;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run({required bool share}) async {
    if (_copies.isEmpty) {
      _snack('اختر صنفًا واحدًا على الأقل');
      return;
    }
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      final all = await db.watchItems('').first;
      final specs = <LabelSpec>[];
      for (final it in all) {
        final n = _copies[it.id];
        if (n == null || n <= 0) continue;
        final unit = await db.defaultUnit(it.id);
        final code = await db.ensureBarcode(it.id, unit.id);
        specs.add(LabelSpec(it.name, unit.name, unit.salePrice, code, n));
      }
      final shop = await loadShopInfo(db);
      final bytes = await buildLabelsPdf(specs, _size, shop.name);
      if (share) {
        await sharePdf(bytes, 'labels.pdf');
      } else {
        final size = labelSizes[_size]!;
        await printPdf(bytes, 'ملصقات باركود',
            format: _size == 'a4'
                ? null
                : PdfPageFormat(size.w * PdfPageFormat.mm, size.h * PdfPageFormat.mm));
      }
    } catch (e) {
      _snack('تعذّر إنشاء الملصقات: ${e is StateError ? e.message : e}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemSearchProvider(_q.trim()));
    final total = _copies.values.fold<int>(0, (s, n) => s + n);
    return Scaffold(
      appBar: AppBar(title: const Text('طباعة ملصقات الباركود')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
                hintText: 'ابحث عن صنف', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Expanded(
          child: items.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('خطأ: $e')),
            data: (list) => list.isEmpty
                ? const Center(child: Text('لا توجد أصناف'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => _row(list[i]),
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
            DropdownButtonFormField<String>(
              value: _size,
              decoration: const InputDecoration(labelText: 'مقاس الملصق'),
              items: [
                for (final e in labelSizes.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value.label)),
              ],
              onChanged: (v) => setState(() => _size = v ?? 'l4030'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _run(share: false),
                  icon: const Icon(Icons.print),
                  label: Text('طباعة ($total ملصق)'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(share: true),
                icon: const Icon(Icons.ios_share),
                label: const Text('PDF'),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _row(ItemRow it) {
    final n = _copies[it.id] ?? 0;
    return ListTile(
      title: Text(it.name),
      subtitle: Text('${formatMoney(it.defUnitPrice)} / ${it.defUnitName}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'إنقاص',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: n == 0
              ? null
              : () => setState(() {
                    if (n <= 1) {
                      _copies.remove(it.id);
                    } else {
                      _copies[it.id] = n - 1;
                    }
                  }),
        ),
        SizedBox(
            width: 28,
            child: Text('$n',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800))),
        IconButton(
          tooltip: 'زيادة',
          icon: const Icon(Icons.add_circle),
          onPressed: () => setState(() => _copies[it.id] = n + 1),
        ),
      ]),
    );
  }
}
