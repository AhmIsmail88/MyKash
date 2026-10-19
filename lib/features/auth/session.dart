import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';

class SessionUser {
  final String id, name, role;
  const SessionUser(this.id, this.name, this.role);
  bool get isAdmin => role == 'admin';
}

class SessionNotifier extends Notifier<SessionUser?> {
  @override
  SessionUser? build() => null;

  void login(User u) => state = SessionUser(u.id, u.name, u.role);
  void logout() => state = null;
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionUser?>(SessionNotifier.new);

/// دقائق الخمول قبل القفل التلقائي (0 = بدون قفل). تُحقن من main.dart.
final lockMinutesProvider = StateProvider<int>((ref) => 10);
