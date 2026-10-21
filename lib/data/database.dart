import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/paths.dart';

part 'database.g.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();
int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// معلومات الجهاز الحالي (تُضبط عند بدء التطبيق).
/// إعدادات الضريبة المحمّلة عند بدء التشغيل (زي kCurrency).
/// الواجهة بتقرأهم بشكل متزامن عشان الأرقام تطلع مطابقة للمخزّن.
int kVatRate = 0;
bool kVatInclusive = false;

/// يحسب الضريبة على الصافي (بعد الخصم).
///
/// شاملة = الضريبة جزء من الرقم، غير شاملة = بتتضاف فوقه.
/// دالة نقية عشان الكود والواجهة يطلعوا نفس الرقم بالظبط.
({int tax, int total}) computeVat(int net, int ratePercent,
    {bool inclusive = false}) {
  final base = net < 0 ? 0 : net;
  if (ratePercent <= 0 || base == 0) return (tax: 0, total: base);
  if (inclusive) {
    final tax = (base * ratePercent / (100 + ratePercent)).round();
    return (tax: tax, total: base);
  }
  final tax = (base * ratePercent / 100).round();
  return (tax: tax, total: base + tax);
}

class DeviceInfo {
  static String id = '';
  static String prefix = 'D'; // D = ديسك توب، M = موبايل
}

/// الحقول المشتركة لكل جدول قابل للمزامنة (انظر القسم 4.1 من ملف المواصفات).
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  IntColumn get createdAt => integer().clientDefault(nowMs)();
  IntColumn get updatedAt => integer().clientDefault(nowMs)();
  TextColumn get deviceId => text().clientDefault(() => DeviceInfo.id)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class ShopSettings extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();
  @override
  Set<Column> get primaryKey => {settingKey};
}

class Counters extends Table {
  TextColumn get name => text()();
  IntColumn get value => integer()();
  @override
  Set<Column> get primaryKey => {name};
}

class Users extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get role => text().withDefault(const Constant('cashier'))();
  TextColumn get pinHash => text().nullable()();
  TextColumn get pinSalt => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class Categories extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
}

class Items extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get costPrice => integer().withDefault(const Constant(0))();
  IntColumn get salePrice => integer()();
  IntColumn get reorderLevelMilli => integer().withDefault(const Constant(0))();
  BoolColumn get trackExpiry => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class ItemUnits extends Table with SyncColumns {
  TextColumn get itemId => text()();
  TextColumn get name => text()();
  IntColumn get factorMilli => integer()(); // كم وحدة أساسية في هذه الوحدة ×1000
  IntColumn get salePrice => integer()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

class ItemBarcodes extends Table with SyncColumns {
  TextColumn get itemId => text()();
  TextColumn get unitId => text().nullable()();
  TextColumn get code => text()();
  BoolColumn get generated => boolean().withDefault(const Constant(false))();
}

/// حركات المخزون (إضافة فقط): كمية الصنف = مجموع الحركات.
class StockMovements extends Table with SyncColumns {
  TextColumn get itemId => text()();
  IntColumn get qtyMilli => integer()(); // موجب أو سالب، بالوحدة الأساسية ×1000
  TextColumn get reason => text()(); // sale, purchase, return, count, damage, opening
  TextColumn get refId => text().nullable()();
  IntColumn get expiryDate => integer().nullable()();
  TextColumn get note => text().nullable()();
}

class Customers extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  IntColumn get creditLimit => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}

class Suppliers extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
}

class Sales extends Table with SyncColumns {
  TextColumn get number => text()();
  TextColumn get type => text()(); // cash | credit
  TextColumn get customerId => text().nullable()();
  IntColumn get soldAt => integer()();
  IntColumn get subtotal => integer()();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get tax => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();
  IntColumn get paid => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get userId => text().nullable()();
  /// الوردية اللي الفاتورة اتعملت فيها (null للفواتير القديمة).
  TextColumn get shiftId => text().nullable()();
}

class SaleLines extends Table with SyncColumns {
  TextColumn get saleId => text()();
  TextColumn get itemId => text()();
  TextColumn get unitId => text().nullable()();
  IntColumn get qtyMilli => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get unitCost => integer().withDefault(const Constant(0))();
  IntColumn get discount => integer().withDefault(const Constant(0))();
}

class Payments extends Table with SyncColumns {
  TextColumn get partyType => text()(); // customer | supplier
  TextColumn get partyId => text()();
  TextColumn get direction => text()(); // in (تحصيل) | out (سداد)
  IntColumn get amount => integer()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get saleId => text().nullable()();
  IntColumn get paidAt => integer()();
  TextColumn get note => text().nullable()();
}

class Purchases extends Table with SyncColumns {
  TextColumn get number => text()();
  TextColumn get supplierId => text().nullable()();
  IntColumn get purchasedAt => integer()();
  IntColumn get total => integer()();
  IntColumn get paid => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('completed'))();
}

class PurchaseLines extends Table with SyncColumns {
  TextColumn get purchaseId => text()();
  TextColumn get itemId => text()();
  IntColumn get qtyMilli => integer()();
  IntColumn get unitCost => integer()();
  IntColumn get expiryDate => integer().nullable()();
  TextColumn get unitId => text().nullable()();
  IntColumn get factorMilli => integer().withDefault(const Constant(1000))();
}

class Devices extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get kind => text()(); // desktop | mobile
  TextColumn get sharedKey => text().nullable()();
  IntColumn get lastSyncAt => integer().nullable()();
  /// بادئة أرقام فواتير هذا الجهاز (D للرئيسي، M1/M2... للموبايلات).
  TextColumn get prefix => text().nullable()();
}

class AuditLogs extends Table with SyncColumns {
  TextColumn get userId => text().nullable()();
  TextColumn get action => text()();
  TextColumn get refId => text().nullable()();
  TextColumn get details => text().nullable()();
}

/// تفصيل طرق الدفع لكل فاتورة (كاش + كارت + محفظة في نفس الفاتورة).
class SalePayments extends Table with SyncColumns {
  TextColumn get saleId => text()();
  /// cash | card | wallet | transfer | cheque
  TextColumn get method => text()();
  IntColumn get amount => integer()();
  TextColumn get reference => text().nullable()();
}

/// وردية الكاشير: من فتح الدرج حتى تقفيله.
///
/// وردية واحدة مفتوحة لكل جهاز. المبيعات بتتربط بيها عشان كل تقرير
/// يخص الوردية يبقى دقيق، والفرق بين النقد المتوقع والمعدود يبقى موثّق.
class Shifts extends Table with SyncColumns {
  TextColumn get number => text()();
  TextColumn get userId => text()();
  IntColumn get openedAt => integer()();
  IntColumn get closedAt => integer().nullable()();
  /// النقدية الافتتاحية في الدرج (أجزاء من 100).
  IntColumn get openingCash => integer().withDefault(const Constant(0))();
  /// المحسوب لحظة التقفيل: افتتاحي + كاش + دفعات - مرتجعات - مدفوعات.
  IntColumn get expectedCash => integer().nullable()();
  /// المعدود فعليًا بواسطة الكاشير.
  IntColumn get countedCash => integer().nullable()();
  /// المعدود - المتوقع. سالب يعني عجز.
  IntColumn get difference => integer().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
}

class SaleReturns extends Table with SyncColumns {
  TextColumn get saleId => text()();
  TextColumn get saleLineId => text()();
  IntColumn get qtyMilli => integer()(); // بوحدة السطر
  IntColumn get refundAmount => integer()();
  IntColumn get returnedAt => integer()();
  TextColumn get userId => text().nullable()();
  TextColumn get note => text().nullable()();
}

// ---------- كائنات مساعدة للعرض والإدخال ----------

class ItemRow {
  final String id, name;
  /// سعر وتكلفة الوحدة الأساسية، والمخزون بالوحدة الأساسية ×1000.
  final int salePrice, costPrice, stockMilli;
  final String baseUnit, defUnitName;
  final int defUnitPrice;
  /// حد إعادة الطلب بالوحدة الأساسية ×1000 (0 = غير محدد).
  final int reorderMilli;
  const ItemRow(this.id, this.name, this.salePrice, this.costPrice,
      this.stockMilli, this.baseUnit, this.defUnitName, this.defUnitPrice,
      this.reorderMilli);
}

class ItemMatch {
  final Item item;
  final ItemUnit unit;
  const ItemMatch(this.item, this.unit);
}

class CustomerRow {
  final String id, name;
  final String? phone, address;
  final int balance; // المديونية الحالية بالقروش
  final int creditLimit; // 0 = بدون حد
  const CustomerRow(this.id, this.name, this.phone, this.address, this.balance,
      this.creditLimit);
}

class SaleRow {
  final String id, number, type, status;
  final String? customerName;
  final int soldAt, total, paid;
  const SaleRow(this.id, this.number, this.type, this.status, this.customerName,
      this.soldAt, this.total, this.paid);
}

/// ملخّص وردية: الأرقام اللي بيتبني عليها تقرير X (أثناء الوردية) و Z (بعد التقفيل).
class ShiftSummary {
  final Shift shift;
  final int cashSales, creditSales, salesCount;
  /// النقد اللي دخل الدرج من الفواتير نفسها (كاش كامل أو جزء من فاتورة مقسّمة).
  final int cashFromSales;
  final int cashReturns, cashPaymentsIn, cashPaymentsOut;

  const ShiftSummary({
    required this.shift,
    required this.cashSales,
    required this.creditSales,
    required this.salesCount,
    required this.cashFromSales,
    required this.cashReturns,
    required this.cashPaymentsIn,
    required this.cashPaymentsOut,
  });

  /// المتوقع في الدرج: افتتاحي + نقد الفواتير + دفعات مستقلة − مرتجعات − مدفوعات.
  int get expectedCash =>
      shift.openingCash + cashFromSales + cashPaymentsIn - cashReturns - cashPaymentsOut;

  /// المعدود − المتوقع. null قبل التقفيل.
  int? get difference =>
      shift.countedCash == null ? null : shift.countedCash! - expectedCash;
}

class SaleDetailLine {
  final String lineId, itemId, name, unitName;
  final int qtyMilli, unitPrice, returnedMilli;
  const SaleDetailLine(this.lineId, this.itemId, this.name, this.unitName,
      this.qtyMilli, this.unitPrice, this.returnedMilli);
  int get total => (unitPrice * qtyMilli / 1000).round();
  int get remainingMilli => qtyMilli - returnedMilli;
}

class SaleLineInput {
  final String itemId;
  final String? unitId;
  final int qtyMilli, unitPrice, unitCost;
  /// عدد الوحدات الأساسية في وحدة السطر ×1000 (للتحويل لحركة المخزون).
  final int factorMilli;
  const SaleLineInput({
    required this.itemId,
    this.unitId,
    required this.qtyMilli,
    required this.unitPrice,
    this.unitCost = 0,
    this.factorMilli = 1000,
  });
  int get total => (unitPrice * qtyMilli / 1000).round();
}

class SupplierRow {
  final String id, name;
  final String? phone, address;
  final int balance; // المستحق للمورد بالقروش
  const SupplierRow(this.id, this.name, this.phone, this.address, this.balance);
}

class PurchaseRow {
  final String id, number, status;
  final String? supplierName;
  final int purchasedAt, total, paid;
  const PurchaseRow(this.id, this.number, this.status, this.supplierName,
      this.purchasedAt, this.total, this.paid);
}

/// سطر دفع واحد داخل الفاتورة: الطريقة والمبلغ.
class SalePaymentInput {
  final String method;
  final int amount;
  final String? reference;
  const SalePaymentInput(
      {required this.method, required this.amount, this.reference});
}

class PurchaseLineInput {
  final String itemId;
  final String? unitId;
  final int qtyMilli, unitCost, factorMilli;
  const PurchaseLineInput({
    required this.itemId,
    this.unitId,
    required this.qtyMilli,
    required this.unitCost,
    this.factorMilli = 1000,
  });
  int get total => (unitCost * qtyMilli / 1000).round();
}

class PurchaseDetailLine {
  final String name, unitName;
  final int qtyMilli, unitCost;
  const PurchaseDetailLine(this.name, this.unitName, this.qtyMilli, this.unitCost);
  int get total => (unitCost * qtyMilli / 1000).round();
}

/// حركة في كشف الحساب: plus يزيد الرصيد، minus ينقصه.
class StatementEntry {
  final int at;
  final String title;
  final int plus, minus;
  const StatementEntry(this.at, this.title, {this.plus = 0, this.minus = 0});
}

class TopItem {
  final String name, baseUnit;
  final int revenue, baseQtyMilli;
  const TopItem(this.name, this.revenue, this.baseQtyMilli, this.baseUnit);
}

class ReportData {
  final int salesTotal, salesCount, cashTotal, creditTotal;
  final int taxTotal;
  final int returnsTotal, cogs, returnsCost;
  final List<TopItem> top;
  const ReportData({
    required this.salesTotal,
    required this.salesCount,
    required this.cashTotal,
    required this.creditTotal,
    required this.taxTotal,
    required this.returnsTotal,
    required this.cogs,
    required this.returnsCost,
    required this.top,
  });
  int get net => salesTotal - returnsTotal;
  /// الربح التقريبي = صافي المبيعات − تكلفة البضاعة المباعة (بعد المرتجع).
  int get profit => net - (cogs - returnsCost);
}

class InvoiceData {
  final String number, type, status;
  final int soldAt, subtotal, discount, tax, total, paid;
  final String? customerName, customerPhone, cashierName;
  final int? customerBalance;
  final List<SaleDetailLine> lines;
  const InvoiceData({
    required this.number,
    required this.type,
    required this.status,
    required this.soldAt,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paid,
    required this.lines,
    this.customerName,
    this.customerPhone,
    this.cashierName,
    this.customerBalance,
  });
}

@DriftDatabase(tables: [
  ShopSettings,
  Counters,
  Users,
  Categories,
  Items,
  ItemUnits,
  ItemBarcodes,
  StockMovements,
  Customers,
  Suppliers,
  Sales,
  SaleLines,
  Payments,
  Purchases,
  PurchaseLines,
  Devices,
  AuditLogs,
  SaleReturns,
  Shifts,
  SalePayments,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase()
      : super(driftDatabase(
          name: 'mykash',
          native: DriftNativeOptions(databasePath: AppPaths.dbPath),
        ));
  AppDatabase.forTesting(super.e);

  /// يُستخدم أيضًا للتحقق من النسخ الاحتياطية قبل الاستعادة.
  static const int currentSchema = 6;

  @override
  int get schemaVersion => currentSchema;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createSyncInfra(backfill: false);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(saleReturns);
          if (from < 3) {
            await m.addColumn(purchases, purchases.status);
            await m.addColumn(purchaseLines, purchaseLines.unitId);
            await m.addColumn(purchaseLines, purchaseLines.factorMilli);
          }
          if (from < 4) {
            await m.addColumn(devices, devices.prefix);
            await _createSyncInfra(backfill: true);
          }
          if (from < 5) {
            await m.createTable(shifts);
            await m.addColumn(sales, sales.shiftId);
          }
          if (from < 6) {
            await m.createTable(salePayments);
          }
        },
      );

  // ---------- الإعدادات والجهاز ----------

  Future<String?> getSetting(String key) async {
    final row = await (select(shopSettings)
          ..where((s) => s.settingKey.equals(key)))
        .getSingleOrNull();
    return row?.settingValue;
  }

  Future<void> setSetting(String key, String value) =>
      into(shopSettings).insertOnConflictUpdate(
        ShopSettingsCompanion.insert(settingKey: key, settingValue: value),
      );

  Future<void> initDevice({required bool isMobile}) async {
    var id = await getSetting('device_id');
    if (id == null) {
      id = newId();
      await setSetting('device_id', id);
      await setSetting('shop_name', 'محلي');
    }
    DeviceInfo.id = id;
    DeviceInfo.prefix =
        await getSetting('device_prefix') ?? (isMobile ? 'M' : 'D');
  }

  /// رقم فاتورة مميّز بالجهاز: D-0001 / M-0001
  Future<String> _nextInvoiceNumber() async {
    final row = await (select(counters)..where((c) => c.name.equals('invoice')))
        .getSingleOrNull();
    final next = (row?.value ?? 0) + 1;
    await into(counters).insertOnConflictUpdate(
      CountersCompanion.insert(name: 'invoice', value: next),
    );
    return '${DeviceInfo.prefix}-${next.toString().padLeft(4, '0')}';
  }

  // ---------- الأصناف والمخزون ----------

  Stream<List<ItemRow>> watchItems(String query, {String? onlyId}) {
    final q = query.trim();
    return customSelect(
      '''
SELECT i.id, i.name, i.sale_price, i.cost_price, i.reorder_level_milli,
  COALESCE((SELECT SUM(m.qty_milli) FROM stock_movements m
            WHERE m.item_id = i.id AND m.is_deleted = 0), 0) AS stock,
  COALESCE((SELECT u.name FROM item_units u
            WHERE u.item_id = i.id AND u.factor_milli = 1000 AND u.is_deleted = 0
            ORDER BY u.created_at LIMIT 1), 'قطعة') AS base_unit,
  COALESCE((SELECT u.name FROM item_units u
            WHERE u.item_id = i.id AND u.is_default = 1 AND u.is_deleted = 0
            LIMIT 1), 'قطعة') AS def_unit_name,
  COALESCE((SELECT u.sale_price FROM item_units u
            WHERE u.item_id = i.id AND u.is_default = 1 AND u.is_deleted = 0
            LIMIT 1), i.sale_price) AS def_unit_price
FROM items i
WHERE i.is_deleted = 0 AND i.active = 1
  AND (i.name LIKE ?1 OR EXISTS (
        SELECT 1 FROM item_barcodes b
        WHERE b.item_id = i.id AND b.code = ?2 AND b.is_deleted = 0))
  AND (?3 = '' OR i.id = ?3)
ORDER BY i.name
LIMIT 300
''',
      variables: [
        Variable.withString('%$q%'),
        Variable.withString(q),
        Variable.withString(onlyId ?? ''),
      ],
      readsFrom: {items, stockMovements, itemBarcodes, itemUnits},
    ).watch().map((rows) => rows
        .map((r) => ItemRow(
              r.read<String>('id'),
              r.read<String>('name'),
              r.read<int>('sale_price'),
              r.read<int>('cost_price'),
              r.read<int>('stock'),
              r.read<String>('base_unit'),
              r.read<String>('def_unit_name'),
              r.read<int>('def_unit_price'),
              r.read<int>('reorder_level_milli'),
            ))
        .toList());
  }

  Future<Item?> itemByBarcode(String code) async {
    final query = select(items).join([
      innerJoin(itemBarcodes, itemBarcodes.itemId.equalsExp(items.id)),
    ])
      ..where(itemBarcodes.code.equals(code) &
          itemBarcodes.isDeleted.equals(false) &
          items.isDeleted.equals(false));
    final row = await query.getSingleOrNull();
    return row?.readTable(items);
  }

  Future<void> addItem({
    required String name,
    required int salePrice,
    int costPrice = 0,
    String? barcode,
    int openingQtyMilli = 0,
    String unitName = 'قطعة',
  }) {
    return transaction(() async {
      if (barcode != null &&
          barcode.trim().isNotEmpty &&
          await _barcodeTaken(barcode.trim())) {
        throw StateError('الباركود مستخدم لصنف آخر');
      }
      final id = newId();
      await into(items).insert(ItemsCompanion.insert(
        id: Value(id),
        name: name,
        salePrice: salePrice,
        costPrice: Value(costPrice),
      ));
      await into(itemUnits).insert(ItemUnitsCompanion.insert(
        itemId: id,
        name: unitName.trim().isEmpty ? 'قطعة' : unitName.trim(),
        factorMilli: 1000,
        salePrice: salePrice,
        isDefault: const Value(true),
      ));
      if (barcode != null && barcode.trim().isNotEmpty) {
        await into(itemBarcodes).insert(
          ItemBarcodesCompanion.insert(itemId: id, code: barcode.trim()),
        );
      }
      if (openingQtyMilli > 0) {
        await into(stockMovements).insert(StockMovementsCompanion.insert(
          itemId: id,
          qtyMilli: openingQtyMilli,
          reason: 'opening',
        ));
      }
    });
  }

  // ---------- العملاء ----------

  Stream<List<CustomerRow>> watchCustomers() {
    return customSelect(
      '''
SELECT c.id, c.name, c.phone, c.address, c.credit_limit,
  COALESCE((SELECT SUM(s.total) FROM sales s
            WHERE s.customer_id = c.id AND s.type = 'credit'
              AND s.status = 'completed' AND s.is_deleted = 0), 0)
  - COALESCE((SELECT SUM(r.refund_amount) FROM sale_returns r
              JOIN sales s2 ON s2.id = r.sale_id
              WHERE s2.customer_id = c.id AND s2.type = 'credit'
                AND s2.status = 'completed' AND r.is_deleted = 0), 0)
  - COALESCE((SELECT SUM(CASE WHEN p.direction = 'in' THEN p.amount ELSE -p.amount END)
              FROM payments p
              WHERE p.party_type = 'customer' AND p.party_id = c.id
                AND p.is_deleted = 0), 0) AS balance
FROM customers c
WHERE c.is_deleted = 0
ORDER BY c.name
''',
      readsFrom: {customers, sales, payments, saleReturns},
    ).watch().map((rows) => rows
        .map((r) => CustomerRow(
              r.read<String>('id'),
              r.read<String>('name'),
              r.readNullable<String>('phone'),
              r.readNullable<String>('address'),
              r.read<int>('balance'),
              r.read<int>('credit_limit'),
            ))
        .toList());
  }

  Future<String> addCustomer({
    required String name,
    String? phone,
    String? address,
    int creditLimit = 0,
  }) async {
    final id = newId();
    await into(customers).insert(CustomersCompanion.insert(
      id: Value(id),
      name: name,
      phone: Value(phone),
      address: Value(address),
      creditLimit: Value(creditLimit),
    ));
    return id;
  }

  // ---------- البيع ----------

  /// يُنشئ الفاتورة وسطورها وحركات المخزون في معاملة واحدة.
  /// يعيد رقم الفاتورة.
  /// دور المستخدم، أو null لو مش معروف (مسار قديم أو بدون تسجيل دخول).
  Future<String?> _roleOf(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    final u = await (select(users)..where((x) => x.id.equals(userId)))
        .getSingleOrNull();
    return u?.role;
  }

  Future<({String id, String number})> completeSale({
    required List<SaleLineInput> lines,
    required bool credit,
    String? customerId,
    int discount = 0,
    int paidNow = 0,
    String? userId,
    List<SalePaymentInput>? paymentSplits,
  }) {
    return transaction(() async {
      final subtotal = lines.fold<int>(0, (s, l) => s + l.total);
      final net = subtotal - discount;
      final vatRate = int.tryParse(await getSetting('vat_rate') ?? '') ?? 0;
      final vatInclusive = (await getSetting('vat_inclusive') ?? '0') == '1';
      final vat = computeVat(net, vatRate, inclusive: vatInclusive);
      final total = vat.total;

      // حد الخصم للكاشير. المدير بلا حد. userId فارغ = مسار قديم بدون فحص.
      final role = await _roleOf(userId);
      if (role != null && role != 'admin' && discount > 0) {
        final cap =
            int.tryParse(await getSetting('max_discount_percent') ?? '') ?? 0;
        if (subtotal > 0 && discount * 100 > cap * subtotal) {
          throw StateError(
              'الخصم المسموح للكاشير $cap% فقط. راجع المدير قبل الخصم.');
        }
      }

      final number = await _nextInvoiceNumber();
      final saleId = newId();
      final now = nowMs();

      // لما الأبلكيشن يبعت تفصيل طرق الدفع، مجموعه هو المدفوع.
      // غير كده بنحافظ على السلوك القديم: كاش = الإجمالي، آجل = المقدم.
      final splits = (paymentSplits == null || paymentSplits.isEmpty)
          ? <SalePaymentInput>[
              if ((credit ? paidNow : total) > 0)
                SalePaymentInput(
                    method: 'cash', amount: credit ? paidNow : total),
            ]
          : paymentSplits;
      final paidFromSplits = splits.fold<int>(0, (s, p) => s + p.amount);
      final paid = paidFromSplits > total ? total : paidFromSplits;
      final openShift = await currentShift();

      await into(sales).insert(SalesCompanion.insert(
        id: Value(saleId),
        number: number,
        type: credit ? 'credit' : 'cash',
        shiftId: Value(openShift?.id),
        customerId: Value(customerId),
        soldAt: now,
        subtotal: subtotal,
        discount: Value(discount),
        tax: Value(vat.tax),
        total: total,
        paid: Value(paid),
        userId: Value(userId),
      ));

      for (final p in splits) {
        if (p.amount <= 0) continue;
        await into(salePayments).insert(SalePaymentsCompanion.insert(
          saleId: saleId,
          method: p.method,
          amount: p.amount,
          reference: Value(p.reference),
        ));
      }

      for (final l in lines) {
        await into(saleLines).insert(SaleLinesCompanion.insert(
          saleId: saleId,
          itemId: l.itemId,
          unitId: Value(l.unitId),
          qtyMilli: l.qtyMilli,
          unitPrice: l.unitPrice,
          unitCost: Value(l.unitCost),
        ));
        await into(stockMovements).insert(StockMovementsCompanion.insert(
          itemId: l.itemId,
          qtyMilli: -(l.qtyMilli * l.factorMilli / 1000).round(),
          reason: 'sale',
          refId: Value(saleId),
        ));
      }

      if (credit && customerId != null && paidNow > 0) {
        await into(payments).insert(PaymentsCompanion.insert(
          partyType: 'customer',
          partyId: customerId,
          direction: 'in',
          amount: paidNow,
          saleId: Value(saleId),
          paidAt: now,
        ));
      }
      if (discount > 0) {
        await logAudit('discount',
            userId: userId, refId: saleId, details: '$number: $discount');
      }
      return (id: saleId, number: number);
    });
  }

  // ---------- الفواتير ----------

  /// filter: all | cash | credit | cancelled
  Stream<List<SaleRow>> watchSales(String query, String filter) {
    final where = StringBuffer(
        "s.is_deleted = 0 AND (s.number LIKE ?1 OR IFNULL(c.name, '') LIKE ?1)");
    if (filter == 'cash') {
      where.write(" AND s.type = 'cash' AND s.status = 'completed'");
    } else if (filter == 'credit') {
      where.write(" AND s.type = 'credit' AND s.status = 'completed'");
    } else if (filter == 'cancelled') {
      where.write(" AND s.status = 'cancelled'");
    }
    return customSelect(
      '''
SELECT s.id, s.number, s.type, s.status, s.sold_at, s.total, s.paid,
       c.name AS customer_name
FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
WHERE $where
ORDER BY s.sold_at DESC
LIMIT 300
''',
      variables: [Variable.withString('%${query.trim()}%')],
      readsFrom: {sales, customers},
    ).watch().map((rows) => rows
        .map((r) => SaleRow(
              r.read<String>('id'),
              r.read<String>('number'),
              r.read<String>('type'),
              r.read<String>('status'),
              r.readNullable<String>('customer_name'),
              r.read<int>('sold_at'),
              r.read<int>('total'),
              r.read<int>('paid'),
            ))
        .toList());
  }

  // ---------- الوردية ----------

  /// أحدث وردية مفتوحة على الجهاز، أو null لو مفيش.
  Future<Shift?> currentShift() =>
      (select(shifts)
            ..where((s) => s.status.equals('open'))
            ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
            ..limit(1))
          .getSingleOrNull();

  /// متابعة الوردية المفتوحة لحظيًا.
  Stream<Shift?> watchCurrentShift() =>
      (select(shifts)..where((s) => s.status.equals('open')))
          .watchSingleOrNull();

  Future<String> _nextShiftNumber() async {
    final row = await (select(counters)..where((c) => c.name.equals('shift')))
        .getSingleOrNull();
    final next = (row?.value ?? 0) + 1;
    await into(counters).insertOnConflictUpdate(
      CountersCompanion.insert(name: 'shift', value: next),
    );
    return 'S-${next.toString().padLeft(4, '0')}';
  }

  /// فتح وردية جديدة. بترفض لو فيه وردية مفتوحة بالفعل.
  Future<Shift> openShift({
    required String userId,
    required int openingCash,
  }) {
    return transaction(() async {
      final open = await currentShift();
      if (open != null) {
        throw StateError(
            'فيه وردية مفتوحة بالفعل (${open.number}). اقفلها الأول.');
      }
      final id = newId();
      final number = await _nextShiftNumber();
      await into(shifts).insert(ShiftsCompanion.insert(
        id: Value(id),
        number: number,
        userId: userId,
        openedAt: nowMs(),
        openingCash: Value(openingCash),
      ));
      await logAudit('shift_open',
          userId: userId, refId: id, details: '$number: $openingCash');
      return await (select(shifts)..where((s) => s.id.equals(id))).getSingle();
    });
  }

  /// ملخّص الوردية من الأرقام الفعلية.
  Future<ShiftSummary> shiftSummary(String shiftId) async {
    final shift =
        await (select(shifts)..where((s) => s.id.equals(shiftId))).getSingle();

    final totals = await customSelect(
      '''
SELECT
  COALESCE(SUM(CASE WHEN s.type = 'cash' THEN s.total ELSE 0 END), 0) AS cash_total,
  COALESCE(SUM(CASE WHEN s.type = 'credit' THEN s.total ELSE 0 END), 0) AS credit_total,
  COUNT(*) AS cnt,
  COALESCE(SUM(COALESCE(
    (SELECT SUM(sp.amount) FROM sale_payments sp
       WHERE sp.sale_id = s.id AND sp.method = 'cash' AND sp.is_deleted = 0),
    CASE WHEN s.type = 'cash' THEN s.total ELSE s.paid END)), 0) AS cash_in
FROM sales s
WHERE s.shift_id = ?1 AND s.status = 'completed' AND s.is_deleted = 0
''',
      variables: [Variable.withString(shiftId)],
      readsFrom: {sales, salePayments},
    ).getSingle();

    final returns = await customSelect(
      '''
SELECT COALESCE(SUM(r.refund_amount), 0) AS v
FROM sale_returns r JOIN sales s ON s.id = r.sale_id
WHERE s.shift_id = ?1 AND s.type = 'cash' AND s.status = 'completed'
  AND s.is_deleted = 0 AND r.is_deleted = 0
''',
      variables: [Variable.withString(shiftId)],
      readsFrom: {saleReturns, sales},
    ).getSingle();

    // الدفعات مالهاش shift_id، فبنحددها بنافذة الوردية الزمنية.
    final windowEnd = shift.closedAt ?? nowMs();
    final movement = await customSelect(
      '''
SELECT
  COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END), 0) AS pin,
  COALESCE(SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END), 0) AS pout
FROM payments
WHERE method = 'cash' AND is_deleted = 0 AND sale_id IS NULL
  AND paid_at >= ?1 AND paid_at <= ?2
''',
      variables: [Variable.withInt(shift.openedAt), Variable.withInt(windowEnd)],
      readsFrom: {payments},
    ).getSingle();

    return ShiftSummary(
      shift: shift,
      cashSales: totals.read<int>('cash_total'),
      creditSales: totals.read<int>('credit_total'),
      salesCount: totals.read<int>('cnt'),
      cashFromSales: totals.read<int>('cash_in'),
      cashReturns: returns.read<int>('v'),
      cashPaymentsIn: movement.read<int>('pin'),
      cashPaymentsOut: movement.read<int>('pout'),
    );
  }

  /// تقفيل الوردية بمبلغ معدود فعليًا.
  Future<ShiftSummary> closeShift({
    required String shiftId,
    required int countedCash,
    String? note,
  }) {
    return transaction(() async {
      final shift = await (select(shifts)..where((s) => s.id.equals(shiftId)))
          .getSingle();
      if (shift.status != 'open') {
        throw StateError('الوردية مقفولة بالفعل.');
      }
      final summary = await shiftSummary(shiftId);
      final expected = summary.expectedCash;
      await (update(shifts)..where((s) => s.id.equals(shiftId))).write(
        ShiftsCompanion(
          closedAt: Value(nowMs()),
          expectedCash: Value(expected),
          countedCash: Value(countedCash),
          difference: Value(countedCash - expected),
          note: Value(note),
          status: const Value('closed'),
        ),
      );
      await logAudit('shift_close',
          refId: shiftId, details: '${shift.number}: $expected / $countedCash');
      return await shiftSummary(shiftId);
    });
  }

  /// فواتير وردية معيّنة.
  Stream<List<SaleRow>> watchShiftSales(String shiftId) {
    return customSelect(
      '''
SELECT s.id, s.number, s.type, s.status, s.sold_at, s.total, s.paid,
       c.name AS customer_name
FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
WHERE s.is_deleted = 0 AND s.shift_id = ?1
ORDER BY s.sold_at DESC
''',
      variables: [Variable.withString(shiftId)],
      readsFrom: {sales, customers},
    ).watch().map((rows) => rows
        .map((r) => SaleRow(
              r.read<String>('id'),
              r.read<String>('number'),
              r.read<String>('type'),
              r.read<String>('status'),
              r.readNullable<String>('customer_name'),
              r.read<int>('sold_at'),
              r.read<int>('total'),
              r.read<int>('paid'),
            ))
        .toList());
  }

  Future<List<SaleDetailLine>> saleLinesFor(String saleId) async {    final rows = await customSelect(
      '''
SELECT l.id AS line_id, l.item_id, i.name AS name,
       COALESCE(u.name, '') AS unit_name, l.qty_milli, l.unit_price,
       COALESCE((SELECT SUM(r.qty_milli) FROM sale_returns r
                 WHERE r.sale_line_id = l.id AND r.is_deleted = 0), 0) AS returned
FROM sale_lines l
JOIN items i ON i.id = l.item_id
LEFT JOIN item_units u ON u.id = l.unit_id
WHERE l.sale_id = ?1 AND l.is_deleted = 0
''',
      variables: [Variable.withString(saleId)],
      readsFrom: {saleLines, items, itemUnits, saleReturns},
    ).get();
    return rows
        .map((r) => SaleDetailLine(
              r.read<String>('line_id'),
              r.read<String>('item_id'),
              r.read<String>('name'),
              r.read<String>('unit_name'),
              r.read<int>('qty_milli'),
              r.read<int>('unit_price'),
              r.read<int>('returned'),
            ))
        .toList();
  }

  /// إلغاء فاتورة كاملة بقيد عكسي: ترجيع المخزون وعكس الدفعة المقدّمة.
  /// لا يُحذف أي سجل فعليًا.
  Future<void> cancelSale(String saleId, {String? userId}) {
    return transaction(() async {
      final sale =
          await (select(sales)..where((s) => s.id.equals(saleId))).getSingle();
      if (sale.status != 'completed') return;

      // إلغاء الفواتير ممكن يتقفل للكاشير من الإعدادات.
      final role = await _roleOf(userId);
      if (role != null &&
          role != 'admin' &&
          (await getSetting('allow_void') ?? '1') == '0') {
        throw StateError('إلغاء الفواتير مقصور على المدير.');
      }
      await (update(sales)..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(
          status: const Value('cancelled'),
          updatedAt: Value(nowMs()),
          deviceId: Value(DeviceInfo.id),
        ),
      );
      final lines = await (select(saleLines)
            ..where((l) => l.saleId.equals(saleId) & l.isDeleted.equals(false)))
          .get();
      for (final l in lines) {
        final remaining = l.qtyMilli - await _returnedQty(l.id);
        if (remaining <= 0) continue;
        final factor = await _factorOf(l.unitId);
        await into(stockMovements).insert(StockMovementsCompanion.insert(
          itemId: l.itemId,
          qtyMilli: (remaining * factor / 1000).round(),
          reason: 'return',
          refId: Value(saleId),
          note: Value('إلغاء فاتورة ${sale.number}'),
        ));
      }
      if (sale.type == 'credit' && sale.customerId != null) {
        final paidRows = await (select(payments)
              ..where((p) =>
                  p.saleId.equals(saleId) &
                  p.direction.equals('in') &
                  p.isDeleted.equals(false)))
            .get();
        final paid = paidRows.fold<int>(0, (s, p) => s + p.amount);
        if (paid > 0) {
          await into(payments).insert(PaymentsCompanion.insert(
            partyType: 'customer',
            partyId: sale.customerId!,
            direction: 'out',
            amount: paid,
            saleId: Value(saleId),
            paidAt: nowMs(),
            note: Value('عكس دفعة فاتورة ملغاة ${sale.number}'),
          ));
        }
      }
      await logAudit('cancel_sale',
          userId: userId, refId: saleId, details: sale.number);
    });
  }

  // ---------- تعديل الصنف وتسوية المخزون ----------

  Future<int> stockOf(String itemId) async {
    final r = await customSelect(
      'SELECT COALESCE(SUM(qty_milli), 0) AS s FROM stock_movements '
      'WHERE item_id = ?1 AND is_deleted = 0',
      variables: [Variable.withString(itemId)],
      readsFrom: {stockMovements},
    ).getSingle();
    return r.read<int>('s');
  }

  Future<void> updateItem({
    required String id,
    required String name,
    required int salePrice,
    required int costPrice,
    int? newStockMilli,
    String? baseUnitName,
    int? reorderMilli,
    String? userId,
  }) {
    return transaction(() async {
      await (update(items)..where((i) => i.id.equals(id))).write(ItemsCompanion(
        name: Value(name),
        salePrice: Value(salePrice),
        costPrice: Value(costPrice),
        updatedAt: Value(nowMs()),
        deviceId: Value(DeviceInfo.id),
      ));
      if (reorderMilli != null) {
        await (update(items)..where((i) => i.id.equals(id))).write(
            ItemsCompanion(reorderLevelMilli: Value(reorderMilli)));
      }
      // سعر الصنف الرئيسي = سعر الوحدة الأساسية (عامل التحويل 1)
      await (update(itemUnits)
            ..where((u) => u.itemId.equals(id) & u.factorMilli.equals(1000)))
          .write(ItemUnitsCompanion(
        salePrice: Value(salePrice),
        name: (baseUnitName == null || baseUnitName.trim().isEmpty)
            ? const Value.absent()
            : Value(baseUnitName.trim()),
        updatedAt: Value(nowMs()),
        deviceId: Value(DeviceInfo.id),
      ));
      if (newStockMilli != null) {
        final diff = newStockMilli - await stockOf(id);
        if (diff != 0) {
          await into(stockMovements).insert(StockMovementsCompanion.insert(
            itemId: id,
            qtyMilli: diff,
            reason: 'count',
            note: const Value('تسوية يدوية'),
          ));
          await logAudit('stock_adjust',
              userId: userId, refId: id, details: 'diff=$diff');
        }
      }
    });
  }

  // ---------- المستخدمون والدخول ----------

  String _newSalt() {
    final r = Random.secure();
    return base64.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// تجزئة مكرّرة SHA-256 مع ملح. (يمكن استبدالها بـ PBKDF2/Argon2 لاحقًا.)
  String _hashPin(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < 5000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64.encode(bytes);
  }

  Future<bool> hasUsers() async {
    final rows = await (select(users)
          ..where((u) => u.isDeleted.equals(false) & u.active.equals(true)))
        .get();
    return rows.isNotEmpty;
  }

  Stream<List<User>> watchUsers({bool onlyActive = true}) {
    final q = select(users)
      ..where((u) => u.isDeleted.equals(false))
      ..orderBy([(u) => OrderingTerm.asc(u.name)]);
    return q.watch().map((l) => onlyActive ? l.where((u) => u.active).toList() : l);
  }

  Future<User> createUser({
    required String name,
    required String role,
    required String pin,
  }) async {
    final salt = _newSalt();
    final id = newId();
    await into(users).insert(UsersCompanion.insert(
      id: Value(id),
      name: name,
      role: Value(role),
      pinSalt: Value(salt),
      pinHash: Value(_hashPin(pin, salt)),
    ));
    return (select(users)..where((u) => u.id.equals(id))).getSingle();
  }

  Future<User?> verifyPin(String userId, String pin) async {
    final usr = await (select(users)
          ..where((u) => u.id.equals(userId) & u.active.equals(true)))
        .getSingleOrNull();
    if (usr == null || usr.pinSalt == null || usr.pinHash == null) return null;
    return _hashPin(pin, usr.pinSalt!) == usr.pinHash ? usr : null;
  }

  Future<void> changePin(String userId, String pin) async {
    final salt = _newSalt();
    await (update(users)..where((u) => u.id.equals(userId))).write(UsersCompanion(
      pinSalt: Value(salt),
      pinHash: Value(_hashPin(pin, salt)),
      updatedAt: Value(nowMs()),
      deviceId: Value(DeviceInfo.id),
    ));
  }

  Future<void> setUserActive(String userId, bool active) async {
    await (update(users)..where((u) => u.id.equals(userId))).write(UsersCompanion(
      active: Value(active),
      updatedAt: Value(nowMs()),
      deviceId: Value(DeviceInfo.id),
    ));
  }

  // ---------- سجل التدقيق ----------

  Future<void> logAudit(String action,
      {String? userId, String? refId, String? details}) async {
    await into(auditLogs).insert(AuditLogsCompanion.insert(
      action: action,
      userId: Value(userId),
      refId: Value(refId),
      details: Value(details),
    ));
  }

  // ---------- الباركود والوحدات المتعددة ----------

  Future<bool> _barcodeTaken(String code) async {
    final rows = await (select(itemBarcodes)
          ..where((b) => b.code.equals(code) & b.isDeleted.equals(false)))
        .get();
    return rows.isNotEmpty;
  }

  Future<int> _factorOf(String? unitId) async {
    if (unitId == null) return 1000;
    final u = await (select(itemUnits)..where((x) => x.id.equals(unitId)))
        .getSingleOrNull();
    return u?.factorMilli ?? 1000;
  }

  Future<int> _returnedQty(String lineId) async {
    final r = await customSelect(
      'SELECT COALESCE(SUM(qty_milli), 0) AS s FROM sale_returns '
      'WHERE sale_line_id = ?1 AND is_deleted = 0',
      variables: [Variable.withString(lineId)],
      readsFrom: {saleReturns},
    ).getSingle();
    return r.read<int>('s');
  }

  Future<List<ItemUnit>> unitsOf(String itemId) {
    return (select(itemUnits)
          ..where((u) => u.itemId.equals(itemId) & u.isDeleted.equals(false))
          ..orderBy([(u) => OrderingTerm.asc(u.factorMilli)]))
        .get();
  }

  Stream<List<ItemUnit>> watchUnits(String itemId) {
    return (select(itemUnits)
          ..where((u) => u.itemId.equals(itemId) & u.isDeleted.equals(false))
          ..orderBy([(u) => OrderingTerm.asc(u.factorMilli)]))
        .watch();
  }

  Future<ItemUnit> defaultUnit(String itemId) async {
    final units = await unitsOf(itemId);
    return units.firstWhere(
      (u) => u.isDefault,
      orElse: () => units.firstWhere((u) => u.factorMilli == 1000,
          orElse: () => units.first),
    );
  }

  /// يبحث بالباركود ويعيد الصنف والوحدة المرتبطة بهذا الباركود.
  Future<ItemMatch?> matchBarcode(String code) async {
    final rows = await (select(itemBarcodes)
          ..where((b) => b.code.equals(code) & b.isDeleted.equals(false)))
        .get();
    if (rows.isEmpty) return null;
    final bc = rows.first;
    final item = await (select(items)
          ..where((i) =>
              i.id.equals(bc.itemId) &
              i.isDeleted.equals(false) &
              i.active.equals(true)))
        .getSingleOrNull();
    if (item == null) return null;
    ItemUnit? unit;
    if (bc.unitId != null) {
      unit = await (select(itemUnits)
            ..where((u) => u.id.equals(bc.unitId!) & u.isDeleted.equals(false)))
          .getSingleOrNull();
    }
    unit ??= await defaultUnit(item.id);
    return ItemMatch(item, unit);
  }

  Future<void> addUnit({
    required String itemId,
    required String name,
    required int factorMilli,
    required int salePrice,
    String? barcode,
  }) {
    return transaction(() async {
      if (factorMilli <= 0 || factorMilli == 1000) {
        throw StateError('عامل التحويل يجب أن يكون أكبر من صفر وغير 1');
      }
      final code = barcode?.trim() ?? '';
      if (code.isNotEmpty && await _barcodeTaken(code)) {
        throw StateError('الباركود مستخدم لصنف آخر');
      }
      final id = newId();
      await into(itemUnits).insert(ItemUnitsCompanion.insert(
        id: Value(id),
        itemId: itemId,
        name: name,
        factorMilli: factorMilli,
        salePrice: salePrice,
      ));
      if (code.isNotEmpty) {
        await into(itemBarcodes).insert(ItemBarcodesCompanion.insert(
            itemId: itemId, unitId: Value(id), code: code));
      }
    });
  }

  Future<void> setDefaultUnit(String itemId, String unitId) {
    return transaction(() async {
      await (update(itemUnits)..where((u) => u.itemId.equals(itemId))).write(
          ItemUnitsCompanion(
              isDefault: const Value(false),
              updatedAt: Value(nowMs()),
              deviceId: Value(DeviceInfo.id)));
      await (update(itemUnits)..where((u) => u.id.equals(unitId))).write(
          ItemUnitsCompanion(
              isDefault: const Value(true),
              updatedAt: Value(nowMs()),
              deviceId: Value(DeviceInfo.id)));
    });
  }

  Future<void> deleteUnit(String unitId) {
    return transaction(() async {
      final u = await (select(itemUnits)..where((x) => x.id.equals(unitId)))
          .getSingle();
      if (u.factorMilli == 1000) {
        throw StateError('لا يمكن حذف الوحدة الأساسية');
      }
      await (update(itemUnits)..where((x) => x.id.equals(unitId))).write(
          ItemUnitsCompanion(
              isDeleted: const Value(true),
              isDefault: const Value(false),
              updatedAt: Value(nowMs()),
              deviceId: Value(DeviceInfo.id)));
      await (update(itemBarcodes)..where((b) => b.unitId.equals(unitId))).write(
          ItemBarcodesCompanion(
              isDeleted: const Value(true),
              updatedAt: Value(nowMs()),
              deviceId: Value(DeviceInfo.id)));
      if (u.isDefault) {
        await (update(itemUnits)
              ..where((x) =>
                  x.itemId.equals(u.itemId) &
                  x.factorMilli.equals(1000) &
                  x.isDeleted.equals(false)))
            .write(ItemUnitsCompanion(
                isDefault: const Value(true),
                updatedAt: Value(nowMs()),
                deviceId: Value(DeviceInfo.id)));
      }
    });
  }

  // ---------- المرتجع الجزئي ----------

  /// [qtyByLine]: معرّف سطر الفاتورة ← كمية المرتجع (بوحدة السطر ×1000).
  /// يرجّع المخزون ويسجّل قيمة الاسترداد (موزَّعة بنسبة خصم الفاتورة).
  /// يعيد إجمالي قيمة المرتجع. يرمي StateError عند كمية غير صالحة.
  Future<int> returnItems(String saleId, Map<String, int> qtyByLine,
      {String? userId}) {
    return transaction(() async {
      final sale =
          await (select(sales)..where((s) => s.id.equals(saleId))).getSingle();
      if (sale.status != 'completed') {
        throw StateError('الفاتورة ملغاة، لا يمكن عمل مرتجع');
      }
      final lines = await (select(saleLines)
            ..where((l) => l.saleId.equals(saleId) & l.isDeleted.equals(false)))
          .get();
      final share = sale.subtotal > 0 ? sale.total / sale.subtotal : 1.0;
      var refundTotal = 0;
      for (final l in lines) {
        final q = qtyByLine[l.id] ?? 0;
        if (q <= 0) continue;
        final returned = await _returnedQty(l.id);
        if (q > l.qtyMilli - returned) {
          throw StateError('كمية المرتجع أكبر من المتاح في الفاتورة');
        }
        final refund = (l.unitPrice * q / 1000 * share).round();
        final factor = await _factorOf(l.unitId);
        await into(saleReturns).insert(SaleReturnsCompanion.insert(
          saleId: saleId,
          saleLineId: l.id,
          qtyMilli: q,
          refundAmount: refund,
          returnedAt: nowMs(),
          userId: Value(userId),
        ));
        await into(stockMovements).insert(StockMovementsCompanion.insert(
          itemId: l.itemId,
          qtyMilli: (q * factor / 1000).round(),
          reason: 'return',
          refId: Value(saleId),
          note: Value('مرتجع فاتورة ${sale.number}'),
        ));
        refundTotal += refund;
      }
      if (refundTotal > 0) {
        await logAudit('return',
            userId: userId, refId: saleId, details: '${sale.number}: $refundTotal');
      }
      return refundTotal;
    });
  }

  // ---------- الموردون والتوريد ----------

  Stream<List<SupplierRow>> watchSuppliers() {
    return customSelect(
      '''
SELECT s.id, s.name, s.phone, s.address,
  COALESCE((SELECT SUM(p.total) FROM purchases p
            WHERE p.supplier_id = s.id AND p.status = 'completed'
              AND p.is_deleted = 0), 0)
  - COALESCE((SELECT SUM(CASE WHEN y.direction = 'out' THEN y.amount ELSE -y.amount END)
              FROM payments y
              WHERE y.party_type = 'supplier' AND y.party_id = s.id
                AND y.is_deleted = 0), 0) AS balance
FROM suppliers s
WHERE s.is_deleted = 0
ORDER BY s.name
''',
      readsFrom: {suppliers, purchases, payments},
    ).watch().map((rows) => rows
        .map((r) => SupplierRow(
              r.read<String>('id'),
              r.read<String>('name'),
              r.readNullable<String>('phone'),
              r.readNullable<String>('address'),
              r.read<int>('balance'),
            ))
        .toList());
  }

  Future<String> addSupplier({
    required String name,
    String? phone,
    String? address,
  }) async {
    final id = newId();
    await into(suppliers).insert(SuppliersCompanion.insert(
      id: Value(id),
      name: name,
      phone: Value(phone),
      address: Value(address),
    ));
    return id;
  }

  Future<String> _nextPurchaseNumber() async {
    final row = await (select(counters)..where((c) => c.name.equals('purchase')))
        .getSingleOrNull();
    final next = (row?.value ?? 0) + 1;
    await into(counters).insertOnConflictUpdate(
      CountersCompanion.insert(name: 'purchase', value: next),
    );
    return 'P${DeviceInfo.prefix}-${next.toString().padLeft(4, '0')}';
  }

  Stream<List<PurchaseRow>> watchPurchases() {
    return customSelect(
      '''
SELECT p.id, p.number, p.status, p.purchased_at, p.total, p.paid,
       s.name AS supplier_name
FROM purchases p LEFT JOIN suppliers s ON s.id = p.supplier_id
WHERE p.is_deleted = 0
ORDER BY p.purchased_at DESC
LIMIT 300
''',
      readsFrom: {purchases, suppliers},
    ).watch().map((rows) => rows
        .map((r) => PurchaseRow(
              r.read<String>('id'),
              r.read<String>('number'),
              r.read<String>('status'),
              r.readNullable<String>('supplier_name'),
              r.read<int>('purchased_at'),
              r.read<int>('total'),
              r.read<int>('paid'),
            ))
        .toList());
  }

  Future<List<PurchaseDetailLine>> purchaseLinesFor(String purchaseId) async {
    final rows = await customSelect(
      '''
SELECT i.name AS name, COALESCE(u.name, '') AS unit_name, l.qty_milli, l.unit_cost
FROM purchase_lines l
JOIN items i ON i.id = l.item_id
LEFT JOIN item_units u ON u.id = l.unit_id
WHERE l.purchase_id = ?1 AND l.is_deleted = 0
''',
      variables: [Variable.withString(purchaseId)],
      readsFrom: {purchaseLines, items, itemUnits},
    ).get();
    return rows
        .map((r) => PurchaseDetailLine(
              r.read<String>('name'),
              r.read<String>('unit_name'),
              r.read<int>('qty_milli'),
              r.read<int>('unit_cost'),
            ))
        .toList();
  }

  /// فاتورة توريد: تزيد المخزون وتحدّث تكلفة الصنف (آخر سعر شراء).
  /// بدون مورد = شراء نقدي مدفوع بالكامل. مع مورد: [paidNow] والباقي دين للمورد.
  Future<String> createPurchase({
    String? supplierId,
    required List<PurchaseLineInput> lines,
    int paidNow = 0,
    String? userId,
  }) {
    return transaction(() async {
      if (lines.isEmpty) throw StateError('لا توجد أصناف في الفاتورة');
      final total = lines.fold<int>(0, (s, l) => s + l.total);
      final paid = supplierId == null ? total : paidNow.clamp(0, total).toInt();
      final number = await _nextPurchaseNumber();
      final id = newId();
      final now = nowMs();
      await into(purchases).insert(PurchasesCompanion.insert(
        id: Value(id),
        number: number,
        supplierId: Value(supplierId),
        purchasedAt: now,
        total: total,
        paid: Value(paid),
      ));
      for (final l in lines) {
        await into(purchaseLines).insert(PurchaseLinesCompanion.insert(
          purchaseId: id,
          itemId: l.itemId,
          qtyMilli: l.qtyMilli,
          unitCost: l.unitCost,
          unitId: Value(l.unitId),
          factorMilli: Value(l.factorMilli),
        ));
        await into(stockMovements).insert(StockMovementsCompanion.insert(
          itemId: l.itemId,
          qtyMilli: (l.qtyMilli * l.factorMilli / 1000).round(),
          reason: 'purchase',
          refId: Value(id),
        ));
        // تكلفة الوحدة الأساسية = تكلفة وحدة الشراء ÷ عامل التحويل
        final baseCost = (l.unitCost * 1000 / l.factorMilli).round();
        await (update(items)..where((i) => i.id.equals(l.itemId))).write(
            ItemsCompanion(
                costPrice: Value(baseCost),
                updatedAt: Value(nowMs()),
                deviceId: Value(DeviceInfo.id)));
      }
      if (supplierId != null && paid > 0) {
        await into(payments).insert(PaymentsCompanion.insert(
          partyType: 'supplier',
          partyId: supplierId,
          direction: 'out',
          amount: paid,
          paidAt: now,
          note: Value('دفعة فاتورة توريد $number'),
        ));
      }
      await logAudit('purchase', userId: userId, refId: id, details: number);
      return number;
    });
  }

  /// إلغاء فاتورة توريد بقيد عكسي (لا يُعاد ضبط التكلفة السابقة للصنف).
  Future<void> cancelPurchase(String purchaseId, {String? userId}) {
    return transaction(() async {
      final p = await (select(purchases)..where((x) => x.id.equals(purchaseId)))
          .getSingle();
      if (p.status != 'completed') return;
      await (update(purchases)..where((x) => x.id.equals(purchaseId))).write(
          PurchasesCompanion(
              status: const Value('cancelled'),
              updatedAt: Value(nowMs()),
              deviceId: Value(DeviceInfo.id)));
      final lines = await (select(purchaseLines)
            ..where((l) => l.purchaseId.equals(purchaseId) & l.isDeleted.equals(false)))
          .get();
      for (final l in lines) {
        await into(stockMovements).insert(StockMovementsCompanion.insert(
          itemId: l.itemId,
          qtyMilli: -(l.qtyMilli * l.factorMilli / 1000).round(),
          reason: 'purchase_cancel',
          refId: Value(purchaseId),
          note: Value('إلغاء فاتورة توريد ${p.number}'),
        ));
      }
      if (p.supplierId != null && p.paid > 0) {
        await into(payments).insert(PaymentsCompanion.insert(
          partyType: 'supplier',
          partyId: p.supplierId!,
          direction: 'in',
          amount: p.paid,
          paidAt: nowMs(),
          note: Value('عكس دفعة فاتورة توريد ملغاة ${p.number}'),
        ));
      }
      await logAudit('cancel_purchase',
          userId: userId, refId: purchaseId, details: p.number);
    });
  }

  // ---------- التحصيل والسداد وكشوف الحساب ----------

  /// direction: in = تحصيل من عميل، out = سداد لمورد.
  Future<void> recordPayment({
    required String partyType,
    required String partyId,
    required String direction,
    required int amount,
    String method = 'cash',
    String? note,
    String? userId,
  }) async {
    if (amount <= 0) throw StateError('المبلغ يجب أن يكون أكبر من صفر');
    await into(payments).insert(PaymentsCompanion.insert(
      partyType: partyType,
      partyId: partyId,
      direction: direction,
      amount: amount,
      method: Value(method),
      paidAt: nowMs(),
      note: Value(note),
    ));
    await logAudit('payment_$direction',
        userId: userId, refId: partyId, details: '$partyType: $amount');
  }

  static const _methodAr = {'cash': 'نقدي', 'transfer': 'تحويل', 'cheque': 'شيك'};

  Future<List<StatementEntry>> _paymentsEntries(
      String partyType, String partyId, {required bool inIsMinus}) async {
    final rows = await customSelect(
      '''
SELECT direction, amount, paid_at, method, note FROM payments
WHERE party_type = ?1 AND party_id = ?2 AND is_deleted = 0
''',
      variables: [Variable.withString(partyType), Variable.withString(partyId)],
      readsFrom: {payments},
    ).get();
    return rows.map((r) {
      final dir = r.read<String>('direction');
      final amount = r.read<int>('amount');
      final method = _methodAr[r.read<String>('method')] ?? '';
      final note = r.readNullable<String>('note');
      final title = [
        dir == 'in' ? (inIsMinus ? 'دفعة' : 'استرداد') : (inIsMinus ? 'استرداد' : 'سداد'),
        if (method.isNotEmpty) '($method)',
        if (note != null && note.isNotEmpty) '— $note',
      ].join(' ');
      final isMinus = (dir == 'in') == inIsMinus;
      return StatementEntry(r.read<int>('paid_at'), title,
          plus: isMinus ? 0 : amount, minus: isMinus ? amount : 0);
    }).toList();
  }

  Future<List<StatementEntry>> customerStatement(String customerId) async {
    final out = <StatementEntry>[];
    final sl = await customSelect(
      '''
SELECT number, sold_at, total FROM sales
WHERE customer_id = ?1 AND type = 'credit' AND status = 'completed' AND is_deleted = 0
''',
      variables: [Variable.withString(customerId)],
      readsFrom: {sales},
    ).get();
    for (final r in sl) {
      out.add(StatementEntry(r.read<int>('sold_at'),
          'فاتورة ${r.read<String>('number')}',
          plus: r.read<int>('total')));
    }
    final rt = await customSelect(
      '''
SELECT s.number AS number, r.returned_at AS at, r.refund_amount AS amt
FROM sale_returns r JOIN sales s ON s.id = r.sale_id
WHERE s.customer_id = ?1 AND s.type = 'credit' AND s.status = 'completed'
  AND r.is_deleted = 0
''',
      variables: [Variable.withString(customerId)],
      readsFrom: {saleReturns, sales},
    ).get();
    for (final r in rt) {
      out.add(StatementEntry(r.read<int>('at'),
          'مرتجع فاتورة ${r.read<String>('number')}',
          minus: r.read<int>('amt')));
    }
    out.addAll(await _paymentsEntries('customer', customerId, inIsMinus: true));
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  Future<List<StatementEntry>> supplierStatement(String supplierId) async {
    final out = <StatementEntry>[];
    final pl = await customSelect(
      '''
SELECT number, purchased_at, total FROM purchases
WHERE supplier_id = ?1 AND status = 'completed' AND is_deleted = 0
''',
      variables: [Variable.withString(supplierId)],
      readsFrom: {purchases},
    ).get();
    for (final r in pl) {
      out.add(StatementEntry(r.read<int>('purchased_at'),
          'فاتورة توريد ${r.read<String>('number')}',
          plus: r.read<int>('total')));
    }
    // للمورد: out (سداد) ينقص المستحق، و in (استرداد/عكس) يزيده
    out.addAll(await _paymentsEntries('supplier', supplierId, inIsMinus: false));
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  // ---------- التقارير ----------

  /// [from] شاملة و[to] غير شاملة (بالملي ثانية).
  Future<ReportData> report(int from, int to) async {
    final vars = [Variable.withInt(from), Variable.withInt(to)];
    final s = await customSelect(
      '''
SELECT COALESCE(SUM(total), 0) AS t, COUNT(*) AS c,
  COALESCE(SUM(CASE WHEN type = 'cash' THEN total ELSE 0 END), 0) AS cash,
  COALESCE(SUM(CASE WHEN type = 'credit' THEN total ELSE 0 END), 0) AS credit,
  COALESCE(SUM(tax), 0) AS tax_total
FROM sales
WHERE status = 'completed' AND is_deleted = 0 AND sold_at >= ?1 AND sold_at < ?2
''',
      variables: vars,
      readsFrom: {sales},
    ).getSingle();
    final cogs = await customSelect(
      '''
SELECT CAST(COALESCE(SUM(l.unit_cost * l.qty_milli / 1000.0), 0) AS REAL) AS c
FROM sale_lines l JOIN sales s ON s.id = l.sale_id
WHERE s.status = 'completed' AND s.is_deleted = 0 AND l.is_deleted = 0
  AND s.sold_at >= ?1 AND s.sold_at < ?2
''',
      variables: vars,
      readsFrom: {saleLines, sales},
    ).getSingle();
    final ret = await customSelect(
      '''
SELECT COALESCE(SUM(r.refund_amount), 0) AS amt,
  CAST(COALESCE(SUM(l.unit_cost * r.qty_milli / 1000.0), 0) AS REAL) AS cost
FROM sale_returns r
JOIN sale_lines l ON l.id = r.sale_line_id
JOIN sales s ON s.id = r.sale_id
WHERE s.status = 'completed' AND r.is_deleted = 0
  AND r.returned_at >= ?1 AND r.returned_at < ?2
''',
      variables: vars,
      readsFrom: {saleReturns, saleLines, sales},
    ).getSingle();
    final topRows = await customSelect(
      '''
SELECT i.name AS name,
  CAST(SUM(l.unit_price * l.qty_milli / 1000.0) AS REAL) AS revenue,
  CAST(SUM(l.qty_milli * COALESCE(u.factor_milli, 1000) / 1000.0) AS REAL) AS base_qty,
  COALESCE((SELECT bu.name FROM item_units bu
            WHERE bu.item_id = i.id AND bu.factor_milli = 1000 AND bu.is_deleted = 0
            LIMIT 1), 'قطعة') AS base_unit
FROM sale_lines l
JOIN sales s ON s.id = l.sale_id
JOIN items i ON i.id = l.item_id
LEFT JOIN item_units u ON u.id = l.unit_id
WHERE s.status = 'completed' AND s.is_deleted = 0 AND l.is_deleted = 0
  AND s.sold_at >= ?1 AND s.sold_at < ?2
GROUP BY l.item_id
ORDER BY revenue DESC
LIMIT 10
''',
      variables: vars,
      readsFrom: {saleLines, sales, items, itemUnits},
    ).get();
    return ReportData(
      salesTotal: s.read<int>('t'),
      salesCount: s.read<int>('c'),
      cashTotal: s.read<int>('cash'),
      creditTotal: s.read<int>('credit'),
      taxTotal: s.read<int>('tax_total'),
      returnsTotal: ret.read<int>('amt'),
      cogs: cogs.read<double>('c').round(),
      returnsCost: ret.read<double>('cost').round(),
      top: topRows
          .map((r) => TopItem(
                r.read<String>('name'),
                r.read<double>('revenue').round(),
                r.read<double>('base_qty').round(),
                r.read<String>('base_unit'),
              ))
          .toList(),
    );
  }

  /// قيمة المخزون بسعر التكلفة (للأصناف ذات الرصيد الموجب فقط).
  Future<int> inventoryValue() async {
    final r = await customSelect(
      '''
SELECT CAST(COALESCE(SUM(st * cost / 1000.0), 0) AS REAL) AS v FROM (
  SELECT i.cost_price AS cost,
    (SELECT COALESCE(SUM(m.qty_milli), 0) FROM stock_movements m
     WHERE m.item_id = i.id AND m.is_deleted = 0) AS st
  FROM items i WHERE i.is_deleted = 0 AND i.active = 1
) WHERE st > 0
''',
      readsFrom: {items, stockMovements},
    ).getSingle();
    return r.read<double>('v').round();
  }

  Future<int> receivablesTotal() async {
    final list = await watchCustomers().first;
    return list.where((c) => c.balance > 0).fold<int>(0, (s, c) => s + c.balance);
  }

  Future<int> payablesTotal() async {
    final list = await watchSuppliers().first;
    return list.where((c) => c.balance > 0).fold<int>(0, (s, c) => s + c.balance);
  }

  /// أصناف رصيدها صفر/سالب أو وصل لحد إعادة الطلب.
  Future<List<ItemRow>> lowStockItems() async {
    final all = await watchItems('').first;
    return all
        .where((i) => i.stockMilli <= (i.reorderMilli > 0 ? i.reorderMilli : 0))
        .toList();
  }

  // ---------- الباركود والطباعة والجرد ----------

  Future<ItemRow?> itemRowById(String id) async {
    final l = await watchItems('', onlyId: id).first;
    return l.isEmpty ? null : l.first;
  }

  Future<List<ItemBarcode>> barcodesOf(String itemId) {
    return (select(itemBarcodes)
          ..where((b) => b.itemId.equals(itemId) & b.isDeleted.equals(false)))
        .get();
  }

  Future<String> _newInternalCode() async {
    final r = Random.secure();
    for (var i = 0; i < 20; i++) {
      final code = '29${List.generate(9, (_) => r.nextInt(10)).join()}';
      if (!await _barcodeTaken(code)) return code;
    }
    throw StateError('تعذّر توليد باركود فريد');
  }

  /// يعيد باركود الوحدة، وإن لم يوجد يولّد باركودًا داخليًا (للملصقات).
  Future<String> ensureBarcode(String itemId, String unitId) async {
    final unit = await (select(itemUnits)..where((u) => u.id.equals(unitId)))
        .getSingle();
    final rows = await barcodesOf(itemId);
    for (final b in rows) {
      if (b.unitId == unitId || (b.unitId == null && unit.isDefault)) {
        return b.code;
      }
    }
    final code = await _newInternalCode();
    await into(itemBarcodes).insert(ItemBarcodesCompanion.insert(
      itemId: itemId,
      unitId: Value(unitId),
      code: code,
      generated: const Value(true),
    ));
    return code;
  }

  Future<void> addBarcode({
    required String itemId,
    String? unitId,
    required String code,
  }) async {
    final c = code.trim();
    if (c.isEmpty) throw StateError('اكتب الباركود');
    if (await _barcodeTaken(c)) throw StateError('الباركود مستخدم لصنف آخر');
    await into(itemBarcodes).insert(
        ItemBarcodesCompanion.insert(itemId: itemId, unitId: Value(unitId), code: c));
  }

  Future<void> removeBarcode(String barcodeId) async {
    await (update(itemBarcodes)..where((b) => b.id.equals(barcodeId))).write(
        ItemBarcodesCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(nowMs()),
            deviceId: Value(DeviceInfo.id)));
  }

  /// تسوية المخزون إلى كمية فعلية (بالوحدة الأساسية ×1000) بحركة جرد.
  Future<void> adjustStockTo(String itemId, int newMilli,
      {String? userId, String note = 'جرد'}) {
    return transaction(() async {
      final diff = newMilli - await stockOf(itemId);
      if (diff == 0) return;
      await into(stockMovements).insert(StockMovementsCompanion.insert(
        itemId: itemId,
        qtyMilli: diff,
        reason: 'count',
        note: Value(note),
      ));
      await logAudit('stock_adjust',
          userId: userId, refId: itemId, details: 'diff=$diff');
    });
  }

  Future<InvoiceData> invoiceForPrint(String saleId) async {
    final sale =
        await (select(sales)..where((s) => s.id.equals(saleId))).getSingle();
    String? cname, cphone, uname;
    int? balance;
    if (sale.customerId != null) {
      final c = await (select(customers)..where((x) => x.id.equals(sale.customerId!)))
          .getSingleOrNull();
      cname = c?.name;
      cphone = c?.phone;
      final all = await watchCustomers().first;
      balance = all.where((x) => x.id == sale.customerId).firstOrNull?.balance;
    }
    if (sale.userId != null) {
      final u = await (select(users)..where((x) => x.id.equals(sale.userId!)))
          .getSingleOrNull();
      uname = u?.name;
    }
    return InvoiceData(
      number: sale.number,
      type: sale.type,
      status: sale.status,
      soldAt: sale.soldAt,
      subtotal: sale.subtotal,
      discount: sale.discount,
      tax: sale.tax,
      total: sale.total,
      paid: sale.paid,
      customerName: cname,
      customerPhone: cphone,
      cashierName: uname,
      customerBalance: balance,
      lines: await saleLinesFor(saleId),
    );
  }

  // ---------- المزامنة: سجل التغييرات والتطبيق ----------

  /// الجداول التي تُزامَن (كلها بحقول SyncColumns).
  static const syncTables = [
    'users',
    'categories',
    'items',
    'item_units',
    'item_barcodes',
    'stock_movements',
    'customers',
    'suppliers',
    'sales',
    'sale_lines',
    'payments',
    'purchases',
    'purchase_lines',
    'sale_returns',
    'audit_logs',
  ];

  /// جداول إضافة فقط: تُدرَج إن لم يكن الـ id موجودًا ولا تُعدَّل بالمزامنة.
  static const _appendOnly = {
    'stock_movements',
    'payments',
    'sale_lines',
    'purchase_lines',
    'sale_returns',
    'audit_logs',
  };

  final Map<String, Set<String>> _colCache = {};

  /// ينشئ change_log وsync_flags ومشغّلات تسجّل كل إدراج/تعديل.
  /// origin = '' للتعديل المحلي، ومعرّف الجهاز عند تطبيق صفوف قادمة من المزامنة.
  Future<void> _createSyncInfra({required bool backfill}) async {
    await customStatement(
        "CREATE TABLE IF NOT EXISTS change_log (seq INTEGER PRIMARY KEY AUTOINCREMENT, tbl TEXT NOT NULL, row_id TEXT NOT NULL, origin TEXT NOT NULL DEFAULT '')");
    await customStatement(
        "CREATE TABLE IF NOT EXISTS sync_flags (id INTEGER PRIMARY KEY, origin TEXT NOT NULL DEFAULT '')");
    await customStatement("INSERT OR IGNORE INTO sync_flags (id, origin) VALUES (1, '')");
    for (final t in syncTables) {
      for (final ev in ['INSERT', 'UPDATE']) {
        await customStatement(
            "CREATE TRIGGER IF NOT EXISTS trg_${t}_${ev.toLowerCase()} AFTER $ev ON $t BEGIN "
            "INSERT INTO change_log (tbl, row_id, origin) "
            "VALUES ('$t', NEW.id, (SELECT origin FROM sync_flags WHERE id = 1)); END");
      }
      if (backfill) {
        await customStatement(
            "INSERT INTO change_log (tbl, row_id, origin) SELECT '$t', id, '' FROM $t");
      }
    }
  }

  Future<Set<String>> _columnsOf(String table) async {
    final cached = _colCache[table];
    if (cached != null) return cached;
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return _colCache[table] = rows.map((r) => r.read<String>('name')).toSet();
  }

  Future<List<Map<String, dynamic>>> _rowsFor(
      Iterable<(String, String)> keys) async {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final (t, id) in keys) {
      if (!syncTables.contains(t) || !seen.add('$t|$id')) continue;
      final r = await customSelect('SELECT * FROM $t WHERE id = ?1',
              variables: [Variable.withString(id)])
          .getSingleOrNull();
      if (r != null) out.add({'t': t, 'd': Map<String, dynamic>.from(r.data)});
    }
    return out;
  }

  /// تغييرات هذا الجهاز التي لم تُدفع بعد (origin فارغ فقط).
  Future<({List<Map<String, dynamic>> rows, int maxSeq, bool full})>
      collectLocalChanges(int afterSeq, {int limit = 500}) async {
    final e = await customSelect(
      "SELECT seq, tbl, row_id FROM change_log "
      "WHERE seq > ?1 AND origin = '' ORDER BY seq LIMIT ?2",
      variables: [Variable.withInt(afterSeq), Variable.withInt(limit)],
    ).get();
    if (e.isEmpty) {
      return (rows: <Map<String, dynamic>>[], maxSeq: afterSeq, full: false);
    }
    final rows = await _rowsFor(
        e.map((r) => (r.read<String>('tbl'), r.read<String>('row_id'))));
    return (rows: rows, maxSeq: e.last.read<int>('seq'), full: e.length >= limit);
  }

  /// (للجهاز الرئيسي) تغييرات بعد [cursor] بدون ما مصدره الجهاز نفسه.
  Future<({List<Map<String, dynamic>> rows, int next, bool more})>
      collectChangesForPeer(int cursor, String peerId, {int limit = 500}) async {
    final e = await customSelect(
      'SELECT seq, tbl, row_id, origin FROM change_log '
      'WHERE seq > ?1 ORDER BY seq LIMIT ?2',
      variables: [Variable.withInt(cursor), Variable.withInt(limit)],
    ).get();
    if (e.isEmpty) {
      return (rows: <Map<String, dynamic>>[], next: cursor, more: false);
    }
    final keys = <(String, String)>[
      for (final r in e)
        if (r.read<String>('origin') != peerId)
          (r.read<String>('tbl'), r.read<String>('row_id')),
    ];
    return (
      rows: await _rowsFor(keys),
      next: e.last.read<int>('seq'),
      more: e.length >= limit
    );
  }

  /// يطبّق صفوفًا قادمة من الطرف الآخر بقواعد التعارض:
  /// جداول الإضافة فقط: إدراج إن لم يوجد. الباقي: الحذف يفوز، وإلا الأحدث (updated_at ثم device_id).
  /// يعيد عدد الصفوف التي طُبِّقت فعلًا.
  Future<int> applyRemoteRows(
      List<Map<String, dynamic>> rows, String origin) async {
    final touched = <String>{};
    final n = await transaction(() async {
      await customStatement(
          'UPDATE sync_flags SET origin = ? WHERE id = 1', [origin]);
      var applied = 0;
      for (final r in rows) {
        final t = r['t'];
        final d = r['d'];
        if (t is! String || d is! Map) continue;
        if (await _applyRow(t, Map<String, dynamic>.from(d))) {
          applied++;
          touched.add(t);
        }
      }
      await customStatement("UPDATE sync_flags SET origin = '' WHERE id = 1");
      return applied;
    });
    if (touched.isNotEmpty) {
      notifyUpdates({for (final t in touched) TableUpdate(t)});
    }
    return n;
  }

  Future<bool> _applyRow(String table, Map<String, dynamic> d) async {
    if (!syncTables.contains(table)) return false;
    final id = d['id'];
    if (id is! String || id.isEmpty) return false;
    final cols = await _columnsOf(table);
    final local = await customSelect(
      'SELECT updated_at, device_id, is_deleted FROM $table WHERE id = ?1',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();
    if (local != null) {
      if (_appendOnly.contains(table)) return false;
      final lDel = local.read<int>('is_deleted') == 1;
      final rDel = d['is_deleted'] == 1 || d['is_deleted'] == true;
      final lu = local.read<int>('updated_at');
      final ru = (d['updated_at'] as num?)?.toInt() ?? 0;
      final ld = local.read<String>('device_id');
      final rd = (d['device_id'] as String?) ?? '';
      final bool useRemote;
      if (rDel && !lDel) {
        useRemote = true;
      } else if (lDel && !rDel) {
        useRemote = false;
      } else {
        useRemote = ru > lu || (ru == lu && rd.compareTo(ld) > 0);
      }
      if (!useRemote) return false;
    }
    final keys = d.keys.where(cols.contains).toList();
    if (!keys.contains('id')) return false;
    await customStatement(
      'INSERT OR REPLACE INTO $table (${keys.join(',')}) '
      'VALUES (${List.filled(keys.length, '?').join(',')})',
      [
        for (final k in keys) d[k] is bool ? ((d[k] as bool) ? 1 : 0) : d[k],
      ],
    );
    return true;
  }

  // ---------- المزامنة: الأجهزة المقترنة (الجهاز الرئيسي) ----------

  Future<({String key, String prefix})> registerPairedDevice({
    required String id,
    required String name,
    required String kind,
  }) async {
    final r = Random.secure();
    final key = base64.encode(List<int>.generate(32, (_) => r.nextInt(256)));
    final existing = await (select(devices)..where((d) => d.id.equals(id)))
        .getSingleOrNull();
    var prefix = existing?.prefix ?? '';
    if (prefix.isEmpty) {
      final all = await (select(devices)..where((d) => d.isDeleted.equals(false))).get();
      final used = all.map((d) => d.prefix).whereType<String>().toSet();
      var n = all.where((d) => d.kind == 'mobile').length + 1;
      while (used.contains('M$n')) {
        n++;
      }
      prefix = 'M$n';
    }
    if (existing == null) {
      await into(devices).insert(DevicesCompanion.insert(
        id: Value(id),
        name: name,
        kind: kind,
        sharedKey: Value(key),
        prefix: Value(prefix),
      ));
    } else {
      await (update(devices)..where((d) => d.id.equals(id))).write(DevicesCompanion(
        name: Value(name),
        sharedKey: Value(key),
        prefix: Value(prefix),
        isDeleted: const Value(false),
        updatedAt: Value(nowMs()),
      ));
    }
    return (key: key, prefix: prefix);
  }

  Future<Device?> deviceById(String id) {
    return (select(devices)
          ..where((d) => d.id.equals(id) & d.isDeleted.equals(false)))
        .getSingleOrNull();
  }

  Stream<List<Device>> watchDevices() {
    return (select(devices)
          ..where((d) => d.isDeleted.equals(false))
          ..orderBy([(d) => OrderingTerm.asc(d.name)]))
        .watch();
  }

  Future<void> touchDeviceSync(String id) async {
    await (update(devices)..where((d) => d.id.equals(id)))
        .write(DevicesCompanion(lastSyncAt: Value(nowMs())));
  }

  /// فصل جهاز: يُلغى مفتاحه فلا يستطيع المزامنة.
  Future<void> removeDevice(String id) async {
    await (update(devices)..where((d) => d.id.equals(id))).write(
        DevicesCompanion(
            isDeleted: const Value(true),
            sharedKey: const Value(null),
            updatedAt: Value(nowMs())));
  }

  /// معرّف «حقبة» المزامنة للجهاز الرئيسي؛ يتغيّر عند استعادة نسخة احتياطية
  /// فتعيد الأجهزة الأخرى سحب كل شيء بدل الاعتماد على مؤشر قديم.
  Future<String> syncEpoch() async {
    var e = await getSetting('sync_epoch');
    if (e == null || e.isEmpty) {
      e = newId();
      await setSetting('sync_epoch', e);
    }
    return e;
  }
}
