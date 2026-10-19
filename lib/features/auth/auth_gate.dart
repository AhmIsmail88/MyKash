import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../sync/sync_providers.dart';
import '../sync/pairing_form.dart';
import 'session.dart';

/// يغطي التطبيق بشاشة الإعداد الأول أو الدخول إلى أن يسجّل المستخدم دخوله.
class AuthGate extends ConsumerWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(sessionProvider) == null;
    return Stack(children: [
      ExcludeFocus(excluding: locked, child: child),
      if (locked)
        Positioned.fill(
          child: Overlay(
            initialEntries: [OverlayEntry(builder: (_) => const _GateView())],
          ),
        ),
    ]);
  }
}

class _GateView extends ConsumerWidget {
  const _GateView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(hasUsersProvider).when(
          loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('خطأ: $e'))),
          data: (has) => has ? const LoginView() : const SetupView(),
        );
  }
}

Widget _logo() => ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset('assets/branding/icon_full.png', width: 96, height: 96),
    );

class SetupView extends ConsumerStatefulWidget {
  const SetupView({super.key});
  @override
  ConsumerState<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<SetupView> {
  final _shop = TextEditingController(text: 'محلي');
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _pairMode = false;

  Future<void> _submit() async {
    final name = _name.text.trim();
    final pin = latinDigits(_pin.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسم المدير');
      return;
    }
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'الرمز السري من 4 إلى 6 أرقام');
      return;
    }
    if (pin != latinDigits(_pin2.text.trim())) {
      setState(() => _error = 'الرمزان غير متطابقين');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final db = ref.read(databaseProvider);
    final shop = _shop.text.trim().isEmpty ? 'محلي' : _shop.text.trim();
    await db.setSetting('shop_name', shop);
    final user = await db.createUser(name: name, role: 'admin', pin: pin);
    ref.read(sessionProvider.notifier).login(user);
    ref.invalidate(hasUsersProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (_pairMode) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _logo(),
                const SizedBox(height: 16),
                const Text('ربط بجهاز رئيسي',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                PairingForm(onPaired: () => ref.invalidate(hasUsersProvider)),
                const SizedBox(height: 10),
                TextButton(
                    onPressed: () => setState(() => _pairMode = false),
                    child: const Text('رجوع')),
              ]),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _logo(),
              const SizedBox(height: 16),
              const Text('أهلًا بك في MyKash',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('إعداد أول مرة: أنشئ حساب المدير'),
              const SizedBox(height: 20),
              TextField(
                  controller: _shop,
                  decoration: const InputDecoration(labelText: 'اسم المحل')),
              const SizedBox(height: 12),
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'اسم المدير')),
              const SizedBox(height: 12),
              TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                      labelText: 'الرمز السري (4 إلى 6 أرقام)', counterText: '')),
              const SizedBox(height: 12),
              TextField(
                  controller: _pin2,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                      labelText: 'أعد كتابة الرمز', counterText: '')),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFA23B2A))),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('ابدأ'),
                ),
              ),
              if (!isHubPlatform) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => setState(() => _pairMode = true),
                  child: const Text('لدي جهاز رئيسي بالفعل: ربط ومزامنة'),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});
  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _pin = TextEditingController();
  String? _selected;
  String? _error;
  int _fails = 0;
  DateTime? _lockedUntil;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    final until = _lockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      setState(() => _error = 'محاولات كثيرة، انتظر قليلًا ثم أعد المحاولة');
      return;
    }
    final user = await ref
        .read(databaseProvider)
        .verifyPin(_selected!, latinDigits(_pin.text.trim()));
    if (user == null) {
      _fails++;
      _pin.clear();
      setState(() {
        if (_fails >= 5) {
          _fails = 0;
          _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
          _error = 'محاولات كثيرة، انتظر 30 ثانية';
        } else {
          _error = 'الرمز غير صحيح';
        }
      });
      return;
    }
    _fails = 0;
    _pin.clear();
    ref.read(sessionProvider.notifier).login(user);
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider).valueOrNull ?? [];
    if (_selected == null && users.isNotEmpty) _selected = users.first.id;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _logo(),
              const SizedBox(height: 16),
              const Text('MyKash',
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800, color: kGreen)),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final u in users)
                  ChoiceChip(
                    label: Text(u.name),
                    selected: _selected == u.id,
                    onSelected: (_) => setState(() {
                      _selected = u.id;
                      _error = null;
                      _pin.clear();
                    }),
                  ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _pin,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 8),
                onSubmitted: (_) => _submit(),
                decoration:
                    const InputDecoration(labelText: 'الرمز السري', counterText: ''),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFA23B2A))),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(onPressed: _submit, child: const Text('دخول')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
