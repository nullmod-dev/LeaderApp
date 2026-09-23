import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/admin_experience.dart';
import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/filter_chips.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/result/result.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/strings.dart';
import '../../detachment/data/detachment_providers.dart';
import '../../detachment/presentation/tabs/detachment_storage_tab.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../notification/domain/notification_selectors.dart';
import '../../shift/data/shift_providers.dart';
import '../../shift/presentation/shift_manage_sheet.dart';
import '../../team/data/team_providers.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';
import '../data/search_providers.dart';
import '../domain/search_models.dart';
import '../domain/search_query.dart';
import 'search_copy.dart';

/// Global Search — the app's one place to find an operational record by name.
///
/// ## What it is, and what it is not
///
/// It is data search over four categories: members, detachments, shifts and
/// stock items. It is **not** a command palette. There is no query syntax, no
/// boolean operator, no filter sheet and no action launcher: a person types a
/// name and taps the record. Every row opens a surface that already exists —
/// the member's attendance page, the detachment shell, the shift management
/// sheet, the stock item sheet — because a second copy of a detail screen is
/// a second place for it to go wrong.
///
/// ## Why it cannot leak
///
/// Three layers, and the first one is where the work is done:
///
/// 1. **Nothing unauthorised is loaded.** The corpus is built from
///    scope-narrowed sources, per detachment, through
///    `AdminView.categoriesIn` — see `search_providers.dart`. There is no
///    fetch-everything-then-hide step.
/// 2. **Nothing unauthorised is matched.** `runSearch` drops any result whose
///    category is not in the index's allowed set, so a grant that narrows
///    while the screen is open takes the rows with it on the next build.
/// 3. **Nothing unauthorised opens.** A tap re-resolves the capability
///    through `Capabilities.canIn` and re-reads the record from its own
///    repository before navigating, so neither a revoked grant nor a record
///    deleted since the index was built can be acted on.
class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key});

  /// A root route, beside the Notifications Center and the Needs Review inbox
  /// and for the same reason: a full surface the user opens deliberately, so
  /// it covers the bottom nav.
  ///
  /// Deliberately unguarded. A session with nothing to search lands on a
  /// designed restricted state rather than being bounced to `/home` — and
  /// every destination it could offer carries its own guard anyway.
  static const routePath = '/search';

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  final _query = TextEditingController();

  /// The chosen category chip, or null for all of them. Held as the enum and
  /// re-validated on every build: a grant that narrows must not leave the list
  /// filtered to a category the session no longer holds.
  AdminDataCategory? _selected;

  /// One result at a time. Opening re-reads the record, and without this a
  /// second tap during that round trip opens two sheets.
  bool _opening = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _reload() => ref.invalidate(searchIndexProvider);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final allowed = ref.watch(searchableCategoriesProvider);
    // Watched unconditionally, not only once the query is long enough: the
    // corpus starts loading the moment the screen opens, so by the time the
    // second character is typed there is usually nothing left to wait for.
    final index = ref.watch(searchIndexProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.globalSearchTitle)),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _Field(
                controller: _query,
                enabled: allowed.isNotEmpty,
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (allowed.length > 1)
              _CategoryFilters(
                categories: allowed,
                selected: _selected,
                onSelect: (value) => setState(() => _selected = value),
              ),
            Expanded(child: _body(allowed, index)),
          ],
        ),
      ),
    );
  }

  Widget _body(
    List<AdminDataCategory> allowed,
    AsyncValue<SearchIndex> index,
  ) {
    // A very restricted account: not an error and not an empty result, but a
    // state of its own that says why there is nothing here.
    if (allowed.isEmpty) {
      return const EmptyState(
        key: Key('search-restricted'),
        icon: Icons.lock_outline_rounded,
        title: S.globalSearchRestrictedTitle,
        body: S.globalSearchRestrictedBody,
      );
    }

    final needle = searchNeedle(_query.text);
    if (needle.isEmpty) {
      return EmptyState(
        key: const Key('search-prompt'),
        icon: Icons.search_rounded,
        title: S.globalSearchPromptTitle,
        body: searchPromptBody(allowed),
      );
    }
    if (needle.length < minSearchQueryLength) {
      return const EmptyState(
        key: Key('search-short-query'),
        icon: Icons.keyboard_alt_outlined,
        title: S.globalSearchShortTitle,
        body: S.globalSearchShortBody,
      );
    }

    return index.when(
      loading: () => const SkeletonList(),
      error: (_, __) => ErrorStateView(onRetry: _reload),
      data: (data) => _results(data),
    );
  }

  Widget _results(SearchIndex index) {
    // The chip is presentation state, the index is authority. A category that
    // has stopped being permitted stops filtering by it rather than showing an
    // empty list the user cannot explain.
    final selected = _selected != null && index.allowed.contains(_selected)
        ? _selected
        : null;

    final groups = runSearch(index, _query.text, only: selected);
    final total = totalResults(groups);

    // Only the sources that failed, and only while their category is in view.
    final degraded = [
      for (final category in searchCategoryOrder)
        if (index.degraded.contains(category) &&
            index.allowed.contains(category) &&
            (selected == null || selected == category))
          category,
    ];

    if (groups.isEmpty) {
      // Nothing loaded at all is not "no match" — saying so would blame the
      // query for a failure that was not its fault.
      if (index.isFullyDegraded) {
        return index.offline
            ? EmptyState(
                key: const Key('search-offline'),
                icon: Icons.cloud_off_rounded,
                title: S.offlineTitle,
                body: S.globalSearchOfflineBody,
                actionLabel: S.retry,
                onAction: _reload,
              )
            : ErrorStateView(onRetry: _reload);
      }
      return Column(
        children: [
          if (degraded.isNotEmpty) _DegradedNotice(categories: degraded),
          const Expanded(
            child: EmptyState(
              key: Key('search-no-results'),
              icon: Icons.search_off_rounded,
              title: S.globalSearchNoResultsTitle,
              body: S.globalSearchNoResultsBody,
            ),
          ),
        ],
      );
    }

    // One flat, lazily built list: headings, rows and the "and N more" tails
    // interleaved, so a long group does not force every other group's rows to
    // be built on the first frame.
    final entries = <Object>[
      for (final group in groups) ...[
        group,
        for (var i = 0; i < group.results.length; i++)
          _Row(
            result: group.results[i],
            isFirst: i == 0,
            isLast: i == group.results.length - 1,
          ),
        if (group.hidden > 0) _More(group.hidden),
      ],
    ];

    return Column(
      children: [
        if (degraded.isNotEmpty) _DegradedNotice(categories: degraded),
        _Summary(total: total, stale: index.offline),
        Expanded(
          child: ListView.builder(
            key: const Key('search-results'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) => Stagger(
              index: i,
              child: _entry(entries[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _entry(Object entry) {
    if (entry is SearchGroup) {
      return SectionHeader(
        key: Key('search-group-${entry.category.name}'),
        title: searchCategoryLabel(entry.category),
      );
    }
    if (entry is _More) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          searchHiddenLabel(entry.hidden),
          style: TextStyle(color: context.c.ink3, fontSize: 12),
        ),
      );
    }
    final row = entry as _Row;
    return _ResultCard(
      isFirst: row.isFirst,
      isLast: row.isLast,
      child: SearchResultRow(
        // Keyed by the record, never by position: the list re-ranks on every
        // keystroke and a positional key would carry one row's state onto
        // another.
        key: Key('search-result-${row.result.id}'),
        result: row.result,
        onTap: () => _open(row.result),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Opening a result
  // ---------------------------------------------------------------------

  /// Opens a result, after checking that it may still be opened.
  ///
  /// Two things can have changed since the row was listed: the grant may have
  /// narrowed, and the record may be gone. Both are checked here rather than
  /// left to the destination, so the user gets a sentence instead of a bounced
  /// route or an empty sheet.
  Future<void> _open(SearchResult result) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final caps = ref.read(capabilitiesProvider);
      if (!destinationAllowed(result.destination, caps)) {
        _gone();
        return;
      }
      // The stock sheet is a modal, not a route, so the router's module
      // guard never sees it. Re-ask the module the way the grant was just
      // re-asked: an item listed before Inventory was switched off must not
      // still open (Point 16).
      if (result.destination is InventoryDestination &&
          !ref.read(
              tenantFeatureAvailableProvider(TenantFeatureKey.inventory))) {
        _gone();
        return;
      }
      switch (result.destination) {
        case MemberDestination(:final detachmentId, :final memberId):
          await _openMember(detachmentId, memberId);
        case DetachmentDestination(:final detachmentId):
          await _openDetachment(detachmentId, caps);
        case ShiftDestination(:final detachmentId, :final shiftId):
          await _openShift(detachmentId, shiftId, caps);
        case InventoryDestination(:final detachmentId, :final itemId):
          await _openItem(detachmentId, itemId, caps);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// The record is gone, or no longer this session's to open. Says so once and
  /// rebuilds the corpus, so the row that led nowhere leaves the list.
  void _gone() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(S.globalSearchResultGone)),
    );
    _reload();
  }

  Future<void> _openMember(String detachmentId, String memberId) async {
    final member =
        _valueOf(await ref.read(teamRepositoryProvider).byId(memberId));
    if (!mounted) return;
    if (member == null) {
      _gone();
      return;
    }
    // The existing member attendance page — the same route the roster opens.
    context.push('/detachment/$detachmentId/member/$memberId/status');
  }

  Future<void> _openDetachment(String detachmentId, Capabilities caps) async {
    final detachment = _valueOf(
        await ref.read(detachmentRepositoryProvider).byId(detachmentId));
    if (!mounted) return;
    if (detachment == null) {
      _gone();
      return;
    }
    // The existing detail shell, on the tab this session may actually open.
    context.push(
        '/detachment/$detachmentId/${detachmentTabFor(caps, detachmentId)}');
  }

  Future<void> _openShift(
    String detachmentId,
    String shiftId,
    Capabilities caps,
  ) async {
    final shift =
        _valueOf(await ref.read(shiftRepositoryProvider).byId(shiftId));
    if (!mounted) return;
    if (shift == null) {
      _gone();
      return;
    }
    // A session that may see the schedule but not staff or mark it gets the
    // schedule tab rather than a sheet whose every control is disabled — the
    // same degradation, resolved off the same key set, the Notifications
    // Centre makes.
    if (!caps.canAnyIn(detachmentId, shiftSheetCapabilities)) {
      context.push('/detachment/$detachmentId/shifts');
      return;
    }
    await showShiftManageSheet(
      context: context,
      ref: ref,
      shift: shift,
      detachmentId: detachmentId,
      canAssign: caps.canIn(detachmentId, Cap.shiftAssign),
      canRecord: caps.canIn(detachmentId, Cap.shiftAttendanceRecord),
      canOverride: caps.canIn(detachmentId, Cap.shiftAttendanceOverride),
      canManage: caps.canIn(detachmentId, Cap.shiftManage),
      canDelete: caps.canIn(detachmentId, Cap.shiftDelete),
    );
  }

  Future<void> _openItem(
    String detachmentId,
    String itemId,
    Capabilities caps,
  ) async {
    final item =
        _valueOf(await ref.read(inventoryRepositoryProvider).byId(itemId));
    if (!mounted) return;
    if (item == null) {
      _gone();
      return;
    }
    // The existing stock sheet from the storage tab, not a copy of it.
    await showInventoryItemSheet(
      context: context,
      detachmentId: detachmentId,
      item: item,
      canAdjust: caps.canIn(detachmentId, Cap.inventoryAdjust),
    );
  }
}

/// The record a re-read produced, or null when there is none to open. An
/// offline read with a cached copy is still a record; a failure is not.
T? _valueOf<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => null,
      offline: (cached) => cached,
    );

/// A list entry marker: one result row and where it sits in its group's card.
class _Row {
  const _Row({
    required this.result,
    required this.isFirst,
    required this.isLast,
  });

  final SearchResult result;
  final bool isFirst;
  final bool isLast;
}

/// A list entry marker: the tail of a group that hit its cap.
class _More {
  const _More(this.hidden);
  final int hidden;
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('global-search-field'),
      controller: controller,
      enabled: enabled,
      autofocus: enabled,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: S.globalSearchHint,
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                key: const Key('global-search-clear'),
                tooltip: S.globalSearchClear,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

/// The category selector. Shown only when there is more than one category to
/// choose between — a single-category session gets no chip it cannot change.
class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<AdminDataCategory> categories;
  final AdminDataCategory? selected;
  final ValueChanged<AdminDataCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return AppFilterBar(
      semanticLabel: S.globalSearchCategoryFilter,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        AppFilterChip(
          label: S.all,
          selected: selected == null,
          onSelected: (_) => onSelect(null),
        ),
        for (final category in categories)
          AppFilterChip(
            key: Key('search-chip-${category.name}'),
            label: searchCategoryLabel(category),
            selected: selected == category,
            onSelected: (_) => onSelect(selected == category ? null : category),
          ),
      ],
    );
  }
}

/// How many rows matched, and whether any of them came from a cached copy.
class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.stale});

  final int total;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        0,
      ),
      child: Row(children: [
        Text(
          searchResultsLabel(total),
          key: const Key('search-results-count'),
          style: TextStyle(color: context.c.ink3, fontSize: 12),
        ),
        const Spacer(),
        if (stale) const StaleBadge(),
      ]),
    );
  }
}

/// One source failed while the others answered. A line, not a screen: the
/// results that did load stay exactly where they are.
class _DegradedNotice extends StatelessWidget {
  const _DegradedNotice({required this.categories});

  final List<AdminDataCategory> categories;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      key: const Key('search-degraded'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.warnTint,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, size: 16, color: c.warn),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            searchDegradedLabel(categories),
            style: TextStyle(color: c.ink2, fontSize: 12, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

/// The rows of one group read as a single card: only the first draws a top
/// hairline and only the last rounds its bottom, so adjacent rows share one
/// divider instead of stacking two.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.isFirst,
    required this.isLast,
    required this.child,
  });

  final bool isFirst;
  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const radius = Radius.circular(AppRadii.lg);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: isFirst ? BorderSide(color: c.line) : BorderSide.none,
          bottom: BorderSide(color: c.line),
          left: BorderSide(color: c.line),
          right: BorderSide(color: c.line),
        ),
        borderRadius: BorderRadius.vertical(
          top: isFirst ? radius : Radius.zero,
          bottom: isLast ? radius : Radius.zero,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// One result: a category tile, the record's name, and the line that tells it
/// apart from a record with the same name somewhere else.
class SearchResultRow extends StatelessWidget {
  const SearchResultRow({
    super.key,
    required this.result,
    required this.onTap,
  });

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(
                    searchCategoryIcon(result.category),
                    size: 17,
                    color: c.ink3,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        // A long Arabic name wraps rather than being cut
                        // mid-word; a third line would stop the list scanning.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: c.ink,
                        ),
                      ),
                      if (result.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          result.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: c.ink3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: ForwardChevron(size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
