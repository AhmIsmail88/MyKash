import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';
import '../scanning/scanner_page.dart';

class _Entry {
  final ItemRow item;
  final TextEditingController counted;
  _Entry(this.item, int startMilli)
      : counted = TextEditingController(text: formatQty(startMilli));
  int get countedMilli => parseQty(counted.text);
  int get diff => countedMilli - item.stockMilli;
}

/// الجرد (للمدير): امسح/اختر الأصناف، اكتب الكمية الفعلية، ثم اعتمد التسوية.
/// كل مسح يزيد الكمية بوحدة المسح (مسح باركود كيس 25 كجم يضيف 25 كجم).
class CountScreen extends ConsumerStatefulWidget {
  const CountScreen({super.key});
  @override
  ConsumerState<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends ConsumerState<CountScreen> {
  final Map<String, _Entry> _entries = {};
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    for (final e in _entries.values) {
      e.counted.dispose();
    }
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _add(ItemRow it, {int addMilli = 0}) {
    setState(() {
      final e = _entries[it.id];
      if (e == null) {
        _entries[it.id] = _Entry(it, addMilli);
      } else if (addMilli > 0) {
        e.counted.text = formatQty(e.countedMilli + addMilli);
      }
      _search.clear();
      _q = '';
    });
  }

  Future<String?> _handleCode(String code) async {
    final db = ref.read(databaseProvider);
    final m = await db.matchBarcode(code);
    if (m == null) return 'غير موجود: $code';
    final row = await db.itemRowById(m.item.id);
    if (row == null) return 'غير موجود: $code';
    _add(row, addMilli: m.unit.factorMilli);
    return 'عُدّ: ${m.item.name} (+${formatQty(m.unit.factorMilli)} ${row.baseUnit})';
  }

  Future<void> _submitSearch(String text) async {
    final code = text.trim();
    if (code.isEmpty) return;
    final msg = await _handleCode(code);
    if (msg != null && !msg.startsWith('غير')) _snack(msg);
  }

  Future<void> _openScanner() async {
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ScannerPage(title: 'جرد بالمسح', onCode: _handleCode),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _apply() async {
    final changed = _entries.values.where((e) => e.diff != 0).toList();
    if (changed.isEmpty) {
      _snack('لا توجد فروق لتسويتها');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اعتماد الجرد'),
        content: Text(
            'سيتم تسوية مخزون ${changed.length} صنف بحركات جرد. لا يمكن التراجع تلقائيًا.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('اعتماد')),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    final uid = ref.read(sessionProvider)?.id;
    for (final e in changed) {
      await db.adjustStockTo(e.item.id, e.countedMilli, userId: uid);
    }
    if (!mounted) return;
    setState(() {
      for (final e in _entries.values) {
        e.counted.dispose();
      }
      _entries.clear();
    });
    _snack('تم اعتماد الجرد');
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(sessionProvider)?.isAdmin ?? false;
    if (!isAdmin) return const Center(child: Text('هذه الشاشة للمدير فقط'));
    return Column(children: [
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
            IconButton.filled(
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
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('خطأ: $e')),
                  data: (list) => ListView(children: [
                    for (final it in list)
                      ListTile(
                        title: Text(it.name),
                        subtitle: Text(
                            'بالنظام: ${formatQty(it.stockMilli)} ${it.baseUnit}'),
                        onTap: () => _add(it),
                      ),
                  ]),
                );
              })
            : _entries.isEmpty
                ? const Center(
                    child: Text('أضف الأصناف التي تجردها بالبحث أو المسح'))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final e in _entries.values) _tile(e),
                    ],
                  ),
      ),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFDDE5E1))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _entries.isEmpty ? null : _apply,
            child: const Text('اعتماد الجرد وتسوية المخزون',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    ]);
  }

  Widget _tile(_Entry e) {
    final diff = e.diff;
    final color = diff == 0
        ? Colors.black54
        : (diff > 0 ? const Color(0xFF0B6B57) : const Color(0xFFA23B2A));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('بالنظام: ${formatQty(e.item.stockMilli)} ${e.item.baseUnit}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Text(
                  diff == 0
                      ? 'مطابق'
                      : 'الفرق: ${diff > 0 ? "+" : ""}${formatQty(diff)} ${e.item.baseUnit}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: e.counted,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'الفعلي', isDense: true),
            ),
          ),
          IconButton(
            tooltip: 'إزالة',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _entries.remove(e.item.id)?.counted.dispose();
            }),
          ),
        ]),
      ),
    );
  }
}
