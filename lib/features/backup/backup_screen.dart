import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_service.dart';
import '../../core/format.dart';
import '../../data/providers.dart';
import '../../sync/sync_providers.dart' show isHubPlatform;
import '../auth/session.dart';
import 'backup_provider.dart';

String _size(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} ك.ب';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} م.ب';
}

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  late Future<List<BackupInfo>> _list = ref.read(backupServiceProvider).list();
  String? _lastAuto;
  String? _extraDir;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = ref.read(databaseProvider);
    final last = await db.getSetting('last_auto_backup');
    final extra = await db.getSetting('backup_extra_dir');
    if (mounted) {
      setState(() {
        _lastAuto = last;
        _extraDir = extra;
      });
    }
  }

  void _reload() => setState(() => _list = ref.read(backupServiceProvider).list());

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _backupNow({bool export = false}) async {
    setState(() => _busy = true);
    try {
      final f = await ref.read(backupServiceProvider).createBackup();
      _reload();
      if (export) {
        final msg = await BackupService.exportFile(f);
        if (msg != null) _snack(msg);
      } else {
        _snack('تم إنشاء النسخة الاحتياطية');
      }
    } catch (e) {
      _snack('تعذّر إنشاء النسخة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickExtraDir() async {
    final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'مجلد النسخة الإضافية (فلاش/Drive)');
    if (dir == null) return;
    await ref.read(databaseProvider).setSetting('backup_extra_dir', dir);
    _loadSettings();
  }

  Future<void> _clearExtraDir() async {
    await ref.read(databaseProvider).setSetting('backup_extra_dir', '');
    _loadSettings();
  }

  Future<void> _restoreFromFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null) return;
    await _stageRestore(path);
  }

  Future<void> _stageRestore(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: const Text(
            'ستُستبدل كل بيانات هذا الجهاز بمحتوى النسخة المختارة، وأي بيانات أُضيفت بعدها ستضيع '
            '(تُحفظ نسخة أمان تلقائية قبل الاستبدال).\n\n'
            'استعد على نفس الجهاز الذي أُخذت منه النسخة فقط. '
            'إن كان هذا هو الجهاز الرئيسي فستُعاد مزامنة الأجهزة الأخرى تلقائيًا.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA23B2A)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final err = await ref.read(backupServiceProvider).stageRestore(path);
    if (mounted) setState(() => _busy = false);
    if (err != null) {
      _snack(err);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('تم تجهيز الاستعادة'),
        content: const Text(
            'أغلق التطبيق ثم افتحه من جديد لإتمام الاستعادة. لا تُضف بيانات جديدة قبل ذلك.'),
        actions: [
          FilledButton(
            onPressed: () {
              if (Platform.isAndroid) {
                SystemNavigator.pop();
              } else {
                exit(0);
              }
            },
            child: const Text('إغلاق التطبيق الآن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(sessionProvider)?.isAdmin ?? false;
    if (!isAdmin) return const Center(child: Text('هذه الشاشة للمدير فقط'));
    final lastMs = int.tryParse(_lastAuto ?? '');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('النسخ الاحتياطي',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(lastMs == null
                ? 'لم تُؤخذ نسخة تلقائية بعد'
                : 'آخر نسخة تلقائية: ${formatDateTime(lastMs)}'),
            const SizedBox(height: 4),
            const Text(
                'تُؤخذ نسخة تلقائيًا كل يوم (تُحفظ آخر 14)، ونسخة أمان قبل أي ترقية أو استعادة. '
                'انسخ ملفًا خارج الجهاز بانتظام (فلاش/واتساب/Drive): النسخ على نفس الجهاز لا تحميك من ضياعه.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _backupNow(),
          icon: const Icon(Icons.backup_outlined),
          label: const Text('نسخ احتياطي الآن'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _backupNow(export: true),
          icon: const Icon(Icons.ios_share),
          label: Text(isHubPlatform ? 'نسخة جديدة وحفظها باسم...' : 'نسخة جديدة ومشاركتها'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restoreFromFile,
          icon: const Icon(Icons.restore),
          label: const Text('استعادة من ملف...'),
        ),
      ]),
      if (isHubPlatform) ...[
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            title: const Text('نسخة إضافية تلقائية في مجلد'),
            subtitle: Text(
                (_extraDir == null || _extraDir!.isEmpty) ? 'غير محدد' : _extraDir!,
                textDirection: TextDirection.ltr),
            trailing: Wrap(children: [
              IconButton(
                  tooltip: 'اختيار مجلد',
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickExtraDir),
              if (_extraDir != null && _extraDir!.isNotEmpty)
                IconButton(
                    tooltip: 'إلغاء',
                    icon: const Icon(Icons.close),
                    onPressed: _clearExtraDir),
            ]),
          ),
        ),
      ],
      const Padding(
        padding: EdgeInsets.only(top: 20, bottom: 6),
        child: Text('النسخ المحفوظة على هذا الجهاز',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      FutureBuilder<List<BackupInfo>>(
        future: _list,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) return const Text('لا توجد نسخ بعد.');
          return Column(children: [
            for (final b in items)
              Card(
                child: ListTile(
                  title: Text('${b.kindLabel} · ${formatDateTime(b.at.millisecondsSinceEpoch)}'),
                  subtitle: Text(_size(b.size)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'export') {
                        final msg = await BackupService.exportFile(b.file);
                        if (msg != null) _snack(msg);
                      } else if (v == 'restore') {
                        await _stageRestore(b.file.path);
                      } else if (v == 'delete') {
                        await ref.read(backupServiceProvider).delete(b);
                        _reload();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'export', child: Text('تصدير')),
                      PopupMenuItem(value: 'restore', child: Text('استعادة')),
                      PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ),
              ),
          ]);
        },
      ),
    ]);
  }
}
