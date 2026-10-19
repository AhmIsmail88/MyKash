import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../sync/sync_protocol.dart';
import '../../sync/sync_providers.dart';
import '../auth/session.dart';
import 'pairing_form.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return isHubPlatform ? const _HubView() : const _ClientView();
  }
}

String _ago(String? msStr) {
  final ms = int.tryParse(msStr ?? '');
  if (ms == null) return 'لم تتم مزامنة بعد';
  return formatDateTime(ms);
}

// ===================== الجهاز الرئيسي (ديسك توب) =====================

class _HubView extends ConsumerStatefulWidget {
  const _HubView();
  @override
  ConsumerState<_HubView> createState() => _HubViewState();
}

class _HubViewState extends ConsumerState<_HubView> {
  Future<void> _retry() async {
    try {
      await ref.read(syncServerProvider)?.start();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _addDevice() async {
    final server = ref.read(syncServerProvider);
    if (server == null || !server.running) {
      await _retry();
      return;
    }
    final ips = await ref.read(localIpsProvider.future);
    final code = server.newPairingCode();
    final qr = jsonEncode({
      'app': 'mykash',
      'v': kProtocolVersion,
      'h': ips,
      'p': kSyncPort,
      'c': code,
    });
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة جهاز'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('على الموبايل: افتح التطبيق ← المزامنة ← مسح QR'),
              const SizedBox(height: 12),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(data: qr, size: 230),
              ),
              const SizedBox(height: 12),
              const Text('أو أدخل يدويًا:'),
              SelectableText('العنوان: ${ips.join("  أو  ")}',
                  textDirection: TextDirection.ltr),
              SelectableText('المنفذ: $kSyncPort   الرمز: $code',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              const Text('الرمز صالح 5 دقائق ولمرة واحدة. يجب أن يكون الجهازان على نفس الشبكة.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('تم')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(syncServerProvider);
    final isAdmin = ref.watch(sessionProvider)?.isAdmin ?? false;
    final ips = ref.watch(localIpsProvider).valueOrNull ?? const [];
    final devices = ref.watch(devicesProvider).valueOrNull ?? const <Device>[];
    final running = server?.running ?? false;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(running ? Icons.check_circle : Icons.error_outline,
                  color: running ? const Color(0xFF0B6B57) : const Color(0xFFA23B2A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    running
                        ? 'الجهاز الرئيسي شغّال — الأجهزة الأخرى تزامن معه'
                        : 'خادم المزامنة غير شغّال',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 8),
            if (running)
              Text('العناوين: ${ips.isEmpty ? "..." : ips.join("  |  ")}  — المنفذ $kSyncPort',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Colors.black54)),
            if (!running) ...[
              const Text(
                  'قد يكون المنفذ مشغولًا أو محجوبًا بجدار الحماية. جرّب إعادة التشغيل، ووافق على تنبيه Windows Firewall للشبكات الخاصة.',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _retry, child: const Text('إعادة تشغيل الخادم')),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (isAdmin)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: _addDevice,
            icon: const Icon(Icons.phonelink_setup),
            label: const Text('إضافة جهاز'),
          ),
        ),
      const Padding(
        padding: EdgeInsets.only(top: 18, bottom: 6),
        child: Text('الأجهزة المقترنة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      if (devices.isEmpty)
        const Text('لا توجد أجهزة مقترنة بعد.')
      else
        for (final d in devices)
          Card(
            child: ListTile(
              leading: const Icon(Icons.smartphone),
              title: Text('${d.name} (${d.prefix ?? "-"})'),
              subtitle: Text(d.lastSyncAt == null
                  ? 'لم يزامن بعد'
                  : 'آخر مزامنة: ${formatDateTime(d.lastSyncAt!)}'),
              trailing: isAdmin
                  ? IconButton(
                      tooltip: 'فصل الجهاز',
                      icon: const Icon(Icons.link_off),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('فصل الجهاز'),
                            content: Text(
                                'سيتوقف ${d.name} عن المزامنة حتى تعيد ربطه. بياناته الحالية على الجهاز تبقى.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('تراجع')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('فصل')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await ref.read(databaseProvider).removeDevice(d.id);
                        }
                      },
                    )
                  : null,
            ),
          ),
    ]);
  }
}

// ===================== الموبايل (عميل) =====================

class _ClientView extends ConsumerWidget {
  const _ClientView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(syncInfoProvider);
    final isAdmin = ref.watch(sessionProvider)?.isAdmin ?? false;
    final state = ref.watch(syncControllerProvider);
    return info.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (i) {
        if (!i.paired) {
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('ربط هذا الجهاز بالجهاز الرئيسي',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (isAdmin)
              PairingForm(onPaired: () => ref.invalidate(syncInfoProvider))
            else
              const Text('اطلب من المدير ربط هذا الجهاز.'),
          ]);
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('مرتبط بالجهاز الرئيسي',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text('${i.host}:${i.port}', textDirection: TextDirection.ltr),
                const SizedBox(height: 6),
                Text('آخر مزامنة: ${_ago(i.lastAt)}'),
                if (state.message != null) ...[
                  const SizedBox(height: 6),
                  Text(state.message!,
                      style: TextStyle(
                          color: state.ok
                              ? const Color(0xFF0B6B57)
                              : const Color(0xFFA23B2A))),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
            onPressed: state.running
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
            icon: state.running
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync),
            label: const Text('مزامنة الآن', style: TextStyle(fontSize: 18)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('مزامنة تلقائية'),
            subtitle: const Text('كل دقيقتين وبعد كل بيع، طالما الجهاز الرئيسي متاح'),
            value: i.auto,
            onChanged: (v) async {
              await ref.read(databaseProvider).setSetting('auto_sync', v ? '1' : '0');
              ref.invalidate(syncInfoProvider);
            },
          ),
          if (isAdmin)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('إلغاء الربط'),
                      content: const Text(
                          'لن يزامن هذا الجهاز بعد الآن حتى تعيد الربط. البيانات الحالية تبقى على الجهاز.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('تراجع')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('إلغاء الربط')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await ref.read(syncClientProvider).unpair();
                    ref.invalidate(syncInfoProvider);
                  }
                },
                icon: const Icon(Icons.link_off),
                label: const Text('إلغاء الربط'),
              ),
            ),
        ]);
      },
    );
  }
}
