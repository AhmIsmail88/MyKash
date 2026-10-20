import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/session.dart';
import 'features/backup/backup_screen.dart';
import 'features/license/license_gate.dart';
import 'features/count/count_screen.dart';
import 'features/customers/customers_screen.dart';
import 'features/home/home_screen.dart';
import 'features/payments/payments_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/suppliers/suppliers_screen.dart';
import 'features/sync/sync_screen.dart';
import 'features/invoices/invoices_screen.dart';
import 'features/items/items_screen.dart';
import 'features/sales/sales_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shift/shift_screen.dart';

final GoRouter _router = GoRouter(
  initialLocation: '/sales',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/sales', builder: (_, __) => const SalesScreen()),
        GoRoute(path: '/items', builder: (_, __) => const ItemsScreen()),
        GoRoute(path: '/customers', builder: (_, __) => const CustomersScreen()),
        GoRoute(path: '/invoices', builder: (_, __) => const InvoicesScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/suppliers', builder: (_, __) => const SuppliersScreen()),
        GoRoute(path: '/payments', builder: (_, __) => const PaymentsScreen()),
        GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
        GoRoute(path: '/shift', builder: (_, __) => const ShiftScreen()),
        GoRoute(path: '/count', builder: (_, __) => const CountScreen()),
        GoRoute(path: '/backup', builder: (_, __) => const BackupScreen()),
        GoRoute(path: '/sync', builder: (_, __) => const SyncScreen()),
      ],
    ),
  ],
);

class MyKashApp extends StatelessWidget {
  const MyKashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MyKash',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
      builder: (context, child) =>
          IdleLock(
        child: AuthGate(
          child: LicenseGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

/// قفل تلقائي بعد فترة خمول (لمس أو ضغط مفاتيح، فقارئ الباركود USB يُحسب نشاطًا).
class IdleLock extends ConsumerStatefulWidget {
  final Widget child;
  const IdleLock({super.key, required this.child});

  @override
  ConsumerState<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends ConsumerState<IdleLock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent e) {
    _reset();
    return false;
  }

  void _reset() {
    _timer?.cancel();
    final minutes = ref.read(lockMinutesProvider);
    if (minutes <= 0 || ref.read(sessionProvider) == null) return;
    _timer = Timer(Duration(minutes: minutes),
        () => ref.read(sessionProvider.notifier).logout());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, __) => _reset());
    ref.listen(lockMinutesProvider, (_, __) => _reset());
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reset(),
      onPointerMove: (_) => _reset(),
      child: widget.child,
    );
  }
}

class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('هذه الشاشة قيد التطوير في مرحلة لاحقة'));
}
