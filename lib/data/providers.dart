import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('يُحقن من main.dart'),
);

final itemSearchProvider =
    StreamProvider.family<List<ItemRow>, String>((ref, query) {
  return ref.watch(databaseProvider).watchItems(query);
});

final customersProvider = StreamProvider<List<CustomerRow>>((ref) {
  return ref.watch(databaseProvider).watchCustomers();
});

/// المستخدمون النشطون (شاشة الدخول).
final usersProvider = StreamProvider<List<User>>((ref) {
  return ref.watch(databaseProvider).watchUsers();
});

/// كل المستخدمين بما فيهم الموقوفون (شاشة الإعدادات).
final allUsersProvider = StreamProvider.autoDispose<List<User>>((ref) {
  return ref.watch(databaseProvider).watchUsers(onlyActive: false);
});

final hasUsersProvider = FutureProvider<bool>((ref) {
  return ref.watch(databaseProvider).hasUsers();
});

/// المعامل: (نص البحث، الفلتر all|cash|credit|cancelled)
final salesListProvider =
    StreamProvider.autoDispose.family<List<SaleRow>, (String, String)>((ref, a) {
  return ref.watch(databaseProvider).watchSales(a.$1, a.$2);
});

/// وحدات صنف معيّن (للاختيار داخل السلة).
final itemUnitsProvider =
    StreamProvider.autoDispose.family<List<ItemUnit>, String>((ref, itemId) {
  return ref.watch(databaseProvider).watchUnits(itemId);
});

final suppliersProvider = StreamProvider<List<SupplierRow>>((ref) {
  return ref.watch(databaseProvider).watchSuppliers();
});

final purchasesProvider = StreamProvider.autoDispose<List<PurchaseRow>>((ref) {
  return ref.watch(databaseProvider).watchPurchases();
});

/// المعامل: (من، إلى) بالملي ثانية.
final reportProvider =
    FutureProvider.autoDispose.family<ReportData, (int, int)>((ref, r) {
  return ref.watch(databaseProvider).report(r.$1, r.$2);
});
