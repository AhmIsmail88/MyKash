import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';

/// سطر في السلة: صنف + وحدة (كيس/كيلو...) + كمية بتلك الوحدة.
class CartLine {
  final String itemId, unitId, unitName, name;
  /// عدد الوحدات الأساسية في هذه الوحدة ×1000.
  final int factorMilli;
  final int unitPrice, baseCost, qtyMilli;
  const CartLine({
    required this.itemId,
    required this.unitId,
    required this.unitName,
    required this.name,
    required this.factorMilli,
    required this.unitPrice,
    required this.baseCost,
    required this.qtyMilli,
  });

  factory CartLine.of({
    required String itemId,
    required String name,
    required int baseCost,
    required ItemUnit unit,
    int qtyMilli = 1000,
    int? unitPrice,
  }) =>
      CartLine(
        itemId: itemId,
        unitId: unit.id,
        unitName: unit.name,
        name: name,
        factorMilli: unit.factorMilli,
        unitPrice: unitPrice ?? unit.salePrice,
        baseCost: baseCost,
        qtyMilli: qtyMilli,
      );

  String get key => '$itemId|$unitId';

  /// تكلفة الوحدة = تكلفة الوحدة الأساسية × عامل التحويل.
  int get unitCost => (baseCost * factorMilli / 1000).round();
  int get total => (unitPrice * qtyMilli / 1000).round();

  /// نسخة بسعر وحدة مختلف (يستخدمها التسعير المتدرج).
  CartLine withPrice(int price) => CartLine(
        itemId: itemId,
        unitId: unitId,
        unitName: unitName,
        name: name,
        factorMilli: factorMilli,
        unitPrice: price,
        baseCost: baseCost,
        qtyMilli: qtyMilli,
      );

  CartLine withQty(int q) => CartLine(
        itemId: itemId,
        unitId: unitId,
        unitName: unitName,
        name: name,
        factorMilli: factorMilli,
        unitPrice: unitPrice,
        baseCost: baseCost,
        qtyMilli: q,
      );
}

class CartNotifier extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => const [];

  /// يضيف سطرًا؛ لو نفس الصنف والوحدة موجودين تُجمع الكمية.
  void add(CartLine line) {
    final i = state.indexWhere((l) => l.key == line.key);
    if (i < 0) {
      state = [...state, line];
    } else {
      change(line.key, line.qtyMilli);
    }
  }

  /// يزيد/ينقص الكمية؛ وإذا وصلت للصفر يُحذف السطر.
  void change(String key, int deltaMilli) {
    state = [
      for (final l in state)
        if (l.key == key)
          if (l.qtyMilli + deltaMilli > 0) l.withQty(l.qtyMilli + deltaMilli) else ...[]
        else
          l,
    ];
  }

  /// يحدّث سعر الوحدة لسطر موجود (تسعير متدرج حسب الكمية).
  void setPrice(String key, int unitPrice) {
    state = [
      for (final l in state) l.key == key ? l.withPrice(unitPrice) : l,
    ];
  }

  void setQty(String key, int qtyMilli) {
    if (qtyMilli <= 0) {
      state = [for (final l in state) if (l.key != key) l];
    } else {
      state = [for (final l in state) l.key == key ? l.withQty(qtyMilli) : l];
    }
  }

  /// تغيير وحدة سطر (مثلاً من كيلو إلى كيس) مع دمجه إن وُجد سطر بنفس الوحدة.
  void switchUnit(String key, ItemUnit unit) {
    final i = state.indexWhere((l) => l.key == key);
    if (i < 0) return;
    final old = state[i];
    final nl = CartLine.of(
      itemId: old.itemId,
      name: old.name,
      baseCost: old.baseCost,
      unit: unit,
      qtyMilli: old.qtyMilli,
    );
    final rest = [...state]..removeAt(i);
    final j = rest.indexWhere((l) => l.key == nl.key);
    if (j >= 0) {
      rest[j] = rest[j].withQty(rest[j].qtyMilli + nl.qtyMilli);
    } else {
      rest.insert(i, nl);
    }
    state = rest;
  }

  void replaceAll(List<CartLine> lines) => state = List.unmodifiable(lines);
  void clear() => state = const [];
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartLine>>(CartNotifier.new);

int cartTotal(List<CartLine> lines) =>
    lines.fold<int>(0, (s, l) => s + l.total);

/// فاتورة معلّقة (في الذاكرة فقط؛ تُفقد بإغلاق التطبيق).
class HeldCart {
  final String label;
  final List<CartLine> lines;
  const HeldCart(this.label, this.lines);
}

class HeldCartsNotifier extends Notifier<List<HeldCart>> {
  @override
  List<HeldCart> build() => const [];

  void hold(List<CartLine> lines) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    state = [...state, HeldCart('معلّقة ${state.length + 1} · $hh:$mm', lines)];
  }

  void removeAt(int i) {
    final copy = [...state]..removeAt(i);
    state = copy;
  }
}

final heldCartsProvider =
    NotifierProvider<HeldCartsNotifier, List<HeldCart>>(HeldCartsNotifier.new);
