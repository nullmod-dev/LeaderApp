import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/sync/outbox_controller.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/reading_column.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/strings.dart';
import '../../announcement/presentation/announcements_page.dart';
import '../../announcement/presentation/widgets/home_announcement_card.dart';
import '../../conflict/presentation/needs_review_page.dart';
import '../../detachment/domain/detachment_models.dart';
import '../../detachment/domain/storage_status.dart';
import '../../shell/main_shell.dart';
import '../../shift/domain/shift_models.dart';
import '../../shift/domain/shift_selectors.dart';
import '../../notification/presentation/widgets/notification_bell.dart';
import '../../search/presentation/widgets/global_search_action.dart';
import '../../shift/presentation/shift_manage_sheet.dart';
import '../data/home_providers.dart';
import '../domain/home_models.dart';
import '../domain/today_selectors.dart';
import 'widgets/dashboard_cards.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';

/// The Today dashboard — the app's operational landing screen.
///
/// It answers one question on open: *what is happening today, and what needs a
/// decision.* Everything on it is a projection of a record that exists
/// somewhere else in the app, and every card leads to the existing surface
/// that owns it — the schedule, the store, the roster, the review inbox. It
/// owns no business logic of its own: what is running now, what is next, how
/// attendance stands, and which alerts exist are all decided by the pure
/// functions in `today_selectors.dart`.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text(S.navHome),
        // The app's one way into Global Search and into the Notifications
        // Center. The alert rows below still open the surface that fixes each
        // condition directly — the bell is for what has not been looked at,
        // and for what is no longer today's.
        actions: const [GlobalSearchAction(), NotificationBellAction()],
      ),
      body: AsyncResultView<Detachment?>(
        value: ref.watch(activeDetachmentProvider),
        onRetry: () => ref.invalidate(dashboardDetachmentsProvider),
        loading: const _DashboardSkeleton(),
        builder: (context, detachment, stale) => detachment == null
            // Not an error: a session with no active detachment is a real
            // state, and it says what would fix it.
            ? const FloatingNavPadding(
                child: EmptyState(
                  key: Key('dashboard-no-detachment'),
                  icon: Icons.flag_outlined,
                  title: S.dashboardNoDetachmentTitle,
                  body: S.dashboardNoDetachmentBody,
                ),
              )
            : _Dashboard(detachment: detachment),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.detachment});

  final Detachment detachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = detachment.id;
    return AppRefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardDetachmentsProvider);
        await ref.read(homeSummaryProvider(id).future);
      },
      child: AsyncResultView<HomeSummary>(
        value: ref.watch(homeSummaryProvider(id)),
        onRetry: () => ref.invalidate(homeSummaryProvider(id)),
        loading: const _DashboardSkeleton(),
        builder: (context, summary, stale) =>
            _DashboardBody(summary: summary, stale: stale),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.summary, required this.stale});

  final HomeSummary summary;
  final bool stale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = summary.detachmentId;
    // Read through the clock provider rather than calling `DateTime.now()`
    // here: what is running, what is next and which alerts are raised are all
    // decided from this one instant, so a test has to be able to pin it. The
    // provider's default is `DateTime.now` — production reads the wall clock
    // exactly as before.
    final now = ref.watch(clockProvider)();
    final caps = ref.capabilities;
    // No `AdminView` read here any more. Breadth used to decide whether the
    // organisation block and its two shortcuts were offered; the block is now
    // one fact on the context line and the two shortcuts are gone, so every
    // remaining thing on this screen is gated on the capability that makes it
    // actionable — which is the stronger check of the two.
    final inventoryEnabled = ref.watch(
      tenantFeatureAvailableProvider(TenantFeatureKey.inventory),
    );
    final statisticsEnabled = ref.watch(
      tenantFeatureAvailableProvider(TenantFeatureKey.statisticsReports),
    );
    final announcementsEnabled = ref.watch(
      tenantFeatureAvailableProvider(TenantFeatureKey.announcements),
    );

    final current = currentShiftOf(summary.shifts, now);
    final next = nextShiftOf(summary.shifts, now);
    final today = shiftsOnDay(summary.shifts, now);
    final attendance = attendanceOf(current);

    // Client-side facts the summary cannot carry: the user's own queued
    // writes. Read from the same providers the Settings sync screen reads,
    // so the two can never disagree.
    final syncStatus = ref.watch(syncCoordinatorProvider);
    final pending = ref.watch(pendingOperationsCountProvider);
    final needingReview = ref.watch(conflictOperationsCountProvider);

    final allAlerts = buildDashboardAlerts(
      summary: summary,
      now: now,
      capabilities: caps,
      pendingOperations: pending,
      operationsNeedingReview: needingReview,
      lastSyncFailed: syncStatus.lastOutcome == SyncRunOutcome.failed ||
          syncStatus.lastOutcome == SyncRunOutcome.partial,
    );
    final alerts = [
      for (final alert in allAlerts)
        if (inventoryEnabled ||
            (alert.kind != DashboardAlertKind.lowStock &&
                alert.kind != DashboardAlertKind.expiringStock))
          alert,
    ];

    final canOpenShift = caps.canAnyIn(id, const {
      Cap.shiftManage,
      Cap.shiftAssign,
      Cap.shiftDelete,
      Cap.shiftAttendanceRecord,
      Cap.shiftAttendanceOverride,
    });

    void openShift(Shift shift) => showShiftManageSheet(
          context: context,
          ref: ref,
          shift: shift,
          detachmentId: id,
          canAssign: caps.canIn(id, Cap.shiftAssign),
          canRecord: caps.canIn(id, Cap.shiftAttendanceRecord),
          canOverride: caps.canIn(id, Cap.shiftAttendanceOverride),
          canManage: caps.canIn(id, Cap.shiftManage),
          canDelete: caps.canIn(id, Cap.shiftDelete),
        );

    void openTab(String tab) => context.go('/detachment/$id/$tab');

    // Whether the store's verdict is this session's to read at all. A
    // detachment where inventory is switched off, or a session without the
    // keys, gets the glance line without a stock fact rather than a fact that
    // says «لا مخزن» because it was not allowed to look.
    final canSeeStock = inventoryEnabled &&
        caps.canAnyIn(id, const {Cap.inventoryAdjust, Cap.inventoryItemManage});

    // The heading over the attention list, and whether the day counts as
    // quiet, are the same question asked once: is anything raised that
    // genuinely asks for a decision? Queued work that the next sync run will
    // clear is information, and calling it «يحتاج قرارك» every time the
    // device goes offline is how a screen teaches people to ignore it.
    final decisions =
        alerts.where((a) => severityOf(a.kind).needsDecision).length;

    return FloatingNavPadding(
      // Class B of the measure policy (`core/widgets/reading_column.dart`):
      // an operational landing is a working column, not a prose column and
      // not a full-bleed grid. Uncapped, the audit's 900 dp render put an
      // alert's title at one edge of the window and its action at the other.
      child: ReadingColumn(
        maxWidth: kContentMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (stale)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StaleBadge(),
                ),
              ),
            // The announcement promotion, at the top of the dashboard's
            // content for exactly one hour after publication. It renders
            // nothing at all when there is nothing promoted — no placeholder,
            // no reserved space — so the moment the hour is up this list is
            // byte-for-byte the list it was before, with the context header
            // back at the top. Deliberately not wrapped in a `Stagger`: a
            // notice at the top of Home is the first thing to read, not the
            // first thing to animate.
            if (announcementsEnabled) HomeAnnouncementCard(detachmentId: id),
            _ContextHeader(summary: summary, now: now),

            // ATTENTION — first, and only when there is something to raise.
            // An empty section here was the audit's «لا شيء يحتاج قرارك
            // الآن» card sitting above two more cards that also said nothing
            // was happening: three surfaces for one absence. When nothing is
            // raised this block is not drawn at all and the calm state lives
            // inside the day's card, said once.
            if (alerts.isNotEmpty) ...[
              SectionHeader(
                title: decisions > 0
                    ? S.needsYourDecision
                    : S.dashboardForInfo,
              ),
              Stagger(
                index: 0,
                child: _Alerts(
                  alerts: alerts,
                  summary: summary,
                  canOpenShift: canOpenShift,
                  onOpenShift: openShift,
                  onOpenTab: openTab,
                ),
              ),
            ],

            // TODAY — what is running, and what is next, in one card.
            const SectionHeader(title: S.dashboardTodaySection),
            Stagger(
              index: 1,
              child: TodayCard(
                current: current,
                attendance: attendance,
                next: next,
                now: now,
                shiftsToday: today.length,
                quiet: alerts.isEmpty,
                onOpenCurrent: current != null && canOpenShift
                    ? () => openShift(current)
                    : null,
                onOpenNext:
                    next != null && canOpenShift ? () => openShift(next) : null,
                onViewSchedule: () => openTab('shifts'),
              ),
            ),

            // The standing facts, on one line rather than in a tile grid.
            const SectionHeader(title: S.dashboardGlanceSection),
            DashboardGlance(
              rosterCount: summary.rosterCount,
              shiftsToday: today.length,
              storageLabel: canSeeStock ? storageLabel(summary.storageStatus) : null,
              storageKind: storageKind(summary.storageStatus),
            ),

            // Shortcuts into *this detachment*. The organisation-level pair
            // that used to sit here — «المفرزات» and «المؤسسة» — opened a
            // permanent navigation branch and a screen two taps inside
            // another one, so they saved nothing and cost a row (audit §9).
            const SectionHeader(title: S.dashboardShortcutsSection),
            _Shortcuts(
              detachmentId: id,
              inventoryEnabled: inventoryEnabled,
              statisticsEnabled: statisticsEnabled,
              announcementsEnabled: announcementsEnabled,
              onOpenTab: openTab,
            ),
          ],
        ),
      ),
    );
  }
}

/// The store's verdict as a word and a status kind, resolved the same way the
/// detachment detail shell's strip resolves it so the two cannot disagree.
String storageLabel(StorageStatus status) => switch (status) {
      StorageStatus.healthy => S.storageStatusHealthy,
      StorageStatus.expiring => S.storageStatusExpiring,
      StorageStatus.low => S.storageStatusLow,
      StorageStatus.depleted => S.storageStatusDepleted,
      StorageStatus.empty => S.storageStatusEmpty,
    };

StatusKind storageKind(StorageStatus status) => switch (status) {
      StorageStatus.healthy => StatusKind.ok,
      StorageStatus.expiring => StatusKind.warn,
      StorageStatus.low => StatusKind.warn,
      StorageStatus.depleted => StatusKind.crit,
      StorageStatus.empty => StatusKind.muted,
    };

/// The detachment/day line, and the switcher when there is more than one
/// detachment to switch to.
class _ContextHeader extends ConsumerWidget {
  const _ContextHeader({required this.summary, required this.now});

  final HomeSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(dashboardDetachmentsProvider).valueOrNull?.when(
              success: (data, {stale = false}) => data,
              failure: (_, __) => const <Detachment>[],
              offline: (cached) => cached ?? const <Detachment>[],
            ) ??
        const <Detachment>[];

    return DashboardContextHeader(
      detachmentName: summary.detachmentName,
      region: summary.region,
      now: now,
      detachmentCount: available.isEmpty ? 1 : available.length,
      onSwitch: available.length < 2
          ? null
          : () =>
              _pickDetachment(context, ref, available, summary.detachmentId),
    );
  }

  Future<void> _pickDetachment(
    BuildContext context,
    WidgetRef ref,
    List<Detachment> available,
    String currentId,
  ) async {
    final chosen = await showAppSheet<String>(
      context: context,
      title: S.dashboardPickDetachment,
      // A Builder so the rows pop the *sheet*: the closure would otherwise
      // capture this method's own context, which belongs to the page under
      // it — tapping a row would then pop the dashboard.
      child: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final detachment in available)
              // The sheet paints its own ground, so each row carries a
              // transparent Material for its ink to land on.
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: Key('dashboard-detachment-${detachment.id}'),
                  onTap: () => Navigator.of(sheetContext).pop(detachment.id),
                  leading: Icon(
                    detachment.id == currentId
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: detachment.id == currentId
                        ? sheetContext.c.primary
                        : sheetContext.c.ink3,
                  ),
                  title: Text(detachment.name),
                  subtitle: Text(detachment.region),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    ref.read(activeDetachmentSelectionProvider.notifier).select(chosen);
  }
}

class _Alerts extends ConsumerWidget {
  const _Alerts({
    required this.alerts,
    required this.summary,
    required this.canOpenShift,
    required this.onOpenShift,
    required this.onOpenTab,
  });

  final List<DashboardAlert> alerts;
  final HomeSummary summary;
  final bool canOpenShift;
  final void Function(Shift shift) onOpenShift;
  final void Function(String tab) onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    // Never drawn empty. The page decides whether this section exists at all;
    // an "all clear" card here is the third surface for one absence that the
    // audit counted, and the calm state belongs in the day's card where the
    // day is reported.
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const Key('dashboard-alerts'),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (int i = 0; i < alerts.length; i++)
          DashboardAlertRow(
            // Two shifts can raise the same kind on one day, so the key
            // carries the record it points at — sibling rows must not share
            // one.
            key: Key('dashboard-alert-${alerts[i].kind.name}'
                '${alerts[i].shiftId == null ? '' : '-${alerts[i].shiftId}'}'),
            alert: alerts[i],
            title: alertTitle(alerts[i]),
            body: alertBody(alerts[i]),
            isLast: i == alerts.length - 1,
            onOpen: _openerFor(context, alerts[i]),
          ),
      ]),
    );
  }

  /// Where an alert leads. Every destination is an existing route or sheet —
  /// the dashboard opens no surface of its own, and an alert with nowhere
  /// meaningful to go gets no action rather than a dead button.
  VoidCallback? _openerFor(BuildContext context, DashboardAlert alert) {
    switch (alert.kind) {
      case DashboardAlertKind.needsReview:
        // Explicit human action, which is the only condition under which the
        // review surfaces may be opened at all.
        return () => context.push(NeedsReviewPage.routePath);
      case DashboardAlertKind.failedSync:
      case DashboardAlertKind.pendingSync:
        return () => context.go('/more/sync');
      case DashboardAlertKind.understaffedShift:
      case DashboardAlertKind.missingAttendance:
        final shift = _shiftById(alert.shiftId);
        if (shift == null) return () => onOpenTab('shifts');
        return canOpenShift
            ? () => onOpenShift(shift)
            : () => onOpenTab('shifts');
      case DashboardAlertKind.lowStock:
      case DashboardAlertKind.expiringStock:
        return () => onOpenTab('storage');
    }
  }

  Shift? _shiftById(String? id) {
    if (id == null) return null;
    for (final shift in summary.shifts) {
      if (shift.id == id) return shift;
    }
    return null;
  }
}

/// The copy for one raised condition.
///
/// It lives on the page rather than in `DashboardAlertRow` for the same
/// reason `DashboardAlert` carries none: the value stays pure and a test can
/// assert on the kind without matching translated Arabic, while the widget
/// stays a layout with no `switch` over domain vocabulary inside it.
String alertTitle(DashboardAlert alert) => switch (alert.kind) {
      DashboardAlertKind.needsReview => alert.count == 1
          ? S.syncReviewOne
          : S.syncReviewMany
              .replaceFirst('%d', toArabicIndic('${alert.count}')),
      DashboardAlertKind.failedSync => S.alertSyncFailedTitle,
      DashboardAlertKind.understaffedShift => S.alertUnderstaffedTitle,
      DashboardAlertKind.missingAttendance => S.alertMissingAttendanceTitle,
      DashboardAlertKind.lowStock => S.alertLowStockTitle,
      DashboardAlertKind.expiringStock => S.alertExpiringTitle,
      DashboardAlertKind.pendingSync => alert.count == 1
          ? S.syncPendingOne
          : S.syncPendingMany
              .replaceFirst('%d', toArabicIndic('${alert.count}')),
    };

String alertBody(DashboardAlert alert) => switch (alert.kind) {
      DashboardAlertKind.needsReview => S.syncReviewOpenHint,
      DashboardAlertKind.failedSync => S.syncFailedNote,
      DashboardAlertKind.understaffedShift => alert.count == 1
          ? S.alertUnderstaffedBodyOne
          : S.alertUnderstaffedBody
              .replaceFirst('%d', toArabicIndic('${alert.count}')),
      DashboardAlertKind.missingAttendance => alert.count == 1
          ? S.alertMissingAttendanceBodyOne
          : S.alertMissingAttendanceBody
              .replaceFirst('%d', toArabicIndic('${alert.count}')),
      DashboardAlertKind.lowStock => alert.count == 1
          ? S.alertLowStockBodyOne
          : S.alertLowStockBody
              .replaceFirst('%d', toArabicIndic('${alert.count}')),
      DashboardAlertKind.expiringStock => alert.count == 1
          ? S.alertExpiringBodyOne
          : S.alertExpiringBody
              .replaceFirst('%d', toArabicIndic('${alert.count}')),
      DashboardAlertKind.pendingSync => S.syncOfflineNote,
    };

/// Shortcuts into the detachment this screen is about.
///
/// **What a shortcut is for.** It saves a real step. From Home, a detachment
/// tab is three taps away — the Detachments branch, the detachment, the tab —
/// and these make it one. What they are *not* is a second bottom navigation
/// bar: «المفرزات» opened the branch that is permanently on screen, and
/// «المؤسسة» opened a settings page two taps inside another permanent branch.
/// Both were removed; neither saved a step, and together they turned a row of
/// shortcuts into a ragged seven-chip wrap that reflowed every time a
/// capability changed (audit §9).
///
/// A tile the session's grants do not cover is not rendered at all, so the
/// grid never offers a dead destination.
class _Shortcuts extends ConsumerWidget {
  const _Shortcuts({
    required this.detachmentId,
    required this.inventoryEnabled,
    required this.statisticsEnabled,
    required this.announcementsEnabled,
    required this.onOpenTab,
  });

  final String detachmentId;
  final bool inventoryEnabled;
  final bool statisticsEnabled;
  final bool announcementsEnabled;
  final void Function(String tab) onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.capabilities;
    return DashboardShortcutGrid(tiles: [
      DashboardShortcut(
        key: const Key('dashboard-action-shifts'),
        icon: Icons.calendar_month_rounded,
        label: S.detachmentShifts,
        onTap: () => onOpenTab('shifts'),
      ),
      if (caps.canIn(detachmentId, Cap.memberView))
        DashboardShortcut(
          key: const Key('dashboard-action-members'),
          icon: Icons.group_rounded,
          label: S.memberCount,
          onTap: () => onOpenTab('team'),
        ),
      if (inventoryEnabled)
        DashboardShortcut(
          key: const Key('dashboard-action-storage'),
          icon: Icons.inventory_2_rounded,
          label: S.detachmentStorage,
          onTap: () => onOpenTab('storage'),
        ),
      if (statisticsEnabled && caps.canIn(detachmentId, Cap.statsView))
        DashboardShortcut(
          key: const Key('dashboard-action-stats'),
          icon: Icons.insights_rounded,
          label: S.detachmentStats,
          onTap: () => onOpenTab('stats'),
        ),
      // Announcements. Gated on the publish key held *anywhere*, not in this
      // detachment: the screen behind it spans every detachment the session
      // may address, so a scoped administrator granted the key in one of them
      // still has somewhere to go. It stays because nothing in the permanent
      // navigation opens it.
      if (announcementsEnabled && caps.canAnywhere(Cap.announcementPublish))
        DashboardShortcut(
          key: const Key('dashboard-action-announcements'),
          icon: Icons.campaign_outlined,
          label: S.announcementsTitle,
          onTap: () => context.push(AnnouncementsPage.routePath),
        ),
    ]);
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return FloatingNavPadding(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          Skeleton(width: 160, height: 14),
          SizedBox(height: AppSpacing.lg),
          Skeleton(height: 180, radius: AppRadii.xl),
          SizedBox(height: AppSpacing.md),
          Skeleton(height: 72, radius: AppRadii.lg),
          SizedBox(height: AppSpacing.xl),
          SkeletonRow(),
          SizedBox(height: AppSpacing.md),
          SkeletonRow(),
        ],
      ),
    );
  }
}
