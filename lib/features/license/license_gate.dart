import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_service.dart';
import '../auth/session.dart';
import '../backup/backup_provider.dart';
import 'license_panel.dart';

/// يمنع استخدام التطبيق بعد انتهاء الترخيص/التجربة (بعد تسجيل الدخول)،
/// مع إتاحة التفعيل وتصدير نسخة احتياطية حتى لا تُحجز بيانات المحل.
class LicenseGate extends ConsumerStatefulWidget {
  final Widget child;
  const LicenseGate({super.key, required this.child});
  @override
  ConsumerState<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends ConsumerState<LicenseGate> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(hours: 1), (_) => ref.invalidate(licenseStatusProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(licenseStatusProvider).valueOrNull;
    final loggedIn = ref.watch(sessionProvider) != null;
    final blocked = loggedIn && status != null && !status.canUse;
    return Stack(children: [
      ExcludeFocus(excluding: blocked, child: widget.child),
      if (blocked)
        Positioned.fill(
          child: Overlay(
            initialEntries: [OverlayEntry(builder: (_) => const _BlockedView())],
          ),
        ),
    ]);
  }
}

class _BlockedView extends ConsumerWidget {
  const _BlockedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_clock, size: 56),
              const SizedBox(height: 12),
              const Text('يلزم تفعيل الترخيص',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              const LicensePanel(),
              const Divider(height: 36),
              const Text('بياناتك محفوظة وآمنة. يمكنك تصدير نسخة احتياطية في أي وقت:'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.ios_share),
                label: const Text('تصدير نسخة احتياطية'),
                onPressed: () async {
                  final f = await ref.read(backupServiceProvider).createBackup();
                  final msg = await BackupService.exportFile(f);
                  if (msg != null && context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  }
                },
              ),
              TextButton(
                onPressed: () => ref.read(sessionProvider.notifier).logout(),
                child: const Text('قفل الشاشة'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
