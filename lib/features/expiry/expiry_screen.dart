import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/providers.dart';

/// الأصناف القريبة من الانتهاء، حسب عدد أيام التحذير في الإعدادات.
final expiringProvider = FutureProvider<List<ExpiringItem>>((ref) async {
  final db = ref.watch(databaseProvider);
  final days =
      int.tryParse(await db.getSetting('expiry_warning_days') ?? '') ?? 30;
  return db.expiringItems(withinDays: days);
});

/// شاشة تنبيهات الصلاحية.
class ExpiryScreen extends ConsumerWidget {
  const ExpiryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(expiringProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('تعذر تحميل التنبيهات\n$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'مفيش أصناف قاربت على الانتهاء.\n'
                'التنبيهات بتظهر للأصناف اللي عليها تاريخ صلاحية ومخزونها لسه موجود.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = rows[i];
            final days = r.daysLeft();
            final color = days < 0
                ? const Color(0xFFA23B2A)
                : (days <= 7 ? const Color(0xFFB8860B) : kGreen);
            final label = days < 0
                ? 'منتهي من ${-days} يوم'
                : (days == 0 ? 'ينتهي اليوم' : 'باقي $days يوم');
            return ListTile(
              title: Text(r.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${formatDateTime(r.expiryDate)} · المخزون ${formatQty(r.stockMilli)}'),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
            );
          },
        );
      },
    );
  }
}
