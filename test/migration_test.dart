import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';

import 'generated/schema.dart';

/// Guards the schema against accidental breakage.
///
/// Every change must bump `currentSchema`, add an additive `onUpgrade` step and
/// freeze a new snapshot in `drift_schemas/`. See docs/DB_MIGRATIONS.md.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('a fresh database matches the current schema snapshot', () async {
    final connection = await verifier.startAt(currentSchemaForTests);
    final db = AppDatabase.forTesting(connection);
    await verifier.migrateAndValidate(db, currentSchemaForTests);
    await db.close();
  });

  test('upgrade from v4 to v5 keeps the declared schema', () async {
    final connection = await verifier.startAt(4);
    final db = AppDatabase.forTesting(connection);
    await verifier.migrateAndValidate(db, 5);
    await db.close();
  });

  test('every business table exists after creation', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.initDevice(isMobile: false);

    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final tables = rows.map((r) => r.read<String>('name')).toSet();

    for (final expected in _expectedTables) {
      expect(tables, contains(expected), reason: 'table "$expected" is missing');
    }
    await db.close();
  });

  test('shop data survives closing and reopening the database', () async {
    final dir = Directory.systemTemp.createTempSync('mykash_schema');
    final file = File('${dir.path}${Platform.pathSeparator}mykash.sqlite');

    var db = AppDatabase.forTesting(NativeDatabase(file));
    await db.initDevice(isMobile: false);
    await db.addItem(name: 'Persisted', salePrice: 1000, openingQtyMilli: 1000);
    final before = await db.stockOf((await db.watchItems('').first)
        .firstWhere((i) => i.name == 'Persisted')
        .id);
    expect(before, 1000);
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(file));
    await db.initDevice(isMobile: false);
    final items = await db.watchItems('').first;
    expect(items.map((i) => i.name), contains('Persisted'));
    await db.close();

    dir.deleteSync(recursive: true);
  });

  test('schema snapshots are in sync with currentSchema', () {
    expect(GeneratedHelper.versions, contains(currentSchemaForTests),
        reason: 'drift_schemas/ has no snapshot for the current schema version. '
            'Run: dart run drift_dev schema dump lib/data/database.dart drift_schemas/');
  });
}

/// Mirrors `AppDatabase.currentSchema` so the test can reason about it.
const int currentSchemaForTests = 5;

const List<String> _expectedTables = <String>[
  'audit_logs',
  'categories',
  'change_log',
  'counters',
  'customers',
  'devices',
  'item_barcodes',
  'item_units',
  'items',
  'payments',
  'purchase_lines',
  'purchases',
  'sale_lines',
  'sale_returns',
  'sales',
  'shifts',
  'shop_settings',
  'stock_movements',
  'suppliers',
  'sync_flags',
  'users',
];