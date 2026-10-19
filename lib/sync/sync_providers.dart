import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import 'sync_client.dart';
import 'sync_server.dart';

/// الديسك توب هو الجهاز الرئيسي (يشغّل السيرفر)، والموبايل عميل.
bool get isHubPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// يُحقن من main.dart على الديسك توب فقط.
final syncServerProvider = Provider<SyncServer?>((ref) => null);

final syncClientProvider =
    Provider<SyncClient>((ref) => SyncClient(ref.watch(databaseProvider)));

final localIpsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final ifs = await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLoopback: false);
  return [
    for (final i in ifs)
      for (final a in i.addresses) a.address,
  ];
});

final devicesProvider = StreamProvider.autoDispose<List<Device>>((ref) {
  return ref.watch(databaseProvider).watchDevices();
});

class SyncInfo {
  final String? host, port, lastAt;
  final bool paired, auto;
  const SyncInfo(this.paired, this.host, this.port, this.lastAt, this.auto);
}

final syncInfoProvider = FutureProvider.autoDispose<SyncInfo>((ref) async {
  final db = ref.watch(databaseProvider);
  final key = await db.getSetting('sync_key');
  return SyncInfo(
    key != null && key.isNotEmpty,
    await db.getSetting('sync_host'),
    await db.getSetting('sync_port'),
    await db.getSetting('sync_last_at'),
    (await db.getSetting('auto_sync')) == '1',
  );
});

class SyncState {
  final bool running, ok;
  final String? message;
  final DateTime? at;
  const SyncState({this.running = false, this.ok = true, this.message, this.at});
}

class SyncController extends Notifier<SyncState> {
  Timer? _timer;
  Timer? _soon;

  @override
  SyncState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _soon?.cancel();
    });
    if (!isHubPlatform) {
      _timer = Timer.periodic(const Duration(minutes: 2), (_) => _auto());
    }
    return const SyncState();
  }

  Future<bool> isPaired() => ref.read(syncClientProvider).isPaired();

  Future<bool> _autoEnabled() async =>
      (await ref.read(databaseProvider).getSetting('auto_sync')) == '1';

  Future<void> _auto() async {
    if (state.running || !await _autoEnabled() || !await isPaired()) return;
    await syncNow();
  }

  Future<SyncResult> syncNow() async {
    if (state.running) return const SyncResult.fail('جارٍ المزامنة...');
    state = const SyncState(running: true);
    final r = await ref.read(syncClientProvider).syncNow();
    state = SyncState(message: r.message, ok: r.ok, at: DateTime.now());
    ref.invalidate(syncInfoProvider);
    return r;
  }

  /// بعد كل بيع: مزامنة هادئة بعد 3 ثوانٍ لو التلقائية مفعّلة.
  void triggerSoon() {
    if (isHubPlatform) return;
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 3), _auto);
  }
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);
