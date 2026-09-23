import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../../core/export/attendance_pdf.dart';
import '../../../../core/motion/animated_counter.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/motion/press_scale.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/time/clock.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../l10n/strings.dart';
import '../../../detachment/domain/report_models.dart';
import '../../data/workshop_stats_report.dart';
import '../../domain/workshop_models.dart';
import '../../domain/workshop_stats.dart';

/// Whether an export produced anything.
enum WorkshopExportOutcome { delivered, empty }

/// Builds the workshop report from the already-loaded [stats] — no second
/// read — and delivers it the way this app delivers every report:
///
/// * **PDF** through `Printing.sharePdf`, the platform share sheet;
/// * **spreadsheet** as CSV on the clipboard.
///
/// The second half is the same documented limitation the detachment report
/// export carries: this build ships no file-writing or sharing plugin beyond
/// `printing`, so the clipboard is the delivery channel for anything that is
/// not a PDF. The document itself is fully built either way, so wiring a real
/// `.csv`/`.xlsx` write later is a delivery change, not a rebuild.
Future<WorkshopExportOutcome> exportWorkshopReport(
  WorkshopStats stats, {
  required ReportFormat format,
  required DateTime generatedAt,
  Set<WorkshopReportSection> sections = const {
    WorkshopReportSection.summary,
    WorkshopReportSection.participants,
    WorkshopReportSection.team,
  },
}) async {
  final wantsPeople = sections.contains(WorkshopReportSection.participants) ||
      sections.contains(WorkshopReportSection.team);
  final hasPeople = stats.people.isNotEmpty;
  if (sections.isEmpty || (wantsPeople && !hasPeople && sections.length == 1)) {
    return WorkshopExportOutcome.empty;
  }

  final document = buildWorkshopStatsReport(
    stats,
    sections: sections,
    generatedAt: generatedAt,
  );
  if (document.isEmpty) return WorkshopExportOutcome.empty;

  if (format == ReportFormat.pdf) {
    final bytes = await AttendancePdfBuilder.build(document);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'workshop-${stats.id}-report.pdf',
    );
  } else {
    await Clipboard.setData(ClipboardData(text: document.toCsv()));
  }
  return WorkshopExportOutcome.delivered;
}

/// One-tap full-report export: attendance and payment summary with the
/// financial total, the named participants list, and the named team list.
/// The third button opens the section picker for anything narrower.
class WorkshopStatsExportCard extends ConsumerStatefulWidget {
  const WorkshopStatsExportCard({super.key, required this.stats});

  final WorkshopStats stats;

  @override
  ConsumerState<WorkshopStatsExportCard> createState() =>
      _WorkshopStatsExportCardState();
}

class _WorkshopStatsExportCardState
    extends ConsumerState<WorkshopStatsExportCard> {
  ReportFormat? _busyWith;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return _StatsCard(
      title: S.statsExportTitle,
      subtitle: S.statsExportSub,
      child: Column(children: [
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed:
                  _busyWith != null ? null : () => _export(ReportFormat.pdf),
              icon: _busyWith == ReportFormat.pdf
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text(S.exportPdf),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  _busyWith != null ? null : () => _export(ReportFormat.excel),
              icon: const Icon(Icons.table_view_outlined, size: 18),
              label: const Text(S.exportExcel),
            ),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: _busyWith != null
                ? null
                : () => showWorkshopExportSheet(context, stats: widget.stats),
            icon: Icon(Icons.tune_rounded, size: 18, color: c.primary),
            label: const Text(S.statsExportCustom),
          ),
        ),
      ]),
    );
  }

  Future<void> _export(ReportFormat format) async {
    setState(() => _busyWith = format);
    await runWorkshopExport(
      context,
      stats: widget.stats,
      format: format,
      generatedAt: ref.read(clockProvider)(),
    );
    if (mounted) setState(() => _busyWith = null);
  }
}

/// Runs an export and reports the outcome in one place, so the card and the
/// sheet cannot drift on what "it worked" looks like.
Future<WorkshopExportOutcome?> runWorkshopExport(
  BuildContext context, {
  required WorkshopStats stats,
  required ReportFormat format,
  required DateTime generatedAt,
  Set<WorkshopReportSection> sections = const {
    WorkshopReportSection.summary,
    WorkshopReportSection.participants,
    WorkshopReportSection.team,
  },
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final outcome = await exportWorkshopReport(
      stats,
      format: format,
      sections: sections,
      generatedAt: generatedAt,
    );
    messenger.showSnackBar(SnackBar(
      content: Text(switch (outcome) {
        WorkshopExportOutcome.empty => S.statsExportEmpty,
        WorkshopExportOutcome.delivered =>
          format == ReportFormat.pdf ? S.pdfReady : S.exportCopied,
      }),
    ));
    return outcome;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text(S.pdfError)));
    return null;
  }
}

/// The selective export: choose the sections, then the format.
Future<void> showWorkshopExportSheet(
  BuildContext context, {
  required WorkshopStats stats,
}) {
  return showAppSheet<void>(
    context: context,
    title: S.statsExportCustom,
    child: _ExportSheetBody(stats: stats),
  );
}

class _ExportSheetBody extends ConsumerStatefulWidget {
  const _ExportSheetBody({required this.stats});

  final WorkshopStats stats;

  @override
  ConsumerState<_ExportSheetBody> createState() => _ExportSheetBodyState();
}

class _ExportSheetBodyState extends ConsumerState<_ExportSheetBody> {
  final Set<WorkshopReportSection> _sections =
      WorkshopReportSection.values.toSet();
  bool _busy = false;

  bool get _canExport => !_busy && _sections.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.statsExportCustomSub,
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final section in WorkshopReportSection.values) ...[
            const SizedBox(height: AppSpacing.sm),
            _SectionToggle(
              section: section,
              value: _sections.contains(section),
              onChanged: _busy
                  ? null
                  : () => setState(() {
                        if (!_sections.remove(section)) _sections.add(section);
                      }),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _canExport ? () => _export(ReportFormat.pdf) : null,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text(S.exportPdf),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _canExport ? () => _export(ReportFormat.excel) : null,
                icon: const Icon(Icons.table_view_outlined, size: 18),
                label: const Text(S.exportExcel),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _export(ReportFormat format) async {
    setState(() => _busy = true);
    final outcome = await runWorkshopExport(
      context,
      stats: widget.stats,
      format: format,
      sections: _sections,
      generatedAt: ref.read(clockProvider)(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    // Only close on a file that actually went somewhere — an empty result
    // leaves the sheet open with the choices that produced it.
    if (outcome == WorkshopExportOutcome.delivered) Navigator.of(context).pop();
  }
}

/// One selectable report section, drawn the way the detachment report
/// composer draws its own — the two export flows are the same idea and must
/// not look like two different apps.
class _SectionToggle extends StatelessWidget {
  const _SectionToggle({
    required this.section,
    required this.value,
    required this.onChanged,
  });

  final WorkshopReportSection section;
  final bool value;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onChanged,
      enabled: onChanged != null,
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
                Text(
                  section.title,
                  style: TextStyle(
                    color: value ? c.primary : c.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  section.subtitle,
                  style: TextStyle(color: c.ink3, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Copies "number - name" lines for the paid people in one group, ready to
/// paste into a message or a list. Only paid people are included — that is
/// what the list is for.
class WorkshopCopyNamesCard extends StatelessWidget {
  const WorkshopCopyNamesCard({super.key, required this.stats});

  final WorkshopStats stats;

  @override
  Widget build(BuildContext context) {
    return _StatsCard(
      title: S.statsCopyTitle,
      subtitle: S.statsCopySub,
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _copy(context, stats.participants),
            icon: const Icon(Icons.content_copy_rounded, size: 16),
            label: const Text(S.statsCopyParticipants),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _copy(context, stats.teamMembers),
            icon: const Icon(Icons.content_copy_rounded, size: 16),
            label: const Text(S.statsCopyTeam),
          ),
        ),
      ]),
    );
  }

  Future<void> _copy(
    BuildContext context,
    List<WorkshopStatsPerson> people,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (people.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text(S.statsCopyEmpty)));
      return;
    }
    final paid =
        people.where((p) => p.paymentStatus == PaymentStatus.paid).toList();
    if (paid.isEmpty) {
      messenger
          .showSnackBar(const SnackBar(content: Text(S.statsCopyNoPayers)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: formatPaidNames(paid)));
    messenger.showSnackBar(const SnackBar(content: Text(S.statsCopyDone)));
  }
}

/// "١ - أحمد كنعان" per line, numbered from one.
String formatPaidNames(List<WorkshopStatsPerson> people) => [
      for (var i = 0; i < people.length; i++)
        '${toArabicIndic('${i + 1}')} - ${people[i].name}',
    ].join('\n');

/// The card shell both of these share with the statistics dashboard.
class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
