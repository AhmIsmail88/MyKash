import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../auth/session.dart';
import '../license/license_panel.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _shop = TextEditingController();
  final _currency = TextEditingController(text: kCurrency);
  final _vatRate = TextEditingController();
  bool _vatInclusive = false;
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _footer = TextEditingController();
  String _format = 'a4';
  bool _autoPrint = false;
  int _lock = 10;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _shop.text = await ref.read(databaseProvider).getSetting('shop_name') ?? '';
    final db0 = ref.read(databaseProvider);
    _phone.text = await db0.getSetting('shop_phone') ?? '';
    _address.text = await db0.getSetting('shop_address') ?? '';
    _footer.text = await db0.getSetting('receipt_footer') ?? '';
    _format = await db0.getSetting('receipt_format') ?? 'a4';
    _autoPrint = (await db0.getSetting('auto_print')) == '1';
    _vatRate.text = await db0.getSetting('vat_rate') ?? '';
    _vatInclusive = (await db0.getSetting('vat_inclusive') ?? '0') == '1';
    _lock = ref.read(lockMinutesProvider);
    if (mounted) setState(() => _loaded = true);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    final cur = _currency.text.trim().isEmpty ? 'ج.م' : _currency.text.trim();
    await db.setSetting('shop_name', _shop.text.trim());
    await db.setSetting('currency', cur);
    await db.setSetting('lock_minutes', '$_lock');
    await db.setSetting('shop_phone', _phone.text.trim());
    await db.setSetting('shop_address', _address.text.trim());
    await db.setSetting('receipt_footer', _footer.text.trim());
    await db.setSetting('receipt_format', _format);
    await db.setSetting('auto_print', _autoPrint ? '1' : '0');
    final vat = int.tryParse(latinDigits(_vatRate.text.trim())) ?? 0;
    await db.setSetting('vat_rate', '${vat.clamp(0, 100)}');
    await db.setSetting('vat_inclusive', _vatInclusive ? '1' : '0');
    kVatRate = vat.clamp(0, 100);
    kVatInclusive = _vatInclusive;
    kCurrency = cur;
    ref.read(lockMinutesProvider.notifier).state = _lock;
    await db.logAudit('settings_changed', userId: ref.read(sessionProvider)?.id);
    if (mounted) _snack('تم حفظ الإعدادات');
  }

  Future<void> _addUser() async {
    final name = TextEditingController();
    final pin = TextEditingController();
    var role = 'cashier';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('مستخدم جديد'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'الاسم')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: const [
                  DropdownMenuItem(value: 'cashier', child: Text('كاشير')),
                  DropdownMenuItem(value: 'admin', child: Text('مدير')),
                ],
                onChanged: (v) => setD(() => role = v ?? 'cashier'),
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                      labelText: 'الرمز السري (4 إلى 6 أرقام)', counterText: '')),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final p = latinDigits(pin.text.trim());
    if (name.text.trim().isEmpty || !RegExp(r'^\d{4,6}$').hasMatch(p)) {
      _snack('اكتب الاسم ورمزًا من 4 إلى 6 أرقام');
      return;
    }
    await ref
        .read(databaseProvider)
        .createUser(name: name.text.trim(), role: role, pin: p);
  }

  Future<void> _changeMyPin() async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير الرمز السري'),
        content: TextField(
            controller: pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
                labelText: 'الرمز الجديد (4 إلى 6 أرقام)', counterText: '')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    final p = latinDigits(pin.text.trim());
    if (!RegExp(r'^\d{4,6}$').hasMatch(p)) {
      _snack('الرمز من 4 إلى 6 أرقام');
      return;
    }
    await ref
        .read(databaseProvider)
        .changePin(ref.read(sessionProvider)!.id, p);
    if (mounted) _snack('تم تغيير الرمز');
  }

  Future<void> _toggleUser(User u, bool active, List<User> all) async {
    final me = ref.read(sessionProvider);
    if (u.id == me?.id) {
      _snack('لا يمكنك إيقاف حسابك الحالي');
      return;
    }
    final activeAdmins =
        all.where((x) => x.active && x.role == 'admin' && x.id != u.id).length;
    if (!active && u.role == 'admin' && activeAdmins == 0) {
      _snack('يجب أن يبقى مدير واحد نشط على الأقل');
      return;
    }
    await ref.read(databaseProvider).setUserActive(u.id, active);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null || !session.isAdmin) {
      return const Center(child: Text('هذه الشاشة للمدير فقط'));
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('بيانات المحل',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(
            controller: _shop,
            decoration: const InputDecoration(labelText: 'اسم المحل')),
        const SizedBox(height: 10),
        TextField(
            controller: _currency,
            decoration: const InputDecoration(labelText: 'رمز العملة (مثل ج.م)')),
        const SizedBox(height: 10),
        TextField(
            controller: _vatRate,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'نسبة الضريبة % (0 = بدون ضريبة)')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('الأسعار شاملة الضريبة'),
          value: _vatInclusive,
          onChanged: (v) => setState(() => _vatInclusive = v),
        ),
        const SizedBox(height: 10),
        TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'هاتف المحل')),
        const SizedBox(height: 10),
        TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'عنوان المحل')),
        const SizedBox(height: 10),
        TextField(
            controller: _footer,
            decoration: const InputDecoration(
                labelText: 'نص أسفل الفاتورة (مثل سياسة الاسترجاع)')),
        const SizedBox(height: 20),
        const Text('الطباعة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _format,
          decoration: const InputDecoration(labelText: 'مقاس الفاتورة'),
          items: const [
            DropdownMenuItem(value: 'a4', child: Text('A4')),
            DropdownMenuItem(value: 'thermal80', child: Text('إيصال حراري 80 مم')),
            DropdownMenuItem(value: 'thermal58', child: Text('إيصال حراري 58 مم')),
          ],
          onChanged: (v) => setState(() => _format = v ?? 'a4'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('طباعة الفاتورة تلقائيًا بعد البيع'),
          value: _autoPrint,
          onChanged: (v) => setState(() => _autoPrint = v),
        ),
        const SizedBox(height: 20),
        const Text('الأمان',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: _lock,
          decoration: const InputDecoration(labelText: 'القفل التلقائي بعد الخمول'),
          items: const [
            DropdownMenuItem(value: 0, child: Text('بدون قفل')),
            DropdownMenuItem(value: 5, child: Text('5 دقائق')),
            DropdownMenuItem(value: 10, child: Text('10 دقائق')),
            DropdownMenuItem(value: 30, child: Text('30 دقيقة')),
            DropdownMenuItem(value: 60, child: Text('60 دقيقة')),
          ],
          onChanged: (v) => setState(() => _lock = v ?? 10),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _changeMyPin,
            icon: const Icon(Icons.password),
            label: const Text('تغيير رمزي السري'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('حفظ الإعدادات')),
        const SizedBox(height: 28),
        const Text('الترخيص',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Card(
            child: Padding(padding: EdgeInsets.all(16), child: LicensePanel())),
        const SizedBox(height: 28),
        Row(children: [
          const Expanded(
            child: Text('المستخدمون',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          FilledButton.icon(
              onPressed: _addUser,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('إضافة')),
        ]),
        const SizedBox(height: 8),
        for (final u in users)
          Card(
            child: SwitchListTile(
              title: Text(u.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(u.role == 'admin' ? 'مدير' : 'كاشير'),
              value: u.active,
              onChanged: (v) => _toggleUser(u, v, users),
            ),
          ),
      ],
    );
  }
}
