import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';

/// الوردية المفتوحة حاليًا (null = مفيش وردية).
final currentShiftProvider = StreamProvider<Shift?>(
    (ref) => ref.watch(databaseProvider).watchCurrentShift());

/// ملخّص الأرقام لوردية معيّنة.
final shiftSummaryProvider = FutureProvider.family<ShiftSummary, String>(
    (ref, id) => ref.watch(databaseProvider).shiftSummary(id));

/// فواتير وردية معيّنة.
final shiftSalesProvider = StreamProvider.family<List<SaleRow>, String>(
    (ref, id) => ref.watch(databaseProvider).watchShiftSales(id));

/// شاشة الوردية: فتح وردية، متابعة الأرقام لحظيًا، ثم تقفيلها بتقرير Z.
class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});
  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
  final _opening = TextEditingController();
  final _counted = TextEditingController();
  bool _busy = false;
  ShiftSummary? _lastClosed;

  @override
  void dispose() {
    _opening.dispose();
    _counted.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openShift(SessionUser? user) async {
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(databaseProvider).openShift(
            userId: user.id,
            openingCash: parseMoney(_opening.text),
          );
      _opening.clear();
      setState(() => _lastClosed = null);
      _toast('تم فتح الوردية');
    } catch (e) {
      _toast(e is StateError ? e.message : 'تعذر فتح الوردية');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeShift(Shift shift, ShiftSummary summary) async {
    _counted.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final counted = parseMoney(_counted.text);
          final diff = counted - summary.expectedCash;
          final diffColor = diff == 0
              ? const Color(0xFF0B6B57)
              : (diff < 0 ? const Color(0xFFA23B2A) : const Color(0xFFB8860B));
          return AlertDialog(
            title: Text('تقفيل الوردية ${shift.number}'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              _row('النقد المتوقع', formatMoney(summary.expectedCash)),
              const SizedBox(height: 10),
              TextField(
                controller: _counted,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'النقد المعدود فعليًا في الدرج'),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: 12),
              _row('الفرق', formatMoney(diff), color: diffColor),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('تأكيد التقفيل')),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final closed = await ref
          .read(databaseProvider)
          .closeShift(shiftId: shift.id, countedCash: parseMoney(_counted.text));
      setState(() => _lastClosed = closed);
      _toast('تم تقفيل الوردية');
    } catch (e) {
      _toast(e is StateError ? e.message : 'تعذر تقفيل الوردية');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.black54))),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentShiftProvider);
    final session = ref.watch(sessionProvider);

    return current.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('تعذر تحميل الوردية\n$e')),
      data: (shift) {
        if (shift == null) {
          final closed = _lastClosed;
          if (closed != null) return _closedReport(closed);
          return _openForm(session);
        }
        return _liveView(shift, session);
      },
    );
  }

  Widget _card(List<Widget> children) => Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children)),
      );

  Widget _openForm(SessionUser? user) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card([
            const Text('مفيش وردية مفتوحة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'افتح وردية أول ما تبدأ الشغل وحطّ النقدية اللي في الدرج. '
                'كل فاتورة بعد كده بتتحسب على الوردية دي، ولما تقفل هتعرف الفرق.',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 14),
            TextField(
              controller: _opening,
              decoration: const InputDecoration(
                  labelText: 'النقدية الافتتاحية في الدرج'),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy || user == null ? null : () => _openShift(user),
              icon: const Icon(Icons.lock_open),
              label: const Text('فتح وردية'),
            ),
          ]),
        ],
      );

  Widget _liveView(Shift shift, SessionUser? user) {
    final summary = ref.watch(shiftSummaryProvider(shift.id));
    final sales = ref.watch(shiftSalesProvider(shift.id));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card([
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: kGreen, borderRadius: BorderRadius.circular(8)),
              child: Text('وردية ${shift.number}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            Text('من ${formatDateTime(shift.openedAt)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
          const SizedBox(height: 12),
          summary.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('تعذر حساب الأرقام: $e'),
            data: (s) => Column(children: [
              _row('الكاشير', user?.name ?? shift.userId),
              _row('النقدية الافتتاحية', formatMoney(s.shift.openingCash)),
              _row('مبيعات كاش', formatMoney(s.cashSales)),
              _row('مبيعات آجل', formatMoney(s.creditSales)),
              _row('عدد الفواتير', '${s.salesCount}'),
              _row('مرتجعات كاش', formatMoney(s.cashReturns)),
              _row('تحصيل دفعات', formatMoney(s.cashPaymentsIn)),
              _row('مدفوعات خارجة', formatMoney(s.cashPaymentsOut)),
              const Divider(height: 22),
              _row('المتوقع في الدرج', formatMoney(s.expectedCash),
                  color: kGreen),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : () => _closeShift(shift, s),
                icon: const Icon(Icons.lock_outline),
                label: const Text('تقفيل الوردية'),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        _card([
          const Text('فواتير الوردية',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          sales.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (rows) => rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('مفيش فواتير في الوردية دي بعد',
                        style: TextStyle(color: Colors.black54)),
                  )
                : Column(
                    children: [
                      for (final r in rows)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.number),
                          subtitle: Text(
                              '${r.type == 'credit' ? 'آجل' : 'كاش'} · ${formatDateTime(r.soldAt)}'),
                          trailing: Text(formatMoney(r.total),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
          ),
        ]),
      ],
    );
  }

  Widget _closedReport(ShiftSummary s) {
    final diff = s.shift.difference ?? 0;
    final diffColor = diff == 0
        ? kGreen
        : (diff < 0 ? const Color(0xFFA23B2A) : const Color(0xFFB8860B));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card([
          Text('تقرير Z — وردية ${s.shift.number}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('الوردية مقفولة',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const Divider(height: 22),
          _row('النقدية الافتتاحية', formatMoney(s.shift.openingCash)),
          _row('مبيعات كاش', formatMoney(s.cashSales)),
          _row('مبيعات آجل', formatMoney(s.creditSales)),
          _row('عدد الفواتير', '${s.salesCount}'),
          _row('مرتجعات كاش', formatMoney(s.cashReturns)),
          _row('تحصيل دفعات', formatMoney(s.cashPaymentsIn)),
          _row('مدفوعات خارجة', formatMoney(s.cashPaymentsOut)),
          const Divider(height: 22),
          _row('المتوقع', formatMoney(s.expectedCash)),
          _row('المعدود', formatMoney(s.shift.countedCash ?? 0)),
          _row('الفرق', formatMoney(diff), color: diffColor),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => setState(() => _lastClosed = null),
            icon: const Icon(Icons.add),
            label: const Text('فتح وردية جديدة'),
          ),
        ]),
      ],
    );
  }
}