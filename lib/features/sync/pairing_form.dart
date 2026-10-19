import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../sync/sync_protocol.dart';
import '../../sync/sync_providers.dart';
import '../scanning/scanner_page.dart';

import 'dart:convert';

/// نموذج الاقتران بالجهاز الرئيسي (QR أو إدخال يدوي). لا يحتاج Navigator
/// فيصلح داخل شاشة الإعداد الأول.
class PairingForm extends ConsumerStatefulWidget {
  final VoidCallback onPaired;
  const PairingForm({super.key, required this.onPaired});

  @override
  ConsumerState<PairingForm> createState() => _PairingFormState();
}

class _PairingFormState extends ConsumerState<PairingForm> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '$kSyncPort');
  final _code = TextEditingController();
  bool _scanning = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_busy) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (j['app'] != 'mykash') continue;
        _host.text = (j['h'] as List).join(',');
        _port.text = '${j['p']}';
        _code.text = '${j['c']}';
        setState(() => _scanning = false);
        _pair();
        return;
      } catch (_) {}
    }
  }

  Future<void> _pair() async {
    final hosts = _host.text
        .split(RegExp(r'[,\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final port = int.tryParse(_port.text.trim()) ?? kSyncPort;
    final code = _code.text.trim();
    if (hosts.isEmpty || code.isEmpty) {
      setState(() => _error = 'اكتب عنوان الجهاز الرئيسي والرمز، أو امسح الـ QR');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref
        .read(syncClientProvider)
        .pair(hosts: hosts, port: port, code: code);
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = r.error;
      });
      return;
    }
    // أول مزامنة بعد الاقتران
    final s = await ref.read(syncControllerProvider.notifier).syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = s.ok ? null : s.message;
    });
    if (s.ok) widget.onPaired();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
        'على الجهاز الرئيسي (الكمبيوتر): افتح شاشة المزامنة واضغط «إضافة جهاز» ليظهر QR ورمز.',
        style: TextStyle(color: Colors.black54),
      ),
      const SizedBox(height: 12),
      if (canScanWithCamera) ...[
        OutlinedButton.icon(
          onPressed: _busy ? null : () => setState(() => _scanning = !_scanning),
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(_scanning ? 'إيقاف الكاميرا' : 'مسح QR من الجهاز الرئيسي'),
        ),
        if (_scanning)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              height: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: MobileScanner(onDetect: _onDetect),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Center(child: Text('أو أدخل البيانات يدويًا')),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _host,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
            labelText: 'عنوان الجهاز الرئيسي (مثل 192.168.1.5)'),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'رمز الاقتران'),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'المنفذ'),
          ),
        ),
      ]),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: const TextStyle(color: Color(0xFFA23B2A))),
      ],
      const SizedBox(height: 14),
      FilledButton(
        onPressed: _busy ? null : _pair,
        child: _busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('ربط ومزامنة'),
      ),
    ]);
  }
}
