import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/format/app_time.dart';
import '../../../core/export/attendance_pdf.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_meta.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/section_header.dart';
import '../../../l10n/strings.dart';
import '../data/report_builder.dart';
import '../domain/report_models.dart';

/// Build a report: choose the sections, the span, and the format.
///
/// This screen exists because "export" as a single button is a guess about
/// what someone needs. Eight switches and a live preview turn it into a
/// decision they make, and the running count under the header keeps the
/// choice visible while they scroll.
class ReportExportPage extends ConsumerStatefulWidget {
  const ReportExportPage({super.key, required this.detachmentId});

  final String detachmentId;

  @override
  ConsumerState<ReportExportPage> createState() => _ReportExportPageState();
}

class _ReportExportPageState extends ConsumerState<ReportExportPage> {
  ReportSpec _spec = ReportSpec.initial;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final chosen = _spec.sections.length;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text(S.exportTitle),
        actions: [
          TextButton(
            onPressed: () => setState(() => _spec = _spec.withAll(
                  chosen != ReportSection.values.length,
                )),
            child: Text(
              chosen == ReportSection.values.length
                  ? S.exportClearAll
                  : S.exportSelectAll,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxxl),
        children: [
          Text(S.exportSub,
              style: TextStyle(color: c.ink3, fontSize: 13, height: 1.6)),
          const SectionHeader(title: S.exportRange),
          Row(children: [
            for (final r in ReportRange.values) ...[
              Expanded(
                child: _Choice(
                  label: r.label,
                  selected: _spec.range == r,
                  onTap: () => setState(() => _spec = _spec.withRange(r)),
                ),
              ),
              if (r != ReportRange.values.last)
                const SizedBox(width: AppSpacing.sm),
            ],
          ]),
          const SectionHeader(title: S.exportFormat),
          Row(children: [
            for (final f in ReportFormat.values) ...[
              Expanded(
                child: _Choice(
                  label: f.label,
                  icon: f == ReportFormat.pdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.grid_on_rounded,
                  selected: _spec.format == f,
                  onTap: () => setState(() => _spec = _spec.withFormat(f)),
                ),
              ),
              if (f != ReportFormat.values.last)
                const SizedBox(width: AppSpacing.sm),
            ],
          ]),
          SectionHeader(
            title: '${S.exportSections} · '
                '${toArabicIndic('$chosen')} ${S.sectionsChosen}',
          ),
          for (final s in ReportSection.values) ...[
            _SectionSwitch(
              section: s,
              value: _spec.has(s),
              onChanged: () => setState(() => _spec = _spec.toggle(s)),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.lg),
          _Actions(
            detachmentId: widget.detachmentId,
            spec: _spec,
            busy: _busy,
            onBusy: (v) => setState(() => _busy = v),
          ),
        ],
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.detachmentId,
    required this.spec,
    required this.busy,
    required this.onBusy,
  });

  final String detachmentId;
  final ReportSpec spec;
  final bool busy;
  final ValueChanged<bool> onBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empty = spec.sections.isEmpty;
    // Reading statistics is the capability the report rests on: a report is
    // a statistics screen in a file.
    final canExport =
        ref.capabilities.canIn(detachmentId, Cap.statsView) && !empty;

    return Column(children: [
      if (empty)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(S.exportNothingSelected,
              style: TextStyle(color: context.c.warn, fontSize: 13)),
        ),
      FilledButton.icon(
        onPressed: canExport && !busy
            ? () => context.push(
                  '/detachment/$detachmentId/report/preview',
                  extra: spec,
                )
            : null,
        icon: const Icon(Icons.visibility_outlined),
        label: const Text(S.exportPreview),
      ),
      const SizedBox(height: AppSpacing.sm),
      OutlinedButton.icon(
        onPressed: canExport && !busy ? () => _export(context, ref) : null,
        icon: Icon(
          spec.format == ReportFormat.pdf
              ? Icons.ios_share_rounded
              : Icons.copy_all_rounded,
          size: 19,
        ),
        label: Text(
          spec.format == ReportFormat.pdf ? S.exportPdf : S.exportCopy,
        ),
      ),
    ]);
  }

  /// Puts the built file's content on the clipboard.
  ///
  /// ASSUMPTION: this build ships no file-writing or sharing plugin, so the
  /// clipboard is the delivery channel. The document itself is fully built
  /// here — CSV for the spreadsheet path, laid-out text for the other — so
  /// wiring a real `.csv`/`.pdf` write is a delivery change, not a rebuild:
  /// swap this one method for a file write plus a share sheet.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    onBusy(true);
    final result = await ref.read(
      reportProvider(ReportQuery(detachmentId: detachmentId, spec: spec))
          .future,
    );
    onBusy(false);
    if (!context.mounted) return;

    result.when(
      success: (doc, {stale = false}) async {
        try {
          if (spec.format == ReportFormat.pdf) {
            final bytes = await AttendancePdfBuilder.build(doc);
            await Printing.sharePdf(
              bytes: bytes,
              filename: 'leader-report.pdf',
            );
          } else {
            await Clipboard.setData(ClipboardData(text: doc.toCsv()));
          }
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text(S.pdfError)));
          return;
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            spec.format == ReportFormat.pdf ? S.pdfReady : S.exportCopied,
          ),
        ));
      },
      failure: (message, _) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: AnimatedContainer(
        duration: effectiveDuration(context, MotionTokens.short),
        curve: effectiveCurve(context, MotionTokens.standard),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : c.surface,
          border: Border.all(color: selected ? c.primary : c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: selected ? c.primary : c.ink3),
            const SizedBox(width: 6),
          ],
          // Three of these share a row, so on a narrow phone the label has to
          // give rather than push past the tile's edge.
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? c.primary : c.ink2,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                )),
          ),
        ]),
      ),
    );
  }
}

class _SectionSwitch extends StatelessWidget {
  const _SectionSwitch({
    required this.section,
    required this.value,
    required this.onChanged,
  });

  final ReportSection section;
  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: AnimatedContainer(
        duration: effectiveDuration(context, MotionTokens.short),
        curve: effectiveCurve(context, MotionTokens.standard),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: value ? c.primaryTint : c.surface,
          border: Border.all(color: value ? c.primary : c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(children: [
          Icon(
            value
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: value ? c.primary : c.ink3,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section.title,
                    style: TextStyle(
                      color: value ? c.primary : c.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 2),
                Text(section.subtitle,
                    style: TextStyle(color: c.ink3, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Shared by the preview: a report block rendered as it will appear.
class ReportBlockView extends StatelessWidget {
  const ReportBlockView({super.key, required this.block});

  final ReportBlock block;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(block.title,
            style: TextStyle(
                color: c.ink, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        switch (block) {
          ReportFacts(:final pairs) => _Facts(pairs: pairs),
          ReportTable(:final columns, :final data) =>
            _Table(columns: columns, data: data),
          ReportSeries() => _Series(series: block as ReportSeries),
        },
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.pairs});

  final List<(String, String)> pairs;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(children: [
      for (final (label, value) in pairs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(
              child: Text(label, style: TextStyle(color: c.ink3, fontSize: 13)),
            ),
            Text(value,
                style: TextStyle(
                    color: c.ink, fontSize: 13, fontWeight: FontWeight.w500)),
          ]),
        ),
    ]);
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.columns, required this.data});

  final List<String> columns;
  final List<List<String>> data;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (data.isEmpty) {
      return Text(S.noData, style: TextStyle(color: c.ink3, fontSize: 13));
    }
    // A wide table scrolls inside its own box; the page itself must never
    // scroll sideways.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 44,
        horizontalMargin: 0,
        columnSpacing: AppSpacing.lg,
        dividerThickness: 0.6,
        headingTextStyle:
            TextStyle(color: c.ink3, fontSize: 12, fontWeight: FontWeight.w600),
        dataTextStyle: TextStyle(color: c.ink, fontSize: 12.5),
        columns: [for (final col in columns) DataColumn(label: Text(col))],
        rows: [
          for (final row in data)
            DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
        ],
      ),
    );
  }
}

class _Series extends StatelessWidget {
  const _Series({required this.series});

  final ReportSeries series;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final max = series.max;
    return Column(children: [
      SizedBox(
        height: 80,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < series.values.length; i++) ...[
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.bottomCenter,
                  heightFactor:
                      max == 0 ? 0.02 : (series.values[i] / max).clamp(0.02, 1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: series.values[i] == 0 ? c.surface3 : c.primary,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                  ),
                ),
              ),
              if (i != series.values.length - 1) const SizedBox(width: 5),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(children: [
        Text(S.highest, style: TextStyle(color: c.ink3, fontSize: 12)),
        const SizedBox(width: 6),
        Text(series.formatValue(max),
            style: AppTypography.digits(c.ink, size: 13)),
        const SizedBox(width: AppSpacing.lg),
        Text(S.average, style: TextStyle(color: c.ink3, fontSize: 12)),
        const SizedBox(width: 6),
        Text(series.formatValue(series.average),
            style: AppTypography.digits(c.ink, size: 13)),
      ]),
    ]);
  }
}

/// Loading and failure for a built report, so the preview page and any future
/// consumer render the same four states.
class ReportView extends ConsumerWidget {
  const ReportView({
    super.key,
    required this.detachmentId,
    required this.spec,
    required this.builder,
  });

  final String detachmentId;
  final ReportSpec spec;
  final Widget Function(BuildContext context, ReportDocument doc) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ReportQuery(detachmentId: detachmentId, spec: spec);
    return AsyncResultView<ReportDocument>(
      value: ref.watch(reportProvider(query)),
      onRetry: () => ref.invalidate(reportProvider),
      builder: (context, doc, stale) => builder(context, doc),
    );
  }
}

/// The header of the printed document — who it is for and when it was made.
class ReportHeader extends StatelessWidget {
  const ReportHeader({super.key, required this.doc});

  final ReportDocument doc;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${S.reportFor} · ${doc.detachmentName}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(doc.detachmentGroupName,
            style: TextStyle(color: c.ink3, fontSize: 13)),
        const SizedBox(height: 6),
        // Two facts, one line, and no printed mark between them: the
        // generated-at clock ends in a numeral and a ` · ` beside it is the
        // Arabic-Indic zero (UI audit P1-11). `AppMeta` draws the rule
        // outside the text run instead.
        AppMeta(parts: [
          AppMetaText('${S.reportGeneratedAt} '
              '${AppTime.dayTime(doc.generatedAt)}'),
          AppMetaText(doc.range.label),
        ]),
      ],
    );
  }
}
