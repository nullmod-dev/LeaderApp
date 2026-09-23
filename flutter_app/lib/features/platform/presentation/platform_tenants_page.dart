import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/filter_chips.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/problem/problem.dart';
import '../../../core/problem/problem_presentation.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../data/saas_tenant_providers.dart';
import '../domain/platform_area.dart';
import '../domain/saas_tenant_models.dart';
import 'platform_destinations.dart';
import 'saas_tenant_copy.dart';
import 'saas_tenant_routes.dart';
import 'widgets/platform_meta.dart';
import 'widgets/platform_page.dart';

/// `/platform/tenants` — the SaaS subscriber list.
///
/// This screen replaces the Point 4 section landing. The route, the
/// destination and the branch are unchanged, which was the point of shipping
/// the landing early: an operator who learned where the Teams area lives finds
/// the real module in the same place.
///
/// **Search and filter are repository parameters**, not a selector over a list
/// the client already holds. A subscriber list is the one collection in this
/// product with no ceiling, and the read that a backend will have to filter is
/// written that way now — see [SaasTenantQuery]. The mock answers it in
/// memory; nothing here changes when a real endpoint takes over.
///
/// **Nothing on this list mutates a subscriber.** Registration has its own
/// route and lifecycle writes live on tenant detail through the Point 9
/// controller. The list remains a read/search/filter surface.
class PlatformTenantsPage extends ConsumerStatefulWidget {
  const PlatformTenantsPage({super.key});

  static String get location => PlatformArea.tenants.route;

  @override
  ConsumerState<PlatformTenantsPage> createState() =>
      _PlatformTenantsPageState();
}

class _PlatformTenantsPageState extends ConsumerState<PlatformTenantsPage> {
  final _search = TextEditingController();

  /// The query actually sent. It trails the text field by [_debounce] so that
  /// typing a team name is one read at the end rather than one per keystroke —
  /// which matters not at all against the mock and entirely against a backend.
  SaasTenantQuery _query = const SaasTenantQuery();
  Timer? _pending;

  static const _debounce = Duration(milliseconds: 250);

  @override
  void dispose() {
    _pending?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _pending?.cancel();
    _pending = Timer(_debounce, () {
      if (!mounted) return;
      setState(() => _query = _query.copyWith(search: value).firstPage);
    });
  }

  void _onStatusChanged(SaasTenantListStatus? status) {
    _pending?.cancel();
    setState(() {
      // `firstPage`, always: a cursor belongs to the query that produced it,
      // and carrying one across a filter change is how a paged list starts
      // showing the wrong page of the wrong set.
      _query = status == null
          ? _query.copyWith(clearStatus: true).firstPage
          : _query.copyWith(status: status).firstPage;
    });
  }

  void _clearFilters() {
    _pending?.cancel();
    _search.clear();
    setState(() => _query = const SaasTenantQuery());
  }

  Future<void> _refresh() async {
    ref.invalidate(saasTenantListProvider(_query));
    await ref.read(saasTenantListProvider(_query).future);
  }

  @override
  Widget build(BuildContext context) {
    final destination = destinationFor(PlatformArea.tenants);
    final async = ref.watch(saasTenantListProvider(_query));

    return PlatformPage(
      title: destination.label,
      onRefresh: _refresh,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('platform-tenants-create'),
        onPressed: () => context.push(SaasTenantRoutes.create),
        // Flat, like every other surface in this app. The theme sets
        // `elevation: 0` and a hairline on every card, and Material's default
        // FAB shadow made this the one raised thing in the product — a hard
        // black slab under a button in dark mode (UI audit, Design System:
        // "the FAB is the only elevated surface").
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        icon: const Icon(Icons.add_rounded),
        label: const Text(S.platformTenantsCreateAction),
      ),
      children: [
        const PlatformPageIntro(lead: S.platformTenantsSubtitle),
        const SizedBox(height: AppSpacing.lg),
        _SearchField(
          controller: _search,
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _onSearchChanged('');
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'الحالة التجارية أو حالة الوصول',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.c.ink3,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _StatusFilterRow(selected: _query.status, onSelected: _onStatusChanged),
        const SizedBox(height: AppSpacing.lg),
        ..._body(async),
      ],
    );
  }

  List<Widget> _body(AsyncValue<Result<SaasTenantPage>> async) {
    // Only the very first read shows the skeleton. A refetch caused by typing
    // keeps the previous rows on screen, because replacing a list the operator
    // is reading with grey bars on every keystroke is worse than a stale row
    // for 340 ms.
    if (async.isLoading && !async.hasValue) {
      return const [_TenantListSkeleton()];
    }
    if (async.hasError || !async.hasValue) {
      return [ErrorStateView(onRetry: _refresh)];
    }

    return async.requireValue.when(
      success: (page, {stale = false}) => _rows(page, stale: stale),
      failure: (message, code) {
        final view = resolveProblem(Problem.of(
          ProblemCode.parse(code),
          rawCode: code,
          detail: message,
        ));
        return [
          ErrorStateView(
            key: const Key('platform-tenants-failure'),
            title: view.title,
            body: view.message,
            onRetry: _refresh,
          ),
        ];
      },
      offline: (cached) => cached == null
          ? [
              EmptyState(
                key: const Key('platform-tenants-offline-empty'),
                icon: Icons.cloud_off_rounded,
                title: S.offlineTitle,
                body: S.noCachedCopy,
                actionLabel: S.retry,
                onAction: _refresh,
              ),
            ]
          : _rows(cached, offline: true),
    );
  }

  List<Widget> _rows(
    SaasTenantPage page, {
    bool stale = false,
    bool offline = false,
  }) {
    // Two different zeros, and the screen must not confuse them: a platform
    // with no subscribers yet is a milestone, a search that matched nothing is
    // a mistake the operator can undo. They get different copy and only one of
    // them offers a way out.
    if (page.items.isEmpty) {
      return [
        if (offline || stale) ...[
          const _FreshnessNote(offline: true),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (_query.isFiltered)
          EmptyState(
            key: const Key('platform-tenants-no-results'),
            icon: Icons.search_off_rounded,
            title: S.platformTenantsNoResultsTitle,
            body: S.platformTenantsNoResultsBody,
            actionLabel: S.platformTenantsNoResultsAction,
            onAction: _clearFilters,
          )
        else
          const EmptyState(
            key: Key('platform-tenants-empty'),
            icon: Icons.groups_2_outlined,
            title: S.platformTenantsEmptyTitle,
            body: S.platformTenantsEmptyBody,
          ),
      ];
    }

    return [
      _CountRow(
        total: page.total,
        filtered: _query.isFiltered,
        offline: offline,
        stale: stale,
        onClear: _clearFilters,
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final tenant in page.items) ...[
        _TenantCard(tenant: tenant),
        const SizedBox(height: AppSpacing.sm),
      ],
      // Truthful rather than silent. The mock never reaches this, and a
      // backend that pages will — at which point the operator is told the list
      // is cut instead of quietly missing a customer. It is a sentence, not a
      // control: a "load more" that cannot be exercised is the dead affordance
      // this surface refuses everywhere else.
      if (page.hasMore) const _MoreResultsNote(),
    ];
  }
}

/// Rows of the shape the real ones have.
///
/// Hand-built rather than the shared `SkeletonList`, which is itself a
/// `ListView` and cannot be a child of the page's own scroll.
class _TenantListSkeleton extends StatelessWidget {
  const _TenantListSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      key: const Key('platform-tenants-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Skeleton(width: 90, height: 14),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < 4; i++) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 160, height: 16),
                SizedBox(height: AppSpacing.sm),
                SkeletonRow(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    // The hint rather than a floating label: the hint is the more useful of
    // the two strings — it names *what* can be searched — and a label would
    // occupy the field until it is focused and hide exactly that. The
    // accessible name is supplied by `Semantics` instead, so nothing is lost
    // to a screen reader.
    return Semantics(
      textField: true,
      label: S.platformTenantsSearchLabel,
      child: TextField(
        key: const Key('platform-tenants-search'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: S.platformTenantsSearchHint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    key: const Key('platform-tenants-search-clear'),
                    tooltip: S.platformTenantsClearSearch,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClear,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Every active-resource projection, plus «الكل». Deleted tombstones are
/// deliberately absent because this is the normal subscriber list rather than
/// a retained-record search surface.
///
/// Status is the only facet Point 6 offers. A plan filter, a size filter and a
/// date filter would each be defensible and together they would be the admin
/// template this surface is trying not to be — and none of them answers the
/// question an operator actually opens this screen with, which is "who needs
/// attention".
class _StatusFilterRow extends StatelessWidget {
  const _StatusFilterRow({required this.selected, required this.onSelected});

  final SaasTenantListStatus? selected;
  final ValueChanged<SaasTenantListStatus?> onSelected;

  static const visibleStatuses = [
    SaasTenantListStatus.trial,
    SaasTenantListStatus.active,
    SaasTenantListStatus.grace,
    SaasTenantListStatus.inactive,
    SaasTenantListStatus.suspended,
    SaasTenantListStatus.deletionPending,
  ];

  @override
  Widget build(BuildContext context) {
    // Wraps rather than scrolling horizontally. The scrolling row this
    // replaced clipped its sixth chip at the edge with no fade and no other
    // affordance, so «محذوفة» was unreachable at 320 dp — a second row of
    // chips costs one line and loses nothing.
    return AppFilterBar(
      semanticLabel: S.platformTenantsFilterLabel,
      children: [
        AppFilterChip(
          key: const Key('platform-tenants-filter-all'),
          label: S.platformTenantsFilterAll,
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final status in visibleStatuses)
          AppFilterChip(
            key: Key('platform-tenants-filter-${status.wire}'),
            label: tenantStatusFilterLabel(status),
            selected: selected == status,
            onSelected: (_) => onSelected(status),
          ),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.total,
    required this.filtered,
    required this.offline,
    required this.stale,
    required this.onClear,
  });

  final int total;
  final bool filtered;
  final bool offline;
  final bool stale;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        Text(
          tenantResultCount(total),
          key: const Key('platform-tenants-count'),
          style: AppTypography.eyebrow(c),
        ),
        if (offline)
          const StatusChip(kind: StatusKind.warn, label: S.offlineTitle)
        else if (stale)
          const StaleBadge(),
        if (filtered)
          TextButton(
            key: const Key('platform-tenants-clear-filters'),
            onPressed: onClear,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
            ),
            child: const Text(S.platformTenantsClearFilters),
          ),
      ],
    );
  }
}

class _FreshnessNote extends StatelessWidget {
  const _FreshnessNote({required this.offline});
  final bool offline;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: offline
            ? const StatusChip(kind: StatusKind.warn, label: S.offlineTitle)
            : const StaleBadge(),
      );
}

class _MoreResultsNote extends StatelessWidget {
  const _MoreResultsNote();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      key: const Key('platform-tenants-more-note'),
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        S.platformTenantsMoreNote,
        style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
      ),
    );
  }
}

/// One subscriber.
///
/// Three lines, and the restraint is the design. A control-plane row that
/// carried plan, seats, storage, revenue and last sign-in would be a
/// spreadsheet squeezed onto a phone; what an operator scans for is *which
/// customer* and *what state*, and the rest is one tap away.
class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant});

  final SaasTenant tenant;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final subscription = tenantSubscriptionLine(tenant);

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('platform-tenant-row-${tenant.id}'),
        onTap: () => context.push(SaasTenantRoutes.detail(tenant.id)),
        child: Semantics(
          button: true,
          label: '${tenant.displayName}، '
              '${tenantStatusLabel(tenant.listStatus)}، '
              '${S.platformTenantsOpen}',
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Wrap, not Row: at a large text scale the chip drops
                      // under the name instead of crushing it to two
                      // characters.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          Text(tenant.displayName, style: t.titleSmall),
                          StatusChip(
                            kind: tenantStatusKind(tenant.listStatus),
                            label: tenantStatusLabel(tenant.listStatus),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        tenant.mainAdmin.name,
                        style: t.bodySmall?.copyWith(color: c.ink2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // The subscription date and the Team Code are one
                      // metadata line — the code is on the row because the
                      // support question this screen answers most often
                      // arrives *as* a code.
                      PlatformMeta(parts: [
                        if (subscription != null)
                          PlatformMetaText(subscription),
                        // `TechnicalText`, not an isolated string: the code is
                        // selectable so it can be pasted into a support
                        // ticket, which is why it is on the row at all.
                        TechnicalText(
                          tenant.teamCode,
                          tabular: true,
                          style: t.bodySmall?.copyWith(color: c.ink3),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                // The row has always opened a detail page and nothing said so
                // (UI audit, Tenants list).
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
