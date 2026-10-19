import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_service.dart';

/// يُحقن من main.dart.
final backupServiceProvider = Provider<BackupService>(
  (ref) => throw UnimplementedError('يُحقن من main.dart'),
);
