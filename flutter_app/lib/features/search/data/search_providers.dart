/// The searchable corpus, and the scope rules that decide what goes into it.
///
/// ## Why an index and not a query per keystroke
///
/// There is no global-search endpoint in this build and none is invented here.
/// The four categories live in four repositories that already answer per
/// detachment, so Global Search composes them: one read per (detachment,
/// category) when the screen opens, matched in memory afterwards. Typing then
/// costs nothing, needs no debounce, and cannot race — there is no
/// per-keystroke request for a slow answer to overwrite. A refresh re-runs the
/// whole build, which is the only thing that can change the corpus.
///
/// ## Scope
///
/// Scope-safe from the first read, never filtered afterwards. The detachment
/// list comes from [detachmentListProvider], which already narrows to what the
/// grant covers, and each detachment's categories come from
/// `AdminView.categoriesIn` — so a session with `member.view` in one
/// detachment and not another indexes one roster and not the other. Nothing
/// unauthorised is ever loaded and then hidden.
///
/// TODO(security): a UX filter, like every other client-side access decision.
/// The backend must not return a record the caller may not see — see the
/// contract at the top of `core/access/capability.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/admin_experience.dart';
import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../../detachment/data/detachment_providers.dart';
import '../../detachment/domain/detachment_models.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../shift/data/shift_providers.dart';
import '../../shift/domain/shift_models.dart';
import '../../team/data/team_providers.dart';
import '../../team/domain/team_models.dart';
import '../domain/search_models.dart';
import 'search_entries.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';

/// The active detachments, the same cache entry the dashboard warms.
///
/// Active only: Global Search is an operational finder. An archived
/// detachment and the records inside it are history, and history is out of
/// scope for this screen (`§27`).
const _activeDetachments = DetachmentListQuery(filter: DetachmentStatus.active);

/// How much of the schedule a shift search covers: four whole weeks — last
/// week, this week, and the two ahead — measured from the Saturday the app's
/// week begins on.
///
/// A window, not the whole history, and this is the one honest gap in the
/// screen. A detachment runs for ten to fifteen days, so "which shift" is
/// almost always a question about the schedule around today — and the shift
/// repository answers by date range, with no query of its own. Searching all
/// time would mean pulling every shift a detachment has ever run on every
/// screen open, which is exactly the unbounded scan `§21` forbids. A real
/// backend search endpoint is what would lift this; `HANDOFF.md` records it.
const Duration _shiftWindowBefore = Duration(days: 7);
const Duration _shiftWindowAfter = Duration(days: 20);

/// What the current session may search, in group order.
///
/// Synchronous, so the app bar's action and the category chips can be drawn
/// before the corpus lands. Derived from [adminViewProvider] — the same
/// `AdminView` the index scopes itself with, so the chips and the results can
/// never disagree about what is permitted.
final searchableCategoriesProvider = Provider<List<AdminDataCategory>>((ref) {
  final inventoryEnabled = ref.watch(
    tenantFeatureAvailableProvider(TenantFeatureKey.inventory),
  );
  return [
    for (final category in searchableCategoriesOf(ref.watch(adminViewProvider)))
      if (category != AdminDataCategory.inventory || inventoryEnabled) category,
  ];
});

/// The corpus for one search session.
///
/// `autoDispose`: leaving the screen drops it, so coming back searches what is
/// true then rather than what was true when the screen was last open.
///
/// It watches the session, so a grant that narrows while search is open
/// rebuilds the index against the narrower scope — the restricted rows leave
/// the list rather than sitting there still tappable.
final searchIndexProvider =
    FutureProvider.autoDispose<SearchIndex>((ref) async {
  // Everything this build needs from `ref` is taken before the first await,
  // the same order `detachmentListProvider` reads in: after an async gap a
  // disposed provider's `ref` is no longer safe to watch.
  final now = ref.watch(clockProvider)();
  final sessionFuture = ref.watch(currentUserProvider.future);
  final featureAccessFuture =
      ref.watch(currentTenantFeatureAccessFutureProvider.future);
  final session = await sessionFuture;
  final featureAccess = await featureAccessFuture;
  final caps = session?.capabilities ?? Capabilities.none;
  final view = AdminView.of(caps);
  final allowed = {
    for (final category in searchableCategoriesOf(view))
      if (category != AdminDataCategory.inventory ||
          featureAccess.isAvailable(TenantFeatureKey.inventory))
        category,
  };
  if (allowed.isEmpty) return SearchIndex.none;
  final detachmentList =
      ref.watch(detachmentListProvider(_activeDetachments).future);
  final team = allowed.contains(AdminDataCategory.members)
      ? ref.read(teamRepositoryProvider)
      : null;
  final shifts = allowed.contains(AdminDataCategory.shifts)
      ? ref.read(shiftRepositoryProvider)
      : null;
  final inventory = allowed.contains(AdminDataCategory.inventory)
      ? ref.read(inventoryRepositoryProvider)
      : null;

  final degraded = <AdminDataCategory>{};
  var offline = false;

  final detachments = _unwrap(await detachmentList);
  offline |= detachments.offline;
  if (detachments.failed) {
    // Without the detachment list there is no scope to search inside, so
    // nothing is degraded in isolation — everything is.
    return SearchIndex(
      results: const [],
      allowed: allowed,
      degraded: allowed,
      detachmentCount: 0,
      offline: offline,
    );
  }

  final visible = detachments.data;
  final week = startOfWeek(now);
  final from = week.subtract(_shiftWindowBefore);
  final to = week.add(_shiftWindowAfter);

  // Which detachment owns which category, decided once through the seam.
  final categories = {
    for (final detachment in visible)
      detachment.id: view.categoriesIn(detachment.id),
  };
  bool covers(String id, AdminDataCategory category) =>
      allowed.contains(category) && categories[id]!.contains(category);

  // Independent sources, so they run together rather than one detachment at a
  // time. The results are re-assembled in list order below, which is what
  // keeps the corpus order — and therefore the ranking tie-break —
  // deterministic regardless of which read finished first.
  final rosters = <String, Future<Result<List<TeamMember>>>>{};
  final schedules = <String, Future<Result<List<Shift>>>>{};
  final stock = <String, Future<Result<List<InventoryItem>>>>{};
  for (final detachment in visible) {
    final id = detachment.id;
    if (covers(id, AdminDataCategory.members)) {
      rosters[id] = team!.listForDetachment(id);
    }
    if (covers(id, AdminDataCategory.shifts)) {
      schedules[id] = shifts!.listForRange(id, from, to);
    }
    if (covers(id, AdminDataCategory.inventory)) {
      stock[id] = inventory!.listForDetachment(id);
    }
  }
  await Future.wait<void>([
    ...rosters.values,
    ...schedules.values,
    ...stock.values,
  ]);

  // Null while a single detachment is in scope: a context line exists to tell
  // records apart, and there is nothing to tell apart from.
  final multi = visible.length > 1;
  String? context(Detachment detachment) => multi ? detachment.name : null;

  final results = <SearchResult>[];
  var order = 0;

  if (allowed.contains(AdminDataCategory.detachments)) {
    for (final detachment in visible) {
      results.add(detachmentEntry(detachment, order: order++));
    }
  }

  for (final detachment in visible) {
    final roster = rosters[detachment.id];
    if (roster == null) continue;
    final loaded = _unwrap(await roster);
    offline |= loaded.offline;
    if (loaded.failed) degraded.add(AdminDataCategory.members);
    for (final member in loaded.data) {
      results.add(memberEntry(
        member,
        order: order++,
        detachmentName: context(detachment),
      ));
    }
  }

  for (final detachment in visible) {
    final schedule = schedules[detachment.id];
    if (schedule == null) continue;
    final loaded = _unwrap(await schedule);
    offline |= loaded.offline;
    if (loaded.failed) degraded.add(AdminDataCategory.shifts);
    for (final shift in loaded.data) {
      results.add(shiftEntry(
        shift,
        order: order++,
        detachmentName: context(detachment),
      ));
    }
  }

  for (final detachment in visible) {
    final items = stock[detachment.id];
    if (items == null) continue;
    final loaded = _unwrap(await items);
    offline |= loaded.offline;
    if (loaded.failed) degraded.add(AdminDataCategory.inventory);
    for (final item in loaded.data) {
      results.add(inventoryEntry(
        item,
        order: order++,
        detachmentName: context(detachment),
      ));
    }
  }

  return SearchIndex(
    results: results,
    allowed: allowed,
    degraded: degraded,
    detachmentCount: visible.length,
    offline: offline,
  );
});

/// One source's answer, flattened into what the index needs to know about it.
///
/// A failure and an offline read with no cached copy both mean "this category
/// is incomplete"; an offline read *with* a copy is usable data that the page
/// still marks as offline. Nothing here throws: one source failing must not
/// take the other three down with it (`§17`).
class _Loaded<T> {
  const _Loaded(this.data, {this.failed = false, this.offline = false});

  final List<T> data;
  final bool failed;
  final bool offline;
}

_Loaded<T> _unwrap<T>(Result<List<T>> result) => result.when(
      success: (data, {stale = false}) => _Loaded<T>(data),
      failure: (_, __) => _Loaded<T>(const [], failed: true),
      offline: (cached) => _Loaded<T>(
        cached ?? const [],
        offline: true,
        failed: cached == null,
      ),
    );
