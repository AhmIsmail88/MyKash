import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/format.dart';
import '../data/database.dart';
import 'sync_protocol.dart';

class SyncResult {
  final int pushed, pulled;
  final String? error;
  final int? skewMs;
  const SyncResult({this.pushed = 0, this.pulled = 0, this.error, this.skewMs});
  const SyncResult.fail(String this.error)
      : pushed = 0,
        pulled = 0,
        skewMs = null;

  bool get ok => error == null;

  String get message {
    if (!ok) return error!;
    final warn = (skewMs != null && skewMs!.abs() > 2 * 60 * 1000)
        ? ' — تنبيه: فرق الساعة بين الجهازين أكثر من دقيقتين، اضبط الوقت'
        : '';
    return 'تمت المزامنة: ↑$pushed ↓$pulled$warn';
  }
}

/// عميل المزامنة (الموبايل): يدفع تغييراته ويسحب تغييرات الجهاز الرئيسي.
class SyncClient {
  SyncClient(this.db);
  final AppDatabase db;

  Future<bool> isPaired() async {
    final k = await db.getSetting('sync_key');
    return k != null && k.isNotEmpty;
  }

  Future<(int, String, Map<String, String>)> _request(
    String host,
    int port,
    String method,
    String path, {
    String? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client
          .openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path));
      headers?.forEach(req.headers.set);
      if (body != null) {
        final bytes = utf8.encode(body);
        req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      final h = <String, String>{};
      res.headers.forEach((k, v) => h[k] = v.join(','));
      return (res.statusCode, text, h);
    } finally {
      client.close(force: true);
    }
  }

  String _deviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  /// الاقتران بالجهاز الرئيسي بعنوان/عناوين ورمز. يجرّب العناوين بالترتيب.
  Future<SyncResult> pair({
    required List<String> hosts,
    required int port,
    required String code,
  }) async {
    final body = jsonEncode({
      'code': code,
      'deviceId': DeviceInfo.id,
      'deviceName': _deviceName(),
      'kind': 'mobile',
    });
    String? lastErr;
    for (final h in hosts) {
      try {
        final (status, text, _) = await _request(h, port, 'POST', '/pair',
            body: body, timeout: const Duration(seconds: 10));
        if (status == 200) {
          final j = jsonDecode(text) as Map<String, dynamic>;
          await db.setSetting('sync_host', hosts.join(','));
          await db.setSetting('sync_port', '$port');
          await db.setSetting('sync_key', j['key'] as String);
          await db.setSetting('sync_hub_id', j['hubId'] as String);
          await db.setSetting('sync_hub_epoch', (j['epoch'] as String?) ?? '');
          await db.setSetting('sync_cursor', '0');
          await db.setSetting('sync_pushed', '0');
          final prefix = j['prefix'] as String;
          await db.setSetting('device_prefix', prefix);
          DeviceInfo.prefix = prefix;
          final settings = Map<String, dynamic>.from(j['settings'] as Map);
          for (final e in settings.entries) {
            await db.setSetting(e.key, '${e.value}');
          }
          if (settings['currency'] != null) kCurrency = '${settings['currency']}';
          return const SyncResult();
        }
        if (status == 403) {
          return const SyncResult.fail('الرمز غير صحيح أو انتهت صلاحيته');
        }
        if (status == 429) {
          return const SyncResult.fail('محاولات كثيرة، انتظر دقيقة ثم أعد المحاولة');
        }
        lastErr = 'رد غير متوقع ($status)';
      } catch (_) {
        lastErr = 'تعذّر الاتصال بالعنوان $h';
      }
    }
    return SyncResult.fail(lastErr ?? 'تعذّر الاتصال بالجهاز الرئيسي');
  }

  /// أول عنوان يردّ على ping وبنفس معرّف الجهاز الرئيسي.
  Future<String?> _pickHost(List<String> hosts, int port, String hubId) async {
    for (final h in hosts) {
      try {
        final (status, text, _) = await _request(h, port, 'GET', '/ping',
            timeout: const Duration(seconds: 3));
        if (status == 200) {
          final j = jsonDecode(text) as Map<String, dynamic>;
          if (j['app'] == 'mykash' && j['hubId'] == hubId) return h;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<SyncResult> syncNow() async {
    final hostSetting = await db.getSetting('sync_host');
    final key = await db.getSetting('sync_key');
    final hubId = await db.getSetting('sync_hub_id') ?? '';
    if (hostSetting == null || hostSetting.isEmpty || key == null || key.isEmpty) {
      return const SyncResult.fail('الجهاز غير مرتبط بجهاز رئيسي');
    }
    final port = int.tryParse(await db.getSetting('sync_port') ?? '') ?? kSyncPort;
    final hosts =
        hostSetting.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    var cursor = int.tryParse(await db.getSetting('sync_cursor') ?? '') ?? 0;
    var pushedSeq = int.tryParse(await db.getSetting('sync_pushed') ?? '') ?? 0;
    var pushed = 0, pulled = 0;
    int? skew;
    try {
      final host = await _pickHost(hosts, port, hubId);
      if (host == null) {
        return const SyncResult.fail(
            'تعذّر الوصول للجهاز الرئيسي. تأكد أنه شغّال وعلى نفس الشبكة.');
      }
      for (var round = 0; round < 200; round++) {
        final batch = await db.collectLocalChanges(pushedSeq);
        final body = jsonEncode({'cursor': cursor, 'rows': batch.rows});
        final ts = '${nowMs()}';
        final (status, text, h) = await _request(
          host,
          port,
          'POST',
          '/sync',
          body: body,
          headers: {
            'x-device': DeviceInfo.id,
            'x-ts': ts,
            'x-sig': signMessage(key, ts, 'POST', '/sync', body),
          },
        );
        if (status == 401) {
          return const SyncResult.fail(
              'رفض الجهاز الرئيسي هذا الجهاز. أعد الربط من إعدادات المزامنة.');
        }
        if (status != 200) {
          return SyncResult.fail('خطأ من الجهاز الرئيسي ($status)');
        }
        final rsig = h['x-sig'] ?? '';
        final rts = h['x-ts'] ?? '';
        if (!constantTimeEquals(rsig, signMessage(key, rts, 'RESP', '/sync', text))) {
          return const SyncResult.fail('توقيع رد الجهاز الرئيسي غير صحيح');
        }
        final j = jsonDecode(text) as Map<String, dynamic>;
        // الجهاز الرئيسي استُعيد من نسخة احتياطية: مؤشراتنا لم تعد صالحة، نعيد من الصفر.
        final epoch = (j['epoch'] as String?) ?? '';
        final knownEpoch = await db.getSetting('sync_hub_epoch') ?? '';
        if (knownEpoch.isNotEmpty && epoch.isNotEmpty && epoch != knownEpoch) {
          await db.setSetting('sync_hub_epoch', epoch);
          await db.setSetting('sync_cursor', '0');
          await db.setSetting('sync_pushed', '0');
          cursor = 0;
          pushedSeq = 0;
          continue;
        }
        if (knownEpoch.isEmpty && epoch.isNotEmpty) {
          await db.setSetting('sync_hub_epoch', epoch);
        }
        skew = nowMs() - (j['time'] as num).toInt();
        final rows = [
          for (final r in (j['rows'] as List)) Map<String, dynamic>.from(r as Map),
        ];
        pulled += await db.applyRemoteRows(rows, 'hub');
        pushed += batch.rows.length;
        pushedSeq = batch.maxSeq;
        cursor = (j['cursor'] as num).toInt();
        await db.setSetting('sync_pushed', '$pushedSeq');
        await db.setSetting('sync_cursor', '$cursor');
        if (!batch.full && j['more'] != true) break;
      }
      await db.setSetting('sync_last_at', '${nowMs()}');
      return SyncResult(pushed: pushed, pulled: pulled, skewMs: skew);
    } on SocketException {
      return const SyncResult.fail('انقطع الاتصال بالجهاز الرئيسي أثناء المزامنة');
    } on TimeoutException {
      return const SyncResult.fail('انتهت مهلة الاتصال بالجهاز الرئيسي');
    } catch (e) {
      return SyncResult.fail('فشلت المزامنة: $e');
    }
  }

  Future<void> unpair() async {
    for (final k in const [
      'sync_host',
      'sync_port',
      'sync_key',
      'sync_hub_id',
      'sync_hub_epoch',
      'sync_cursor',
      'sync_pushed',
      'sync_last_at',
    ]) {
      await db.setSetting(k, '');
    }
  }
}
