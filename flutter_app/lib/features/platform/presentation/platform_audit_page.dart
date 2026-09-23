import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart' show toArabicIndic;
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/calendar_day.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/strings.dart';
import '../data/platform_audit_list_controller.dart';
import '../data/platform_audit_providers.dart';
import '../domain/platform_audit_models.dart';
import 'platform_audit_copy.dart';
import 'platform_audit_detail.dart';
import 'platform_audit_filters.dart';
import 'widgets/platform_meta.dart';
import 'widgets/platform_page.dart';

class PlatformAuditPageWidget extends ConsumerStatefulWidget {
  const PlatformAuditPageWidget({super.key, this.initialQuery});

  final PlatformAuditQuery? initialQuery;
  @override
  ConsumerState<PlatformAuditPageWidget> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<PlatformAuditPageWidget> {
  late final PlatformAuditListController list;
  final search = TextEditingController();
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    list =
        PlatformAuditListController(ref.read(platformAuditRepositoryProvider));
    list.addListener(update);
    final initial = widget.initialQuery;
    unawaited(initial == null ? list.refresh() : list.setQuery(initial));
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    list.removeListener(update);
    list.dispose();
    super.dispose();
  }

  PlatformAuditQuery withSearch(PlatformAuditQuery q, String text) =>
      PlatformAuditQuery(
          from: q.from,
          before: q.before,
          actorKind: q.actorKind,
          actorId: q.actorId,
          action: q.action,
          category: q.category,
          tenantId: q.tenantId,
          targetType: q.targetType,
          search: text.trim(),
          limit: q.limit);

  void searchChanged(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(list.setQuery(withSearch(list.query, value)));
    });
  }

  Future<void> filters() async {
    debounce?.cancel();
    final query = await showPlatformAuditFilters(context,
        withSearch(list.query, search.text), ref.read(clockProvider)());
    if (!mounted) return;
    // A pending search still applies if the sheet is dismissed.
    final next = query ?? withSearch(list.query, search.text);
    if (next != list.query) await list.setQuery(next);
  }

  @override
  Widget build(BuildContext context) {
    final count = auditFilterCount(list.query);
    final hasQuery = count > 0 || list.query.search.trim().isNotEmpty;
    return PlatformPage(
        title: S.platformAuditTitle,
        onRefresh: list.refresh,
        actions: [
          IconButton(
              key: const Key('audit-refresh'),
              tooltip: 'تحديث السجل',
              onPressed: list.loading ? null : list.refresh,
              icon: const Icon(Icons.refresh_rounded))
        ],
        children: [
          const PlatformPageIntro(
            lead: 'أحداث إدارة المنصة، من الأحدث إلى الأقدم.',
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
              key: const Key('audit-search'),
              controller: search,
              onChanged: searchChanged,
              decoration: const InputDecoration(
                  labelText: 'بحث في السجل',
                  hintText: 'المنفّذ أو العميل أو المورد',
                  prefixIcon: Icon(Icons.search_rounded))),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                    key: const Key('audit-filters'),
                    onPressed: filters,
                    // `Size(0, 48)`, not the theme's `Size.fromHeight(48)`,
                    // which is `Size(infinity, 48)` — that is why a one-word
                    // control used to occupy the full width of the page.
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                    ),
                    icon: const Icon(Icons.filter_list_rounded),
                    label: Text(count == 0
                        ? S.platformAuditFilters
                        : '${S.platformAuditFilters} '
                            '(${toArabicIndic('$count')})')),
                if (count > 0 || search.text.isNotEmpty)
                  TextButton(
                      key: const Key('audit-clear'),
                      onPressed: () {
                        debounce?.cancel();
                        search.clear();
                        unawaited(list.setQuery(PlatformAuditQuery(limit: 8)));
                      },
                      child: const Text('مسح الكل')),
              ]),
          const SizedBox(height: AppSpacing.lg),
          if (list.offline)
            const Padding(
                key: Key('audit-offline'),
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Text('أنت غير متصل. قد لا يعكس السجل آخر الأحداث.')),
          if (list.stale)
            const Padding(
                key: Key('audit-stale'),
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Text('تُعرض نسخة محفوظة من السجل.')),
          if (list.loading && list.items.isEmpty)
            const Column(key: Key('audit-loading'), children: [
              Skeleton(height: 64),
              SizedBox(height: AppSpacing.md),
              Skeleton(height: 64)
            ])
          else ...[
            if (list.loading)
              const LinearProgressIndicator(key: Key('audit-refreshing')),
            if (list.failed || list.cursorFailed)
              Column(
                  key: const Key('audit-failure'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(list.cursorFailed
                        ? 'تعذّر متابعة الصفحات. حدّث السجل للبدء من جديد.'
                        : 'تعذّر تحميل السجل. حاول مرة أخرى.'),
                    TextButton(
                        key: const Key('audit-retry'),
                        onPressed: list.cursorFailed || list.nextCursor == null
                            ? list.refresh
                            : list.loadMore,
                        child: Text(list.cursorFailed
                            ? 'تحديث السجل'
                            : 'إعادة المحاولة')),
                  ]),
            if (list.items.isEmpty && !list.failed && !list.cursorFailed)
              EmptyState(
                  key: const Key('audit-empty'),
                  icon: Icons.history_rounded,
                  title: list.offline
                      ? 'السجل غير متاح دون اتصال'
                      : hasQuery
                          ? 'لا توجد نتائج مطابقة'
                          : 'لا توجد أحداث',
                  body: hasQuery
                      ? 'جرّب تعديل البحث أو عوامل التصفية.'
                      : 'ستظهر أحداث إدارة المنصة هنا.',
                  actionLabel: list.offline ? 'إعادة المحاولة' : null,
                  onAction: list.offline ? list.refresh : null),
            // Grouped by the day the event happened, newest day first. The
            // log used to repeat a full date on every row, so «١٠ أيلول
            // ٢٠٢٦» appeared five times in one screen and the eye had to
            // read it each time to find out it had not changed (UI audit P2).
            for (final day in _groupByDay(list.items, ref.read(clockProvider)()))
              ...[
              SectionHeader(title: day.label),
              for (final event in day.events) ...[
                _AuditEventTile(
                  key: Key('audit-row-${event.id}'),
                  event: event,
                  onTap: () => showPlatformAuditDetail(context, event),
                ),
                const Divider(height: 1),
              ],
            ],
            if (list.nextCursor != null && !list.cursorFailed)
              Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: OutlinedButton(
                      key: const Key('audit-load-more'),
                      onPressed:
                          list.paging || list.loading ? null : list.loadMore,
                      child: Text(list.paging
                          ? 'جارٍ تحميل المزيد…'
                          : 'تحميل المزيد'))),
          ],
        ]);
  }
}

/// One day's worth of events, and the label above them.
class _AuditDay {
  const _AuditDay(this.label, this.events);

  final String label;
  final List<PlatformAuditEvent> events;
}

/// Groups the loaded page by the local calendar day each event happened on.
///
/// Local, not UTC: an operator reads the log against their own day. The two
/// most recent days are named rather than dated, because «اليوم» is the answer
/// to "has anything happened since I last looked".
List<_AuditDay> _groupByDay(List<PlatformAuditEvent> events, DateTime now) {
  final today = dateOnly(now.toLocal());
  final out = <_AuditDay>[];
  DateTime? current;
  for (final event in events) {
    final day = dateOnly(event.occurredAt.toLocal());
    if (current == null || day != current) {
      current = day;
      final delta = calendarDaysBetween(today, day);
      out.add(_AuditDay(
        switch (delta) {
          0 => S.platformAuditToday,
          -1 => S.platformAuditYesterday,
          _ => AppDate.dayMonthYear(day),
        },
        <PlatformAuditEvent>[],
      ));
    }
    out.last.events.add(event);
  }
  return out;
}

/// One event.
///
/// **Three weights** (§28): what happened, who did it and to whom, and the
/// technical metadata. The row used to be four flat lines of `bodySmall` in
/// which the actor, the full date, the time, the category and the customer
/// were all the same size and joined by ` · ` — a separator that renders
/// identically to the Arabic-Indic zero standing next to it (P1-11).
///
/// It also gained a chevron, because tapping it has always opened a detail
/// sheet and nothing on the row said so.
class _AuditEventTile extends StatelessWidget {
  const _AuditEventTile({
    super.key,
    required this.event,
    required this.onTap,
  });

  final PlatformAuditEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final textTheme = Theme.of(context).textTheme;
    final tenant = event.tenant;
    final localTime = event.occurredAt.toLocal();
    final contextLabel = tenant == null
        ? S.platformAuditPlatformScope
        : tenant.displayName;
    final semanticLabel = [
      AuditCopy.action(event.action),
      'المنفّذ ${AuditCopy.actor(event.actor)}',
      AuditCopy.category(event.category),
      contextLabel,
      if (tenant != null && tenant.isDeleted) S.platformAuditDeletedTenant,
      AppDate.time(localTime),
      S.platformAuditOpenEvent,
    ].join('، ');

    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AuditCopy.action(event.action),
                        style: textTheme.titleSmall?.copyWith(color: c.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // Who, and to whom. The day is the group heading, so the
                      // row carries only the clock.
                      PlatformMeta(parts: [
                        PlatformMetaText(AuditCopy.actor(event.actor)),
                        PlatformMetaText(contextLabel),
                        PlatformMetaText(
                          PlatformTime.time(event.occurredAt),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      PlatformMeta(parts: [
                        PlatformMetaText(AuditCopy.category(event.category)),
                        if (tenant != null && tenant.isDeleted)
                          PlatformMetaText(
                            S.platformAuditDeletedTenant,
                            color: c.ink3,
                          ),
                      ]),
                      if (event.changes.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _AuditChangeSummary(change: event.changes.first),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: ForwardChevron(size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditChangeSummary extends StatelessWidget {
  const _AuditChangeSummary({required this.change});

  final PlatformAuditChange change;

  @override
  Widget build(BuildContext context) {
    final before = AuditCopy.value(change.field, change.before);
    final after = AuditCopy.value(change.field, change.after);
    // Words, not an arrow. «10 ← 20» put a pair of Latin digits either side of
    // a directional glyph inside an Arabic paragraph, which is bidi-ambiguous
    // about which of the two is the old value — the exact thing an audit line
    // may not be ambiguous about. Each value is isolated so a numeric run
    // keeps its own order.
    final body = S.platformAuditChangeFromTo
        .replaceFirst('%before%', '\u2066$before\u2069')
        .replaceFirst('%after%', '\u2066$after\u2069');
    return Semantics(
      label: '${AuditCopy.changeField(change.field)}، من $before إلى $after',
      child: ExcludeSemantics(
        child: Text(
          '${AuditCopy.changeField(change.field)}: $body',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.c.ink2),
        ),
      ),
    );
  }
}
