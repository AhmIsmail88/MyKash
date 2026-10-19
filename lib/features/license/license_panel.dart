import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/license/license_key.dart';
import '../../core/license/license_service.dart';
import '../../core/license/machine_id.dart';
import '../../data/providers.dart';

final licenseServiceProvider = Provider<LicenseService>(
    (ref) => LicenseService(ref.watch(databaseProvider)));

final licenseStatusProvider = FutureProvider<LicenseStatus>(
    (ref) => ref.watch(licenseServiceProvider).status());

/// بطاقة الترخيص: الحالة + بصمة الجهاز + تفعيل برمز أو بملف.
class LicensePanel extends ConsumerStatefulWidget {
  const LicensePanel({super.key});
  @override
  ConsumerState<LicensePanel> createState() => _LicensePanelState();
}

class _LicensePanelState extends ConsumerState<LicensePanel> {
  final _code = TextEditingController();
  String? _msg;
  bool _ok = false;
  bool _busy = false;
  String? _machine;
  String? _machineError;

  @override
  void initState() {
    super.initState();
    // The fingerprint only matters when licensing is actually enforced;
    // a public build must never show it to a normal user.
    if (kLicensingEnabled) _loadMachine();
  }

  Future<void> _loadMachine() async {
    try {
      final id = await machineFingerprint();
      if (!mounted) return;
      setState(() => _machine = id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _machineError =
          e is MachineIdException ? e.message : 'تعذر قراءة بصمة الجهاز.');
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    if (raw.trim().isEmpty) {
      setState(() {
        _ok = false;
        _msg = 'أدخل رمز الترخيص أو استورد ملف الترخيص.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final r = await ref.read(licenseServiceProvider).activate(raw);
    ref.invalidate(licenseStatusProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = r.valid;
      _msg = r.valid ? 'تم تفعيل الترخيص' : r.error;
      if (r.valid) _code.clear();
    });
  }

  Future<void> _importFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر ملف الترخيص',
        type: FileType.any,
        withData: true,
      );
      final files = picked?.files ?? const <PlatformFile>[];
      if (files.isEmpty) return;
      final bytes = files.first.bytes;
      if (bytes == null) return;
      await _submit(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _msg = 'تعذر قراءة ملف الترخيص.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(licenseStatusProvider).valueOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(status?.text ?? '...',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      if (kLicensingEnabled) ...[
        const SizedBox(height: 10),
        if (_machineError != null)
          Text(_machineError!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFA23B2A)))
        else
          Row(children: [
            Expanded(
              child: SelectableText('بصمة الجهاز: ${_machine ?? '...'}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
            IconButton(
              tooltip: 'نسخ بصمة الجهاز',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: _machine == null
                  ? null
                  : () => Clipboard.setData(ClipboardData(text: _machine!)),
            ),
          ]),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
              'أرسل بصمة الجهاز إلى المورّد ليصدر لك ترخيصًا صالحًا لهذا الجهاز فقط.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ),
      ],
      if (!kLicensingEnabled)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
              'الترخيص معطّل حاليًا (kLicensingEnabled = false في license_key.dart).',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        )
      else ...[
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          minLines: 2,
          maxLines: 4,
          textDirection: TextDirection.ltr,
          decoration:
              const InputDecoration(labelText: 'رمز الترخيص (MYK1....)'),
        ),
        if (_msg != null) ...[
          const SizedBox(height: 8),
          Text(_msg!,
              style: TextStyle(
                  color:
                      _ok ? const Color(0xFF0B6B57) : const Color(0xFFA23B2A))),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _submit(_code.text),
              child: const Text('تفعيل الترخيص'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _importFile,
              icon: const Icon(Icons.file_open, size: 18),
              label: const Text('استيراد ملف'),
            ),
          ),
        ]),
      ],
    ]);
  }
}
