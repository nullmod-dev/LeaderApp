import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/export/attendance_pdf.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/detachment/data/report_builder.dart';
import 'package:mtm/features/detachment/domain/report_models.dart';
import 'package:mtm/l10n/strings.dart';

T _success<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => fail('$message ($code)'),
      offline: (_) => fail('offline'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real PDF paginates multilingual attendance and absence records',
      () async {
    final rows = <List<String>>[
      for (var index = 0; index < 90; index++)
        [
          '${(index % 28) + 1}/09/2026',
          index % 5 == 0 ? 'Absent' : 'Checked out',
          index % 5 == 0 ? '—' : '08:00',
          index % 5 == 0 ? '—' : '14:00',
        ],
    ];
    final document = ReportDocument(
      detachmentName: 'مفرزة دمشق المركزية — Damascus Central Detachment',
      detachmentGroupName: 'Medical Team',
      generatedAt: DateTime(2026, 9, 2, 12, 30),
      range: ReportRange.quarter,
      blocks: [
        const ReportFacts('Attendance totals', [
          ('Present', '72'),
          ('Absent', '18'),
          ('Completed', '72'),
        ]),
        ReportTable(
          'أحمد كنعان — A member with an intentionally long display name for wrapping',
          const ['Attendance date', 'Status', 'Check-in', 'Check-out'],
          rows,
        ),
        const ReportTable(
          'ليلى ياسين',
          ['تاريخ الحضور', 'الحالة', 'الدخول', 'الخروج'],
          [
            ['٢ أيلول', 'غياب', '—', '—'],
            ['١ أيلول', 'سجّل الخروج', '٠٨:٠٠', '١٤:٠٠'],
          ],
        ),
      ],
    );

    final bytes = await AttendancePdfBuilder.build(document);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(20000));

    final output = File('../output/pdf/attendance-sample.pdf');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes, flush: true);
    expect(await output.exists(), isTrue);
  });

  test('the full report pipeline produces a paginated, complete PDF', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Everything the composer can switch on, over the widest range, so the
    // rendered file exercises facts, tables, series, Arabic and Latin names,
    // and enough rows to force pagination.
    final document = _success(
      await container.read(
        reportProvider(
          const ReportQuery(
            detachmentId: 'd_dam_central',
            spec: ReportSpec(
              sections: {
                ReportSection.summary,
                ReportSection.members,
                ReportSection.shifts,
                ReportSection.storage,
                ReportSection.storageLow,
                ReportSection.attendance,
                ReportSection.coverage,
                ReportSection.consumption,
              },
              range: ReportRange.quarter,
              format: ReportFormat.pdf,
            ),
          ),
        ).future,
      ),
    );

    // The attendance sections the report is really about are present.
    final titles = [for (final block in document.blocks) block.title];
    expect(titles, contains(S.secAttendance));
    expect(titles, contains(S.attendanceSummary));

    final summary = document.blocks.whereType<ReportTable>().firstWhere(
          (block) => block.title == S.attendanceSummary,
        );
    expect(summary.columns, hasLength(6));
    expect(summary.data, isNotEmpty);

    // Per-member detail tables carry the dated check-in/check-out columns.
    final detail = document.blocks.whereType<ReportTable>().where(
          (block) => block.columns.contains(S.checkInTime),
        );
    expect(detail, isNotEmpty);
    expect(
      detail.any((block) => block.data.any((row) => row.contains(S.absent))),
      isTrue,
      reason: 'the seeded weeks include absences, which must reach the report',
    );

    final bytes = await AttendancePdfBuilder.build(document);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');

    final output = File('../output/pdf/detachment-report.pdf');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes, flush: true);
    expect(await output.exists(), isTrue);
  });
}
