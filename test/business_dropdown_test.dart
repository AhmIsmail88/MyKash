import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';
import 'package:mykash/data/providers.dart';
import 'package:mykash/features/auth/auth_gate.dart';

void main() {
  /// Mirrors the real mounting: AuthGate sits in `MaterialApp.builder`, i.e.
  /// ABOVE the navigator. This is what used to break the dropdown menu.
  testWidgets('setup dropdown works when the gate is mounted in builder',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.initDevice(isMobile: false);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        builder: (context, child) =>
            AuthGate(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('app')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('عام'), findsOneWidget,
        reason: 'the setup screen should be visible');

    await tester.tap(find.text('عام'));
    await tester.pumpAndSettle();

    final feed = find.text('أعلاف وكيماويات');
    expect(feed, findsWidgets, reason: 'dropdown menu did not open');

    await tester.tap(feed.last);
    await tester.pumpAndSettle();

    expect(find.text('أعلاف وكيماويات'), findsOneWidget,
        reason: 'selection did not stick');

    await db.close();
  });
}