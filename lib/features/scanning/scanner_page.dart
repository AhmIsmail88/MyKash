import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// المسح بالكاميرا متاح على أندرويد/iOS فقط. على الديسك توب استخدم قارئ USB.
bool get canScanWithCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// مسح مرة واحدة: يعيد الكود المقروء أو null.
Future<String?> scanOnce(BuildContext context, {String title = 'امسح الباركود'}) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => ScannerPage(title: title)),
  );
}

/// شاشة الكاميرا. مع [onCode] تبقى مفتوحة (مسح مستمر) وتعرض الرسالة المُعادة
/// لكل قراءة؛ بدونها تُغلق عند أول قراءة وتعيد الكود.
class ScannerPage extends StatefulWidget {
  final String title;
  final Future<String?> Function(String code)? onCode;
  final Widget? footer;
  const ScannerPage({super.key, required this.title, this.onCode, this.footer});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  final Map<String, int> _recent = {};
  String? _message;
  bool _torch = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    for (final b in capture.barcodes) {
      final code = b.rawValue;
      if (code == null || code.isEmpty) continue;
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _recent[code];
      if (last != null && now - last < 1500) return; // منع التكرار السريع
      _recent[code] = now;

      final handler = widget.onCode;
      if (handler == null) {
        HapticFeedback.mediumImpact();
        if (mounted) Navigator.of(context).pop(code);
        return;
      }
      _busy = true;
      final msg = await handler(code);
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
      if (mounted) setState(() => _message = msg);
      _busy = false;
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'الفلاش',
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
          IconButton(
            tooltip: 'تبديل الكاميرا',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'تعذّر تشغيل الكاميرا. تأكد من السماح للتطبيق باستخدام الكاميرا.\n${error.errorCode.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 280,
            height: 170,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(14),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_message ?? 'وجّه الكاميرا نحو الباركود',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                if (widget.footer != null) ...[
                  const SizedBox(height: 6),
                  widget.footer!,
                ],
                if (widget.onCode != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('تم'),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
