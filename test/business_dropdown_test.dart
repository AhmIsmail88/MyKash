import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/data/database.dart';
import 'package:mykash/data/providers.dart';
import 'package:mykash/features/auth/auth_gate.dart';

void main() {
  testWidgets('the business dropdown opens and keeps the chosen value',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.initDevice(isMobile: false);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: Scaffold(body: SetupView())),
    ));
    await tester.pumpAndSettle();

    // The control starts on the generic profile.
    expect(find.text('عام'), findsOneWidget);

    await tester.tap(find.text('عام'));
    await tester.pumpAndSettle();

    final feed = find.text('أعلاف وكيماويات');
    expect(feed, findsWidgets, reason: 'menu did not open');

    await tester.tap(feed.last);
    await tester.pumpAndSettle();

    expect(find.text('أعلاف وكيماويات'), findsOneWidget,
        reason: 'selection did not stick');

    await db.close();
  });
}