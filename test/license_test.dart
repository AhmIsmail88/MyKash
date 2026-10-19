import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykash/core/license/license_service.dart';
import 'package:mykash/core/license/machine_id.dart';

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Builds a licence token signed by a throwaway Ed25519 key created per call.
Future<Map<String, String>> _issue({
  required List<String> devices,
  String exp = '',
}) async {
  final algo = Ed25519();
  final keyPair = await algo.newKeyPair();
  final payload = <String, dynamic>{
    'v': 1,
    'shop': 'متجر تجريبي',
    'devices': devices,
    'exp': exp,
    'issued': '2026-01-01',
  };
  final payloadBytes = utf8.encode(jsonEncode(payload));
  final signature = await algo.sign(payloadBytes, keyPair: keyPair);
  final publicKey = base64.encode((await keyPair.extractPublicKey()).bytes);
  return <String, String>{
    'token': 'MYK1.${_b64u(payloadBytes)}.${_b64u(signature.bytes)}',
    'pub': publicKey,
  };
}

void main() {
  group('licence token', () {
    test('accepts a token issued for this machine', () async {
      final issued = await _issue(devices: <String>['MACH-AAAA-BBBB-CCCC']);
      final r = await LicenseService.verify(issued['token']!,
          publicKeyB64: issued['pub']!, machineId: 'MACH-AAAA-BBBB-CCCC');
      expect(r.valid, isTrue, reason: r.error);
    });

    test('rejects a token signed by another key', () async {
      final issued = await _issue(devices: <String>['MACH-AAAA-BBBB-CCCC']);
      final other = await _issue(devices: <String>['MACH-AAAA-BBBB-CCCC']);
      final r = await LicenseService.verify(issued['token']!,
          publicKeyB64: other['pub']!, machineId: 'MACH-AAAA-BBBB-CCCC');
      expect(r.valid, isFalse);
    });

    test('rejects a token issued for a different machine', () async {
      final issued = await _issue(devices: <String>['MACH-AAAA-BBBB-CCCC']);
      final r = await LicenseService.verify(issued['token']!,
          publicKeyB64: issued['pub']!, machineId: 'MACH-1111-2222-3333');
      expect(r.valid, isFalse);
    });

    test('accepts the wildcard machine', () async {
      final issued = await _issue(devices: <String>['*']);
      final r = await LicenseService.verify(issued['token']!,
          publicKeyB64: issued['pub']!, machineId: 'MACH-1111-2222-3333');
      expect(r.valid, isTrue, reason: r.error);
    });

    test('rejects an expired token', () async {
      final issued = await _issue(devices: <String>['*'], exp: '2020-01-01');
      final r = await LicenseService.verify(issued['token']!,
          publicKeyB64: issued['pub']!, machineId: 'MACH-1111-2222-3333');
      expect(r.valid, isFalse);
    });

    test('rejects a malformed token', () async {
      final r = await LicenseService.verify('not-a-token',
          publicKeyB64: 'AAAA', machineId: 'MACH-1111-2222-3333');
      expect(r.valid, isFalse);
    });
  });

  group('machine fingerprint', () {
    test('groups twelve hex chars as MACH-XXXX-XXXX-XXXX', () {
      expect(formatFingerprint('a1b2c3d4e5f6'), 'MACH-A1B2-C3D4-E5F6');
    });

    test('pads short input so the shape stays constant', () {
      expect(formatFingerprint('abc'), 'MACH-ABC0-0000-0000');
    });
  });
}