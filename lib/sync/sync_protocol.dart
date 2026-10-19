import 'dart:convert';

import 'package:crypto/crypto.dart';

const int kSyncPort = 47615;
const int kProtocolVersion = 1;

String bodyHash(String body) => sha256.convert(utf8.encode(body)).toString();

/// توقيع HMAC-SHA256 للطلب أو الرد: يربط الوقت والطريقة والمسار ومحتوى الجسم.
/// للردود يُستخدم method = 'RESP'.
String signMessage(String key, String ts, String method, String path, String body) {
  final h = Hmac(sha256, utf8.encode(key));
  return h
      .convert(utf8.encode('$ts\n$method\n$path\n${bodyHash(body)}'))
      .toString();
}

bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return r == 0;
}
