import '../../../core/format/app_number.dart';
import '../../../l10n/strings.dart';

/// What can go into an exported report, one switch per section.
///
/// The list is the contract between the composer screen, the builder, and
/// the preview: adding a section here is the only place a new one has to be
/// declared, and every consumer switches exhaustively over it.
enum ReportSection {
  summary,
  members,
  shifts,
  storage,
  storageLow,
  attendance,
  coverage,
  consumption,
}

extension ReportSectionLabels on ReportSection {
  String get title => switch (this) {
        ReportSection.summary => S.secSummary,
        ReportSection.members => S.secMembers,
        ReportSection.shifts => S.secShifts,
        ReportSection.storage => S.secStorage,
        ReportSection.storageLow => S.secStorageLow,
        ReportSection.attendance => S.secAttendance,
        ReportSection.coverage => S.secCoverage,
        ReportSection.consumption => S.secConsumption,
      };

  String get subtitle => switch (this) {
        ReportSection.summary => S.secSummarySub,
        ReportSection.members => S.secMembersSub,
        ReportSection.shifts => S.secShiftsSub,
        ReportSection.storage => S.secStorageSub,
        ReportSection.storageLow => S.secStorageLowSub,
        ReportSection.attendance => S.secAttendanceSub,
        ReportSection.coverage => S.secCoverageSub,
        ReportSection.consumption => S.secConsumptionSub,
      };
}

/// How far back the dated sections reach.
enum ReportRange { week, month, quarter }

extension ReportRangeSpan on ReportRange {
  int get days => switch (this) {
        ReportRange.week => 7,
        ReportRange.month => 30,
        ReportRange.quarter => 90,
      };

  String get label => switch (this) {
        ReportRange.week => S.rangeWeek,
        ReportRange.month => S.rangeMonth,
        ReportRange.quarter => S.rangeQuarter,
      };
}

/// PDF is a laid-out document; Excel is a grid. The distinction changes what
/// a chart section becomes — a drawn series in one, its underlying numbers in
/// the other — so it is chosen before the file is built, not after.
enum ReportFormat { pdf, excel }

extension ReportFormatLabels on ReportFormat {
  String get label => switch (this) {
        ReportFormat.pdf => S.exportPdf,
        ReportFormat.excel => S.exportExcel,
      };
}

/// The user's choices. This is what the composer screen edits and what the
/// builder reads; nothing else decides what a report contains.
class ReportSpec {
  const ReportSpec({
    required this.sections,
    required this.range,
    required this.format,
  });

  final Set<ReportSection> sections;
  final ReportRange range;
  final ReportFormat format;

  /// The default selection: what a detachment lead would put in a weekly
  /// report without being asked. Everything else is opt-in, so the first
  /// export is one tap and the composer is still fully open.
  static const ReportSpec initial = ReportSpec(
    sections: {
      ReportSection.summary,
      ReportSection.shifts,
      ReportSection.storageLow,
    },
    range: ReportRange.week,
    format: ReportFormat.pdf,
  );

  bool has(ReportSection s) => sections.contains(s);

  ReportSpec toggle(ReportSection s) => ReportSpec(
        sections: has(s) ? ({...sections}..remove(s)) : ({...sections}..add(s)),
        range: range,
        format: format,
      );

  ReportSpec withRange(ReportRange r) =>
      ReportSpec(sections: sections, range: r, format: format);

  ReportSpec withFormat(ReportFormat f) =>
      ReportSpec(sections: sections, range: range, format: f);

  ReportSpec withAll(bool selected) => ReportSpec(
        sections: selected ? ReportSection.values.toSet() : const {},
        range: range,
        format: format,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportSpec &&
          other.range == range &&
          other.format == format &&
          other.sections.length == sections.length &&
          other.sections.containsAll(sections);

  @override
  int get hashCode => Object.hash(
        range,
        format,
        Object.hashAllUnordered(sections),
      );
}

/// One block of a built report. Three shapes cover everything the app can
/// export, and each one knows how to flatten itself into rows — which is all
/// a spreadsheet is.
sealed class ReportBlock {
  const ReportBlock(this.title);
  final String title;

  /// The block as a grid: first row is the header when it has one.
  List<List<String>> get rows;
}

/// Label/value pairs — the summary block.
class ReportFacts extends ReportBlock {
  const ReportFacts(super.title, this.pairs);
  final List<(String label, String value)> pairs;

  @override
  List<List<String>> get rows => [
        for (final (label, value) in pairs) [label, value],
      ];
}

/// A real table with a header row.
class ReportTable extends ReportBlock {
  const ReportTable(super.title, this.columns, this.data);
  final List<String> columns;
  final List<List<String>> data;

  @override
  List<List<String>> get rows => [columns, ...data];
}

/// A daily series. Drawn as bars in the PDF preview; written out as one row
/// per day in the spreadsheet, because a picture of a chart is not something
/// anyone can sum.
class ReportSeries extends ReportBlock {
  const ReportSeries(super.title, this.labels, this.values, {this.suffix = ''});
  final List<String> labels;
  final List<int> values;
  final String suffix;

  int get max => values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
  int get average => values.isEmpty
      ? 0
      : (values.reduce((a, b) => a + b) / values.length).round();

  String formatValue(int value) => suffix == S.percentSign
      ? AppNumber.percent(value)
      : '${AppNumber.count(value)}$suffix';

  @override
  List<List<String>> get rows => [
        for (int i = 0; i < values.length; i++)
          [labels[i], formatValue(values[i])],
      ];
}

/// A built report, ready to render or serialise.
class ReportDocument {
  const ReportDocument({
    required this.detachmentName,
    required this.detachmentGroupName,
    required this.generatedAt,
    required this.range,
    required this.blocks,
    this.headerNote,
  });

  final String detachmentName;
  final String detachmentGroupName;
  final DateTime generatedAt;
  final ReportRange range;
  final List<ReportBlock> blocks;

  /// Overrides the small print beside the title. A detachment report is
  /// scoped by a window ("last 7 days") and says so; a document scoped to one
  /// dated thing — a workshop — puts that thing's own date there instead,
  /// because printing a window on it would be a lie.
  final String? headerNote;

  /// What the header actually prints.
  String get scopeLabel => headerNote ?? range.label;

  bool get isEmpty => blocks.isEmpty;

  /// CSV, which is what "Excel" means for a file this app can produce
  /// without a spreadsheet library. Comma-separated, quotes doubled, UTF-8 —
  /// Excel and LibreOffice both open it directly.
  ///
  /// Blocks are stacked with their titles as single-cell rows and a blank row
  /// between them, so one file carries every chosen section instead of
  /// forcing an export per section.
  String toCsv() {
    final buffer = StringBuffer()
      ..writeln(_csvRow([detachmentName, detachmentGroupName]))
      ..writeln(_csvRow([S.reportGeneratedAt, generatedAt.toString()]))
      ..writeln();
    for (final block in blocks) {
      buffer.writeln(_csvRow([block.title]));
      for (final row in block.rows) {
        buffer.writeln(_csvRow(row));
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// A plain-text rendering of the same document, for the PDF path until a
  /// real writer is available. Columns are padded so the text keeps the
  /// table's shape when pasted somewhere fixed-width.
  String toPlainText() {
    final buffer = StringBuffer()
      ..writeln('$detachmentName — $detachmentGroupName')
      ..writeln('${S.reportGeneratedAt} $generatedAt')
      ..writeln();
    for (final block in blocks) {
      buffer
        ..writeln('■ ${block.title}')
        ..writeln();
      for (final row in block.rows) {
        buffer.writeln('   ${row.join('   ·   ')}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  static String _csvRow(List<String> cells) =>
      cells.map((cell) => '"${cell.replaceAll('"', '""')}"').join(',');
}
