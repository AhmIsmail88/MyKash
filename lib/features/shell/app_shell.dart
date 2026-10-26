import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../sync/sync_providers.dart';
import '../auth/session.dart';
import '../license/license_panel.dart';
import '../shift/shift_screen.dart';

class _Dest {
  final String path, title;
  final IconData icon;
  final bool adminOnly;
  const _Dest(this.path, this.title, this.icon, {this.adminOnly = false});
}

const _destinations = <_Dest>[
  _Dest('/home', 'الرئيسية', Icons.home_outlined),
  _Dest('/sales', 'البيع', Icons.point_of_sale),
  _Dest('/shift', 'الوردية', Icons.request_quote_outlined),
  _Dest('/items', 'الأصناف والمخزون', Icons.inventory_2_outlined),
  _Dest('/customers', 'العملاء', Icons.people_outline),
  _Dest('/count', 'الجرد', Icons.fact_check_outlined, adminOnly: true),
  _Dest('/expiry', 'الصلاحية', Icons.event_busy_outlined),
  _Dest('/suppliers', 'الموردون والتوريد', Icons.local_shipping_outlined,
      adminOnly: true),
  _Dest('/payments', 'التحصيل والمديونيات',
      Icons.account_balance_wallet_outlined),
  _Dest('/invoices', 'الفواتير', Icons.receipt_long_outlined),
  _Dest('/reports', 'التقارير', Icons.bar_chart, adminOnly: true),
  _Dest('/sync', 'المزامنة', Icons.sync),
  _Dest('/backup', 'النسخ الاحتياطي', Icons.backup_outlined, adminOnly: true),
  _Dest('/settings', 'الإعدادات', Icons.settings_outlined, adminOnly: true),
];

/// قائمة جانبية ثابتة على الشاشات العريضة، وDrawer على الشاشات الضيقة.
/// الكاشير لا يرى شاشات المدير (التقارير، الإعدادات، التوريد).
class AppShell extends ConsumerWidget {
  final String location;
  final Widget child;
  const AppShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final syncState = ref.watch(syncControllerProvider);
    final lic = ref.watch(licenseStatusProvider).valueOrNull;
    Widget wrapBody(Widget c) => Column(children: [
          if (lic != null && lic.showBanner)
            Material(
              color: const Color(0xFFFFF3CD),
              child: ListTile(
                dense: true,
                title: Text(lic.text),
                trailing: (session?.isAdmin ?? false)
                    ? TextButton(
                        onPressed: () => context.go('/settings'),
                        child: const Text('تفعيل'))
                    : null,
              ),
            ),
          Expanded(child: c),
        ]);
    final isAdmin = session?.isAdmin ?? false;
    final visible = [
      for (final d in _destinations)
        if (!d.adminOnly || isAdmin) d
    ];
    final current = _destinations.firstWhere(
      (d) => location.startsWith(d.path),
      orElse: () => _destinations.first,
    );

    PreferredSizeWidget appBar() => AppBar(
          title: Text(current.title,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            const _ShiftChip(),
            if (session != null)
              Center(
                child: Text(session.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            IconButton(
              tooltip: 'قفل الشاشة',
              icon: const Icon(Icons.lock_outline),
              onPressed: () => ref.read(sessionProvider.notifier).logout(),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF08503F),
                  minimumSize: const Size(0, 44),
                ),
                onPressed: syncState.running
                    ? null
                    : () async {
                        final c = ref.read(syncControllerProvider.notifier);
                        // الديسك توب هو الرئيسي: يفتح شاشة المزامنة. الموبايل غير المرتبط كذلك.
                        if (isHubPlatform || !await c.isPaired()) {
                          if (context.mounted) context.go('/sync');
                          return;
                        }
                        final r = await c.syncNow();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(r.message)));
                        }
                      },
                icon: syncState.running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync),
                label: const Text('مزامنة'),
              ),
            ),
          ],
        );

    Widget navList(BuildContext ctx, {required bool dark}) {
      final fg = dark ? const Color(0xFFC9D6D1) : kInk;
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final d in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ListTile(
                leading: Icon(d.icon,
                    color: current.path == d.path ? Colors.white : fg),
                title: Text(d.title,
                    style: TextStyle(
                        color: current.path == d.path ? Colors.white : fg,
                        fontWeight: FontWeight.w600)),
                selected: current.path == d.path,
                selectedTileColor: kGreen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                onTap: () {
                  final sc = Scaffold.of(ctx);
                  if (sc.hasDrawer && sc.isDrawerOpen) Navigator.of(ctx).pop();
                  context.go(d.path);
                },
              ),
            ),
        ],
      );
    }

    final wide = MediaQuery.of(context).size.width >= 900;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            Container(
              width: 250,
              color: kInk,
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const _BrandHeader(light: true),
                  Expanded(
                      child:
                          Builder(builder: (ctx) => navList(ctx, dark: true))),
                ],
              ),
            ),
            Expanded(child: Scaffold(appBar: appBar(), body: wrapBody(child))),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: appBar(),
      drawer: Drawer(
        child: SafeArea(
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: _BrandHeader(light: false),
            ),
            Expanded(
                child: Builder(builder: (ctx) => navList(ctx, dark: false))),
          ]),
        ),
      ),
      body: wrapBody(child),
    );
  }
}

/// شعار MyKash (العملة الذهبية K) مع الاسم.
class _BrandHeader extends StatelessWidget {
  final bool light;
  const _BrandHeader({required this.light});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child:
            Image.asset('assets/branding/icon_full.png', width: 38, height: 38),
      ),
      const SizedBox(width: 10),
      Text('MyKash',
          style: TextStyle(
              color: light ? Colors.white : kInk,
              fontSize: 24,
              fontWeight: FontWeight.w800)),
    ]);
  }
}

class _ShiftChip extends ConsumerWidget {
  const _ShiftChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(currentShiftProvider).valueOrNull;
    final open = shift != null;
    return TextButton.icon(
      onPressed: () => context.go('/shift'),
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      icon: Icon(open ? Icons.point_of_sale : Icons.lock_open, size: 18),
      label: Text(open ? shift.number : 'بدون وردية',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
