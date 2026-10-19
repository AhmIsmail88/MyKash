import 'package:intl/intl.dart';

/// رمز العملة (سيُقرأ من الإعدادات لاحقًا).
String kCurrency = 'ج.م';

/// المبالغ تُخزَّن بأصغر وحدة (قرش): 9500 = 95.00
String formatMoney(int minor) {
  final v = minor / 100;
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  return '$s $kCurrency';
}

String _latinDigits(String s) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = arabic.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (ch == '٫' || ch == '،' || ch == ',') {
      b.write('.');
    } else {
      b.write(ch);
    }
  }
  return b.toString().trim();
}

/// يحوّل نص المستخدم (مثل "95.5") إلى قروش.
int parseMoney(String s) =>
    ((double.tryParse(_latinDigits(s)) ?? 0) * 100).round();

/// الكميات تُخزَّن مضروبة في 1000: 2500 = 2.5
int parseQty(String s) =>
    ((double.tryParse(_latinDigits(s)) ?? 0) * 1000).round();

String formatQty(int milli) {
  if (milli % 1000 == 0) return '${milli ~/ 1000}';
  return (milli / 1000).toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
}

/// نسخة عامة لتحويل الأرقام العربية إلى لاتينية (للـ PIN والإدخال).
String latinDigits(String s) => _latinDigits(s);

/// قيمة المبلغ لعرضها داخل حقل إدخال (بدون رمز العملة).
String moneyInput(int minor) =>
    minor % 100 == 0 ? '${minor ~/ 100}' : (minor / 100).toStringAsFixed(2);

String formatDateTime(int ms) =>
    DateFormat('yyyy/MM/dd  HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));

/// المبلغ بدون رمز العملة (للطباعة).
String formatAmount(int minor) {
  final v = minor / 100;
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
