import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/providers.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('عميل جديد'),
      ),
      body: customers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('لا يوجد عملاء بعد.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = list[i];
              final sub = [
                c.phone,
                c.address,
                if (c.creditLimit > 0) 'الحد: ${formatMoney(c.creditLimit)}',
              ].where((e) => e != null && e.isNotEmpty).join(' · ');
              final over = c.creditLimit > 0 && c.balance > c.creditLimit;
              return Card(
                child: ListTile(
                  title: Text(c.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: sub.isEmpty ? null : Text(sub),
                  trailing: c.balance == 0
                      ? null
                      : Text('عليه: ${formatMoney(c.balance)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: over
                                  ? const Color(0xFFA23B2A)
                                  : const Color(0xFF8A5A00))),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final limit = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('عميل جديد'),
        content: SingleChildScrollView(
          child: SizedBox(
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
              const SizedBox(height: 10),
              TextField(
                  controller: limit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'حد الائتمان (اختياري، 0 = بدون حد)')),
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
    if (ok == true && name.text.trim().isNotEmpty) {
      await ref.read(databaseProvider).addCustomer(
            name: name.text.trim(),
            phone: phone.text.trim(),
            address: address.text.trim(),
            creditLimit: parseMoney(limit.text),
          );
    }
  }
}
