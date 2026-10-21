import 'dart:typed_data';

import 'package:barcode/barcode.dart' show Barcode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database.dart';
import '../format.dart';

/// بيانات المحل وإعدادات الطباعة (من الإعدادات).
class ShopInfo {
  final String name, phone, address, footer;
  /// a4 | thermal80 | thermal58
  final String format;
  const ShopInfo(this.name, this.phone, this.address, this.footer, this.format);

  bool get thermal => format != 'a4';
  PdfPageFormat get pageFormat => format == 'thermal58'
      ? PdfPageFormat.roll57
      : format == 'thermal80'
          ? PdfPageFormat.roll80
          : PdfPageFormat.a4;
}

Future<ShopInfo> loadShopInfo(AppDatabase db) async => ShopInfo(
      await db.getSetting('shop_name') ?? '',
      await db.getSetting('shop_phone') ?? '',
      await db.getSetting('shop_address') ?? '',
      await db.getSetting('receipt_footer') ?? '',
      await db.getSetting('receipt_format') ?? 'a4',
    );

pw.Font? _regular;
pw.Font? _bold;

Future<pw.ThemeData> _theme() async {
  _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
  _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
  return pw.ThemeData.withFont(base: _regular!, bold: _bold!);
}

// ---------- عناصر مساعدة ----------

/// نص عربي (يمين لليسار).
pw.Widget _t(String s,
        {double size = 10,
        bool bold = false,
        pw.TextAlign align = pw.TextAlign.right,
        PdfColor? color}) =>
    pw.Text(s,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color));

/// أرقام/نص لاتيني (يسار لليمين).
pw.Widget _n(String s,
        {double size = 10, bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
    pw.Text(s,
        textDirection: pw.TextDirection.ltr,
        textAlign: align,
        style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));

/// مبلغ مع العملة: العملة يسارًا والرقم يمينًا (قراءة عربية).
pw.Widget _money(int minor, {double size = 10, bool bold = false}) => pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          _t(kCurrency, size: size, bold: bold),
          pw.SizedBox(width: 2),
          _n(formatAmount(minor), size: size, bold: bold),
        ]);

/// صف «بيان ← قيمة»: البيان يمينًا والقيمة يسارًا.
pw.Widget _kv(String label, pw.Widget value, {double size = 10, bool bold = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [value, _t(label, size: size, bold: bold)],
      ),
    );

pw.Widget _cell(pw.Widget child, {bool header = false}) => pw.Container(
      color: header ? PdfColors.grey200 : null,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: child,
    );

String _dateTime(int ms) => formatDateTime(ms);

// ---------- الفاتورة ----------

Future<Uint8List> buildInvoicePdf(InvoiceData d, ShopInfo shop) async {
  final doc = pw.Document(theme: await _theme());
  if (shop.thermal) {
    final small = shop.format == 'thermal58';
    final base = shop.pageFormat;
    doc.addPage(pw.Page(
      pageFormat: base.copyWith(
        marginLeft: 3 * PdfPageFormat.mm,
        marginRight: 3 * PdfPageFormat.mm,
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 6 * PdfPageFormat.mm,
      ),
      build: (_) => _thermalBody(d, shop, small),
    ));
  } else {
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      textDirection: pw.TextDirection.rtl,
      build: (_) => _a4Body(d, shop),
    ));
  }
  return doc.save();
}

pw.Widget _thermalBody(InvoiceData d, ShopInfo shop, bool small) {
  final s = small ? 8.0 : 9.0;
  final credit = d.type == 'credit';
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    if (shop.name.isNotEmpty)
      _t(shop.name, size: small ? 12 : 14, bold: true, align: pw.TextAlign.center),
    if (shop.phone.isNotEmpty) _n(shop.phone, size: s - 1, align: pw.TextAlign.center),
    if (shop.address.isNotEmpty)
      _t(shop.address, size: s - 1, align: pw.TextAlign.center),
    pw.Divider(thickness: 0.5),
    _kv('رقم الفاتورة', _n(d.number, size: s, bold: true), size: s),
    _kv('التاريخ', _n(_dateTime(d.soldAt), size: s), size: s),
    if (d.cashierName != null)
      _kv('الكاشير', _t(d.cashierName!, size: s), size: s),
    if (d.customerName != null)
      _kv('العميل', _t(d.customerName!, size: s), size: s),
    if (d.status == 'cancelled')
      _t('ملغاة', size: 16, bold: true, align: pw.TextAlign.center),
    pw.Divider(thickness: 0.5),
    for (final l in d.lines) ...[
      _t(l.name, size: s, bold: true),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        _money(l.total, size: s),
        pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          _money(l.unitPrice, size: s - 1),
          pw.SizedBox(width: 3),
          _n('×', size: s - 1),
          pw.SizedBox(width: 3),
          _n(formatQty(l.qtyMilli), size: s - 1),
          pw.SizedBox(width: 3),
          _t(l.unitName, size: s - 1),
        ]),
      ]),
      pw.SizedBox(height: 3),
    ],
    pw.Divider(thickness: 0.5),
    if (d.discount > 0) ...[
      _kv('المجموع', _money(d.subtotal, size: s), size: s),
      _kv('الخصم', _money(d.discount, size: s), size: s),
    ],
    if (d.tax > 0)
      _kv('الضريبة', _money(d.tax, size: s), size: s),
    _kv('الإجمالي', _money(d.total, size: s + 3, bold: true), size: s + 3, bold: true),
    _kv('المدفوع', _money(d.paid, size: s), size: s),
    if (credit && d.total - d.paid > 0)
      _kv('المتبقي', _money(d.total - d.paid, size: s), size: s),
    if (credit && d.customerBalance != null)
      _kv('رصيد العميل', _money(d.customerBalance!, size: s), size: s),
    pw.SizedBox(height: 6),
    if (shop.footer.isNotEmpty)
      _t(shop.footer, size: s - 1, align: pw.TextAlign.center),
    pw.SizedBox(height: 6),
    pw.Center(
      child: pw.BarcodeWidget(
        barcode: Barcode.code128(),
        data: d.number,
        width: small ? 110 : 140,
        height: 28,
        drawText: false,
      ),
    ),
  ]);
}

List<pw.Widget> _a4Body(InvoiceData d, ShopInfo shop) {
  final credit = d.type == 'credit';
  return [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        // يسار: بيانات الفاتورة
        pw.Container(
          width: 200,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
          child: pw.Column(children: [
            _kv('رقم الفاتورة', _n(d.number, bold: true)),
            _kv('التاريخ', _n(_dateTime(d.soldAt))),
            _kv('النوع', _t(credit ? 'آجل' : 'كاش')),
            if (d.cashierName != null) _kv('الكاشير', _t(d.cashierName!)),
          ]),
        ),
        // يمين: بيانات المحل
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          if (shop.name.isNotEmpty) _t(shop.name, size: 20, bold: true),
          if (shop.address.isNotEmpty) _t(shop.address, size: 10),
          if (shop.phone.isNotEmpty) _n(shop.phone, size: 10),
        ]),
      ],
    ),
    pw.SizedBox(height: 14),
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
      _t('فاتورة بيع', size: 18, bold: true),
      if (d.status == 'cancelled') ...[
        pw.SizedBox(width: 12),
        _t('(ملغاة)', size: 18, bold: true, color: PdfColors.red800),
      ],
    ]),
    if (d.customerName != null) ...[
      pw.SizedBox(height: 6),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        if (d.customerPhone != null && d.customerPhone!.isNotEmpty) ...[
          _n(d.customerPhone!),
          pw.SizedBox(width: 10),
        ],
        _t(d.customerName!, bold: true),
        pw.SizedBox(width: 6),
        _t('العميل:'),
      ]),
    ],
    pw.SizedBox(height: 10),
    // الأعمدة من اليسار لليمين: الإجمالي، السعر، الكمية، الوحدة، الصنف
    pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(1.4),
        3: const pw.FlexColumnWidth(1.4),
        4: const pw.FlexColumnWidth(5),
      },
      children: [
        pw.TableRow(children: [
          _cell(_t('الإجمالي', bold: true, align: pw.TextAlign.center), header: true),
          _cell(_t('السعر', bold: true, align: pw.TextAlign.center), header: true),
          _cell(_t('الكمية', bold: true, align: pw.TextAlign.center), header: true),
          _cell(_t('الوحدة', bold: true, align: pw.TextAlign.center), header: true),
          _cell(_t('الصنف', bold: true), header: true),
        ]),
        for (final l in d.lines)
          pw.TableRow(children: [
            _cell(pw.Center(child: _n(formatAmount(l.total)))),
            _cell(pw.Center(child: _n(formatAmount(l.unitPrice)))),
            _cell(pw.Center(child: _n(formatQty(l.qtyMilli)))),
            _cell(_t(l.unitName, align: pw.TextAlign.center)),
            _cell(_t(l.name)),
          ]),
      ],
    ),
    pw.SizedBox(height: 12),
    pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.SizedBox(
        width: 220,
        child: pw.Column(children: [
          if (d.discount > 0) ...[
            _kv('المجموع', _money(d.subtotal)),
            _kv('الخصم', _money(d.discount)),
          ],
          if (d.tax > 0)
            _kv('الضريبة', _money(d.tax)),
          _kv('الإجمالي', _money(d.total, size: 13, bold: true), size: 13, bold: true),
          _kv('المدفوع', _money(d.paid)),
          if (credit && d.total - d.paid > 0)
            _kv('المتبقي', _money(d.total - d.paid)),
          if (credit && d.customerBalance != null)
            _kv('رصيد العميل', _money(d.customerBalance!)),
        ]),
      ),
    ),
    pw.SizedBox(height: 24),
    if (shop.footer.isNotEmpty) pw.Center(child: _t(shop.footer, size: 10)),
    pw.SizedBox(height: 10),
    pw.Center(
      child: pw.BarcodeWidget(
        barcode: Barcode.code128(),
        data: d.number,
        width: 160,
        height: 36,
        drawText: false,
      ),
    ),
  ];
}

// ---------- كشف الحساب ----------

Future<Uint8List> buildStatementPdf({
  required String title,
  required ShopInfo shop,
  required List<StatementEntry> entries,
  required int balance,
  required String plusLabel,
  required String minusLabel,
}) async {
  final doc = pw.Document(theme: await _theme());
  var running = 0;
  final rows = <pw.TableRow>[];
  for (final e in entries) {
    running += e.plus - e.minus;
    rows.add(pw.TableRow(children: [
      _cell(pw.Center(child: _n(formatAmount(running)))),
      _cell(pw.Center(child: e.minus > 0 ? _n(formatAmount(e.minus)) : pw.SizedBox())),
      _cell(pw.Center(child: e.plus > 0 ? _n(formatAmount(e.plus)) : pw.SizedBox())),
      _cell(_t(e.title)),
      _cell(pw.Center(child: _n(_dateTime(e.at), size: 9))),
    ]));
  }
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    textDirection: pw.TextDirection.rtl,
    build: (_) => [
      if (shop.name.isNotEmpty)
        pw.Align(
            alignment: pw.Alignment.centerRight,
            child: _t(shop.name, size: 16, bold: true)),
      pw.SizedBox(height: 6),
      pw.Align(alignment: pw.Alignment.centerRight, child: _t(title, size: 18, bold: true)),
      pw.SizedBox(height: 4),
      pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _t('تاريخ الطباعة: ${_dateTime(DateTime.now().millisecondsSinceEpoch)}',
              size: 9)),
      pw.SizedBox(height: 10),
      // من اليسار: الرصيد، الثاني، الأول، البيان، التاريخ
      pw.Table(
        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
        columnWidths: {
          0: const pw.FlexColumnWidth(2),
          1: const pw.FlexColumnWidth(2),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(5),
          4: const pw.FlexColumnWidth(3),
        },
        children: [
          pw.TableRow(children: [
            _cell(_t('الرصيد', bold: true, align: pw.TextAlign.center), header: true),
            _cell(_t(minusLabel, bold: true, align: pw.TextAlign.center), header: true),
            _cell(_t(plusLabel, bold: true, align: pw.TextAlign.center), header: true),
            _cell(_t('البيان', bold: true), header: true),
            _cell(_t('التاريخ', bold: true, align: pw.TextAlign.center), header: true),
          ]),
          ...rows,
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.SizedBox(
          width: 220,
          child: _kv('الرصيد الحالي', _money(balance, size: 13, bold: true),
              size: 13, bold: true),
        ),
      ),
    ],
  ));
  return doc.save();
}

// ---------- تقرير المبيعات ----------

Future<Uint8List> buildReportPdf({
  required ShopInfo shop,
  required String period,
  required ReportData r,
  int? inventoryValue,
  int? receivables,
  int? payables,
}) async {
  final doc = pw.Document(theme: await _theme());
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    textDirection: pw.TextDirection.rtl,
    build: (_) => [
      if (shop.name.isNotEmpty)
        pw.Align(
            alignment: pw.Alignment.centerRight,
            child: _t(shop.name, size: 16, bold: true)),
      pw.SizedBox(height: 6),
      pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _t('تقرير المبيعات — $period', size: 18, bold: true)),
      pw.SizedBox(height: 12),
      _kv('إجمالي المبيعات', _money(r.salesTotal), size: 12),
      _kv('عدد الفواتير', _n('${r.salesCount}', size: 12), size: 12),
      _kv('كاش', _money(r.cashTotal), size: 12),
      _kv('آجل', _money(r.creditTotal), size: 12),
      _kv('المرتجعات', _money(r.returnsTotal), size: 12),
      _kv('صافي المبيعات', _money(r.net, bold: true), size: 12, bold: true),
      _kv('الربح التقريبي', _money(r.profit, bold: true), size: 12, bold: true),
      if (inventoryValue != null || receivables != null || payables != null) ...[
        pw.Divider(),
        if (inventoryValue != null)
          _kv('قيمة المخزون (بالتكلفة)', _money(inventoryValue), size: 12),
        if (receivables != null)
          _kv('مستحقات عند العملاء', _money(receivables), size: 12),
        if (payables != null) _kv('مستحقات للموردين', _money(payables), size: 12),
      ],
      pw.SizedBox(height: 14),
      pw.Align(alignment: pw.Alignment.centerRight, child: _t('الأكثر مبيعًا', size: 14, bold: true)),
      pw.SizedBox(height: 6),
      if (r.top.isEmpty)
        pw.Align(alignment: pw.Alignment.centerRight, child: _t('لا توجد مبيعات في هذه الفترة'))
      else
        pw.Table(
          border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(5),
          },
          children: [
            pw.TableRow(children: [
              _cell(_t('القيمة', bold: true, align: pw.TextAlign.center), header: true),
              _cell(_t('الكمية', bold: true, align: pw.TextAlign.center), header: true),
              _cell(_t('الصنف', bold: true), header: true),
            ]),
            for (final t in r.top)
              pw.TableRow(children: [
                _cell(pw.Center(child: _n(formatAmount(t.revenue)))),
                _cell(pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      _t(t.baseUnit),
                      pw.SizedBox(width: 3),
                      _n(formatQty(t.baseQtyMilli)),
                    ])),
                _cell(_t(t.name)),
              ]),
          ],
        ),
    ],
  ));
  return doc.save();
}

// ---------- ملصقات الباركود ----------

class LabelSpec {
  final String name, unitName, code;
  final int price, copies;
  const LabelSpec(this.name, this.unitName, this.price, this.code, this.copies);
}

/// المقاسات: العرض والارتفاع بالملم (a4 = شبكة 3×8 على ورقة A4).
const labelSizes = <String, ({String label, double w, double h})>{
  'l4030': (label: 'ملصق 40×30 مم', w: 40.0, h: 30.0),
  'l5030': (label: 'ملصق 50×30 مم', w: 50.0, h: 30.0),
  'l6040': (label: 'ملصق 60×40 مم', w: 60.0, h: 40.0),
  'a4': (label: 'ورق A4 (3×8)', w: 66.0, h: 34.0),
};

pw.Widget _label(LabelSpec s, double w, double h, String shopName) {
  final small = h <= 32;
  final nameSize = small ? 7.0 : 9.0;
  return pw.Container(
    width: w * PdfPageFormat.mm,
    height: h * PdfPageFormat.mm,
    padding: const pw.EdgeInsets.all(3),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _t(s.name, size: nameSize, bold: true, align: pw.TextAlign.center),
        pw.SizedBox(height: 1),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          _t(s.unitName, size: nameSize - 1),
          pw.SizedBox(width: 3),
          _money(s.price, size: small ? 9 : 12, bold: true),
        ]),
        pw.SizedBox(height: 2),
        pw.Expanded(
          child: pw.BarcodeWidget(
            barcode: Barcode.code128(),
            data: s.code,
            drawText: true,
            textStyle: pw.TextStyle(fontSize: small ? 6 : 7),
          ),
        ),
      ],
    ),
  );
}

Future<Uint8List> buildLabelsPdf(
    List<LabelSpec> specs, String sizeKey, String shopName) async {
  final doc = pw.Document(theme: await _theme());
  final size = labelSizes[sizeKey] ?? labelSizes['l4030']!;
  final all = <LabelSpec>[
    for (final s in specs)
      for (var i = 0; i < s.copies; i++) s,
  ];
  if (sizeKey == 'a4') {
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 6 * PdfPageFormat.mm, vertical: 10 * PdfPageFormat.mm),
      build: (_) => [
        pw.Wrap(children: [
          for (final s in all)
            pw.Container(
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.3, color: PdfColors.grey400)),
              child: _label(s, size.w, size.h, shopName),
            ),
        ]),
      ],
    ));
  } else {
    final fmt = PdfPageFormat(size.w * PdfPageFormat.mm, size.h * PdfPageFormat.mm);
    for (final s in all) {
      doc.addPage(pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.zero,
        build: (_) => _label(s, size.w, size.h, shopName),
      ));
    }
  }
  return doc.save();
}

// ---------- الطباعة والمشاركة ----------

Future<void> printPdf(Uint8List bytes, String name, {PdfPageFormat? format}) =>
    Printing.layoutPdf(
      name: name,
      format: format ?? PdfPageFormat.a4,
      onLayout: (_) async => bytes,
    );

Future<void> sharePdf(Uint8List bytes, String filename) =>
    Printing.sharePdf(bytes: bytes, filename: filename);

Future<void> printInvoice(AppDatabase db, String saleId) async {
  final d = await db.invoiceForPrint(saleId);
  final shop = await loadShopInfo(db);
  final bytes = await buildInvoicePdf(d, shop);
  await printPdf(bytes, 'فاتورة ${d.number}', format: shop.pageFormat);
}

Future<void> shareInvoice(AppDatabase db, String saleId) async {
  final d = await db.invoiceForPrint(saleId);
  final shop = await loadShopInfo(db);
  final bytes = await buildInvoicePdf(d, shop);
  await sharePdf(bytes, 'invoice-${d.number}.pdf');
}