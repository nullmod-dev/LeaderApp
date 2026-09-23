/// Matching, ranking and grouping — the whole of Global Search's logic, as
/// pure functions over a built [SearchIndex].
///
/// Deliberately dull. There is no fuzzy distance, no scoring model and no
/// learning: a person looking for a colleague types part of their name and
/// expects the same list every time. Predictable beats clever here, and a
/// wrong "smart" match on a roster is not a mild annoyance — it is the wrong
/// person's attendance record.
library;

import '../../../core/access/admin_experience.dart';
import '../../team/domain/member_search.dart';
import 'search_models.dart';

/// Below this many normalized characters a query matches too much to be
/// useful. Not a cost guard — matching is in-memory and free — a quality one:
/// one Arabic letter appears in most names on any roster.
const int minSearchQueryLength = 2;

/// How many rows one group draws before it starts saying "and N more".
const int maxResultsPerCategory = 20;

/// How well a result matches, best first. The whole ranking model.
enum SearchMatch {
  /// The title *is* the query.
  exact,

  /// The title starts with the query.
  prefix,

  /// The query appears somewhere in the title.
  contains,

  /// The query appears in a secondary field only — a section, a number, a
  /// supervisor's name. Always below every title match.
  secondary,
}

/// The comparison form of a typed query: the same normalization the roster
/// search uses, so search behaves identically wherever a person types a name.
String searchNeedle(String raw) => memberSearchKey(raw);

/// How [result] matches [needle], or null when it does not.
///
/// [needle] must already be normalized by [searchNeedle]; the result's own
/// keys were normalized once when the index was built.
SearchMatch? matchOf(SearchResult result, String needle) {
  if (needle.isEmpty) return null;
  final title = result.titleKey;
  if (title == needle) return SearchMatch.exact;
  if (title.startsWith(needle)) return SearchMatch.prefix;
  if (title.contains(needle)) return SearchMatch.contains;
  for (final key in result.secondaryKeys) {
    if (key.contains(needle)) return SearchMatch.secondary;
  }
  return null;
}

/// The grouped, ranked answer to [rawQuery].
///
/// Empty for a query below [minSearchQueryLength] — the screen distinguishes
/// "not asked yet" from "asked and nothing matched", and this function
/// deliberately does not, because both are legitimately zero groups.
///
/// [only] narrows to one category chip. A category the index does not allow is
/// dropped even if a result for it somehow survived in the corpus: filtering
/// before display is the rule, and this is the last place it can be enforced.
///
/// Ordering inside a group is total and stable: rank, then the corpus order
/// assigned at index time, then the record id. Two builds of the same query
/// over the same index produce the same list in the same order.
List<SearchGroup> runSearch(
  SearchIndex index,
  String rawQuery, {
  AdminDataCategory? only,
  int limitPerCategory = maxResultsPerCategory,
}) {
  final needle = searchNeedle(rawQuery);
  if (needle.length < minSearchQueryLength) return const [];

  final buckets = <AdminDataCategory, List<_Hit>>{};
  for (final result in index.results) {
    final category = result.category;
    if (!index.allowed.contains(category)) continue;
    if (only != null && category != only) continue;
    final match = matchOf(result, needle);
    if (match == null) continue;
    (buckets[category] ??= <_Hit>[]).add(_Hit(match.index, result));
  }

  final groups = <SearchGroup>[];
  for (final category in searchCategoryOrder) {
    final hits = buckets[category];
    if (hits == null || hits.isEmpty) continue;
    hits.sort(_byRankThenOrder);
    groups.add(SearchGroup(
      category: category,
      results: [
        for (final hit in hits.take(limitPerCategory)) hit.result,
      ],
      total: hits.length,
    ));
  }
  return groups;
}

/// Total rows matched across every group, before any cap.
int totalResults(List<SearchGroup> groups) =>
    groups.fold(0, (sum, group) => sum + group.total);

class _Hit {
  const _Hit(this.rank, this.result);
  final int rank;
  final SearchResult result;
}

int _byRankThenOrder(_Hit a, _Hit b) {
  final byRank = a.rank.compareTo(b.rank);
  if (byRank != 0) return byRank;
  final byOrder = a.result.order.compareTo(b.result.order);
  if (byOrder != 0) return byOrder;
  return a.result.id.compareTo(b.result.id);
}
