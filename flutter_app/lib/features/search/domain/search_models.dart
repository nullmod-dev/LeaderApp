/// The shapes Global Search works in: one presentation result, where it
/// leads, and the corpus a query runs over.
///
/// **No parallel domain.** Nothing here copies a `TeamMember`, a `Shift`, a
/// `Detachment` or an `InventoryItem` — a result carries the two lines it
/// draws, the id it was built from, and a destination that names an existing
/// surface. When a row is tapped the record is re-read from the repository
/// that owns it, so a stale copy can never be what the user acts on.
///
/// **No second permission model either.** The categories a session may search
/// are `AdminView.searchableCategories` narrowed to the four this screen
/// supports; the capability that must still be held at the moment of the tap
/// is resolved by [destinationAllowed] through `Capabilities.canIn`, like
/// every other access decision in the app.
library;

import '../../../core/access/admin_experience.dart';
import '../../../core/access/capability.dart';
import '../../team/domain/member_search.dart';

export '../../detachment/domain/detachment_tabs.dart' show detachmentTabFor;

/// The categories Global Search supports, in the order their groups render.
///
/// Four of `AdminDataCategory`'s six. `statistics` is a chart, not a record
/// anyone searches by name, and `workshops` carry no detachment scope and no
/// searchable roster of their own in this build — leaving them out is a
/// smaller lie than offering a group that can never answer.
const List<AdminDataCategory> searchCategoryOrder = [
  AdminDataCategory.members,
  AdminDataCategory.detachments,
  AdminDataCategory.shifts,
  AdminDataCategory.inventory,
];

/// What [view] may search, in [searchCategoryOrder].
///
/// **The seam.** This is the only question Global Search asks about breadth,
/// and `admin_experience.dart` is the only place the answer is derived. An
/// empty list is a real state — an account granted nothing — and the screen
/// renders it as a designed restricted state rather than an empty list.
List<AdminDataCategory> searchableCategoriesOf(AdminView view) {
  final allowed = view.searchableCategories;
  return [
    for (final category in searchCategoryOrder)
      if (allowed.contains(category)) category,
  ];
}

// -----------------------------------------------------------------------------
// Destinations
// -----------------------------------------------------------------------------

/// Where a result leads. Every value names a surface that **already exists**;
/// Global Search owns no detail screen of its own.
sealed class SearchDestination {
  const SearchDestination();

  /// The detachment the record lives in. Every searchable record in this
  /// build is detachment-owned, which is what makes one scope check enough.
  String get detachmentId;
}

/// The existing member attendance/detail page,
/// `/detachment/:id/member/:memberId/status`.
class MemberDestination extends SearchDestination {
  const MemberDestination({required this.detachmentId, required this.memberId});

  @override
  final String detachmentId;
  final String memberId;
}

/// The existing detachment detail shell. Which tab it opens on is decided at
/// tap time by [detachmentTabFor], because the roster tab is gated and the
/// schedule tab is not.
class DetachmentDestination extends SearchDestination {
  const DetachmentDestination({required this.detachmentId});

  @override
  final String detachmentId;
}

/// The existing shift management sheet — the same one the schedule and the
/// Notifications Center open.
class ShiftDestination extends SearchDestination {
  const ShiftDestination({required this.detachmentId, required this.shiftId});

  @override
  final String detachmentId;
  final String shiftId;
}

/// The existing stock item sheet on the storage tab.
class InventoryDestination extends SearchDestination {
  const InventoryDestination({
    required this.detachmentId,
    required this.itemId,
  });

  @override
  final String detachmentId;
  final String itemId;
}

/// Whether [destination] may still be opened by [caps].
///
/// Re-asked at the moment of the tap, not trusted from index time: a grant can
/// narrow while the screen is open, and a result that was legitimate when it
/// was listed must not still navigate. Resolves through `Capabilities.canIn`
/// like everything else — the single-resolver rule.
///
/// `detachment.view` is the anchor of the scoping model and any scoped grant
/// implies it, so it is the right question for the three detachment-owned
/// surfaces; the roster page is gated on `member.view` exactly as its route is.
///
/// TODO(security): a UX gate. The backend rejects the request regardless —
/// see the contract at the top of `core/access/capability.dart`.
bool destinationAllowed(SearchDestination destination, Capabilities caps) =>
    switch (destination) {
      MemberDestination(:final detachmentId) =>
        caps.canIn(detachmentId, Cap.memberView),
      DetachmentDestination(:final detachmentId) ||
      ShiftDestination(:final detachmentId) ||
      InventoryDestination(:final detachmentId) =>
        caps.canIn(detachmentId, Cap.detachmentView),
    };

// Which tab a detachment result opens on is `detachmentTabFor`, now owned by
// the detachment feature (`detachment_tabs.dart`) so the detachment list and
// the detail shell ask the same question Search does. Re-exported at the top
// of this file for the call sites that already import it from here.

// -----------------------------------------------------------------------------
// Results
// -----------------------------------------------------------------------------

/// One row of Global Search.
///
/// The comparison keys are computed **once**, when the index is built, by the
/// same `memberSearchKey` the roster search uses — so typing does no
/// normalization work at all, and "احمد" finds "أحمد" here exactly as it does
/// on the Members tab.
class SearchResult {
  SearchResult({
    required this.category,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.order,
    required this.destination,
    List<String> secondary = const [],
  })  : titleKey = memberSearchKey(title),
        secondaryKeys = [
          for (final value in secondary)
            if (value.trim().isNotEmpty) memberSearchKey(value),
        ];

  final AdminDataCategory category;

  /// The record's own id. Never rendered — it is what the tap re-reads.
  final String id;

  final String title;

  /// The context line: enough to tell two records with the same name apart.
  final String subtitle;

  /// Position in the corpus, assigned in a fixed order at index time. The
  /// tie-break that makes ranking deterministic — equal-scoring rows keep the
  /// order their sources were listed in rather than whatever the sort happened
  /// to do this build.
  final int order;

  final SearchDestination destination;

  /// [title], normalized. Exact, prefix and contains matches are measured
  /// against this.
  final String titleKey;

  /// The other fields a person might type — a section, a personal number, a
  /// supervisor's name, a unit. Matched last, and never ranked above a title.
  final List<String> secondaryKeys;

  String get detachmentId => destination.detachmentId;
}

/// The corpus one search session runs over, plus what could not be loaded.
///
/// Built once when the screen opens rather than per keystroke: every source
/// is a repository read, and re-running fifteen of them on every letter is the
/// difference between search that feels instant and search that stutters.
/// Because the index is a provider and matching is pure, a slow source can
/// never overwrite a newer query — there is no per-keystroke request to race.
class SearchIndex {
  const SearchIndex({
    required this.results,
    required this.allowed,
    required this.degraded,
    required this.detachmentCount,
    required this.offline,
  });

  /// Nothing searchable: the session was granted no searchable category.
  static const SearchIndex none = SearchIndex(
    results: [],
    allowed: {},
    degraded: {},
    detachmentCount: 0,
    offline: false,
  );

  final List<SearchResult> results;

  /// The categories this session may search. Enforced again at match time, so
  /// a result that outlived its permission cannot be rendered.
  final Set<AdminDataCategory> allowed;

  /// Categories whose sources failed or were unreachable. Their results are
  /// missing or incomplete; every other category is unaffected.
  final Set<AdminDataCategory> degraded;

  /// How many detachments the corpus covers. One means the context line does
  /// not need to repeat the detachment name on every row.
  final int detachmentCount;

  /// At least one source answered from an offline state.
  final bool offline;

  bool get isEmpty => results.isEmpty;

  /// Every allowed category failed — there is nothing to search, and saying
  /// "no results" for it would be a lie.
  bool get isFullyDegraded =>
      allowed.isNotEmpty && degraded.containsAll(allowed);
}

/// One category's results, ranked.
class SearchGroup {
  const SearchGroup({
    required this.category,
    required this.results,
    required this.total,
  });

  final AdminDataCategory category;

  /// The rows to draw — capped, so one enormous group cannot bury the others.
  final List<SearchResult> results;

  /// How many matched before the cap.
  final int total;

  int get hidden => total - results.length;
}
