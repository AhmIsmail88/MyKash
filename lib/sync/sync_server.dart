import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../data/database.dart';
import 'sync_protocol.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

/// سيرفر المزامنة المحلي على الجهاز الرئيسي (ديسك توب). لا يحتاج إنترنت.
class SyncServer {
  SyncServer(this.db);
  final AppDatabase db;

  HttpServer? _server;
  String? _code;
  DateTime? _codeExpires;
  int _badCodes = 0;
  DateTime? _blockedUntil;

  bool get running => _server != null;
  DateTime? get codeExpires => _codeExpires;

  Future<void> start() async {
    if (_server != null) return;
    _server = await shelf_io.serve(_handle, InternetAddress.anyIPv4, kSyncPort);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// رمز اقتران لمرة واحدة صالح 5 دقائق.
  String newPairingCode() {
    final r = Random.secure();
    _code = (100000 + r.nextInt(900000)).toString();
    _codeExpires = DateTime.now().add(const Duration(minutes: 5));
    _badCodes = 0;
    return _code!;
  }

  Response _json(Map<String, dynamic> m, {int status = 200, Map<String, String>? extra}) =>
      Response(status,
          body: jsonEncode(m), headers: {..._jsonHeaders, ...?extra});

  Future<Response> _handle(Request req) async {
    try {
      final path = '/${req.url.path}';
      if (req.method == 'GET' && path == '/ping') {
        return _json({
          'app': 'mykash',
          'v': kProtocolVersion,
          'hubId': DeviceInfo.id,
          'time': nowMs(),
        });
      }
      if (req.method == 'POST' && path == '/pair') return await _pair(req);
      if (req.method == 'POST' && path == '/sync') return await _sync(req, path);
      return Response.notFound('not found');
    } catch (e) {
      return _json({'error': '$e'}, status: 500);
    }
  }

  Future<Response> _pair(Request req) async {
    final now = DateTime.now();
    if (_blockedUntil != null && now.isBefore(_blockedUntil!)) {
      return _json({'error': 'blocked'}, status: 429);
    }
    final j = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final code = j['code'] as String?;
    final valid = _code != null &&
        _codeExpires != null &&
        now.isBefore(_codeExpires!) &&
        code != null &&
        constantTimeEquals(code, _code!);
    if (!valid) {
      _badCodes++;
      if (_badCodes >= 5) {
        _blockedUntil = now.add(const Duration(minutes: 1));
        _badCodes = 0;
      }
      return _json({'error': 'bad_code'}, status: 403);
    }
    final deviceId = j['deviceId'] as String?;
    if (deviceId == null || deviceId.isEmpty) {
      return _json({'error': 'bad_request'}, status: 400);
    }
    final reg = await db.registerPairedDevice(
      id: deviceId,
      name: (j['deviceName'] as String?) ?? 'جهاز',
      kind: (j['kind'] as String?) ?? 'mobile',
    );
    _code = null; // يُستعمل مرة واحدة
    final settings = <String, String>{};
    for (final k in const [
      'shop_name',
      'currency',
      'shop_phone',
      'shop_address',
      'receipt_footer',
      'receipt_format',
    ]) {
      final v = await db.getSetting(k);
      if (v != null) settings[k] = v;
    }
    return _json({
      'key': reg.key,
      'prefix': reg.prefix,
      'hubId': DeviceInfo.id,
      'epoch': await db.syncEpoch(),
      'settings': settings,
      'time': nowMs(),
    });
  }

  Future<Response> _sync(Request req, String path) async {
    final id = req.headers['x-device'];
    final ts = req.headers['x-ts'];
    final sig = req.headers['x-sig'];
    if (id == null || ts == null || sig == null) {
      return _json({'error': 'unauthorized'}, status: 401);
    }
    final device = await db.deviceById(id);
    final key = device?.sharedKey;
    if (device == null || key == null) {
      return _json({'error': 'unauthorized'}, status: 401);
    }
    final body = await req.readAsString();
    final expected = signMessage(key, ts, 'POST', path, body);
    final skew = (nowMs() - (int.tryParse(ts) ?? 0)).abs();
    if (!constantTimeEquals(sig, expected) || skew > 10 * 60 * 1000) {
      return _json({'error': 'unauthorized'}, status: 401);
    }
    final j = jsonDecode(body) as Map<String, dynamic>;
    final cursor = (j['cursor'] as num?)?.toInt() ?? 0;
    final rows = [
      for (final r in (j['rows'] as List? ?? const []))
        Map<String, dynamic>.from(r as Map),
    ];
    final applied = await db.applyRemoteRows(rows, id);
    final pull = await db.collectChangesForPeer(cursor, id);
    await db.touchDeviceSync(id);

    final respBody = jsonEncode({
      'applied': applied,
      'epoch': await db.syncEpoch(),
      'rows': pull.rows,
      'cursor': pull.next,
      'more': pull.more,
      'time': nowMs(),
    });
    final rts = '${nowMs()}';
    return Response.ok(respBody, headers: {
      ..._jsonHeaders,
      'x-ts': rts,
      'x-sig': signMessage(key, rts, 'RESP', path, respBody),
    });
  }
}
