import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/detachment/domain/report_models.dart';
import '../../l10n/strings.dart';
import '../motion/animated_counter.dart';
import '../format/app_date.dart';

/// Produces the same report document shown by the in-app preview as a real,
/// paginated PDF. Bundled fonts keep Arabic shaping available offline.
abstract final class AttendancePdfBuilder {
  static Future<Uint8List> build(ReportDocument document) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'),
    );
    final medium = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Medium.ttf'),
    );
    final semibold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-SemiBold.ttf'),
    );
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: semibold,
        italic: medium,
        boldItalic: semibold,
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(28, 30, 28, 34),
          textDirection: pw.TextDirection.rtl,
        ),
        header: (context) => _header(document, context),
        footer: (context) => _footer(context),
        build: (context) => [
          pw.SizedBox(height: 14),
          for (final block in document.blocks) ...[
            ..._block(block),
            pw.SizedBox(height: 16),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _header(ReportDocument document, pw.Context context) =>
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColor.fromInt(0xffdad6cc)),
          ),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    document.detachmentName,
                    style: const pw.TextStyle(
                      color: PdfColor.fromInt(0xff1a1f26),
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    document.detachmentGroupName,
                    style: const pw.TextStyle(
                      color: PdfColor.fromInt(0xff4a5058),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            pw.Text(
              '${document.scopeLabel}\n${AppDate.dayMonthTime(document.generatedAt)}',
              textAlign: pw.TextAlign.left,
              style: const pw.TextStyle(
                color: PdfColor.fromInt(0xff4a5058),
                fontSize: 8,
              ),
            ),
          ],
        ),
      );

  static pw.Widget _footer(pw.Context context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColor.fromInt(0xffdad6cc)),
          ),
        ),
        alignment: pw.Alignment.center,
        child: pw.Text(
          '${S.reportPage} ${toArabicIndic('${context.pageNumber}')} '
          '${S.reportOf} ${toArabicIndic('${context.pagesCount}')}',
          style: const pw.TextStyle(
            color: PdfColor.fromInt(0xff7a8189),
            fontSize: 8,
          ),
        ),
      );

  static List<pw.Widget> _block(ReportBlock block) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xfff5e4e0),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            block.title,
            style: const pw.TextStyle(
              color: PdfColor.fromInt(0xff7a241b),
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 7),
        switch (block) {
          ReportFacts(:final pairs) => _facts(pairs),
          ReportTable(:final columns, :final data) => _table(columns, data),
          ReportSeries(:final labels, :final values) => _table(
              [S.workshopDate, block.title],
              [
                for (var index = 0; index < values.length; index++)
                  [labels[index], block.formatValue(values[index])],
              ],
            ),
        },
      ];

  static pw.Widget _facts(List<(String, String)> pairs) => pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, value) in pairs)
            pw.Container(
              width: 160,
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xfff5f3ee),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(label,
                      style: const pw.TextStyle(
                          color: PdfColor.fromInt(0xff7a8189), fontSize: 7)),
                  pw.SizedBox(height: 2),
                  pw.Text(value,
                      style: const pw.TextStyle(
                          color: PdfColor.fromInt(0xff1a1f26),
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
        ],
      );

  /// PDF tables paint columns left-to-right even in an RTL subtree, so both
  /// headers and row cells are reversed together, matching the legacy app.
  static pw.Widget _table(List<String> columns, List<List<String>> data) =>
      pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.TableHelper.fromTextArray(
          headers: columns.reversed.toList(),
          data: [for (final row in data) row.reversed.toList()],
          headerDecoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xffe4e1d9)),
          headerStyle: const pw.TextStyle(
            color: PdfColor.fromInt(0xff1a1f26),
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(
            color: PdfColor.fromInt(0xff1a1f26),
            fontSize: 7,
          ),
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.centerRight,
          cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          border: const pw.TableBorder(
            horizontalInside:
                pw.BorderSide(color: PdfColor.fromInt(0xffdad6cc), width: .5),
          ),
          oddRowDecoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xfffaf9f6)),
        ),
      );
}
