import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/admin_experience.dart';
import 'package:mtm/features/search/domain/search_models.dart';
import 'package:mtm/features/search/domain/search_query.dart';

/// Global Search's whole logic, tested without a widget tree.
///
/// What is checked here is what a person cannot check by looking: that the
/// order is total and repeatable, that Arabic spelling variants find the same
/// record, and that a result whose category is no longer permitted cannot be
/// rendered even when it is still sitting in the corpus.

SearchResult _result({
  required String title,
  AdminDataCategory category = AdminDataCategory.members,
  String? id,
  int order = 0,
  List<String> secondary = const [],
}) =>
    SearchResult(
      category: category,
      id: id ?? title,
      title: title,
      subtitle: '',
      order: order,
      secondary: secondary,
      destination: MemberDestination(detachmentId: 'd1', memberId: id ?? title),
    );

SearchIndex _index(
  List<SearchResult> results, {
  Set<AdminDataCategory>? allowed,
  Set<AdminDataCategory> degraded = const {},
}) =>
    SearchIndex(
      results: results,
      allowed: allowed ?? searchCategoryOrder.toSet(),
      degraded: degraded,
      detachmentCount: 1,
      offline: false,
    );

List<String> _titles(List<SearchGroup> groups) =>
    [for (final group in groups) ...group.results.map((r) => r.title)];

void main() {
  group('ranking', () {
    final index = _index([
      _result(title: 'محمد علي', order: 0),
      _result(title: 'علي منصور', order: 1),
      _result(title: 'علي', order: 2),
      _result(title: 'سامي درويش', order: 3, secondary: ['علي']),
    ]);

    test(
        'exact outranks prefix, prefix outranks contains, contains outranks '
        'a secondary field', () {
      expect(
        _titles(runSearch(index, 'علي')),
        ['علي', 'علي منصور', 'محمد علي', 'سامي درويش'],
      );
    });

    test('a secondary-field match never outranks a title match', () {
      expect(matchOf(_result(title: 'علي'), 'علي'), SearchMatch.exact);
      expect(
        matchOf(_result(title: 'سامي', secondary: ['علي']), 'علي'),
        SearchMatch.secondary,
      );
      expect(SearchMatch.exact.index, lessThan(SearchMatch.secondary.index));
    });

    test(
        'equal-ranking results keep corpus order, then id — the same list '
        'every rebuild', () {
      final tied = _index([
        _result(title: 'ليلى ياسين', id: 'm9', order: 7),
        _result(title: 'ليلى قاسم', id: 'm2', order: 3),
        _result(title: 'ليلى سعيد', id: 'm5', order: 3),
      ]);
      // order 3 before order 7; inside order 3 the corpus positions are equal
      // so the id decides — and it decides the same way on every build.
      for (var i = 0; i < 3; i++) {
        expect(
          [
            for (final g in runSearch(tied, 'ليلى'))
              ...g.results.map((r) => r.id)
          ],
          ['m2', 'm5', 'm9'],
        );
      }
    });

    test('no match produces no group at all', () {
      expect(runSearch(index, 'زياد'), isEmpty);
    });
  });

  group('Arabic normalization is the roster search, reused', () {
    final index = _index([
      _result(title: 'أحمد كنعان', id: 'm1', order: 0),
      _result(title: 'سلمى نجّار', id: 'm2', order: 1, secondary: ['١٠٧']),
      _result(title: 'رانيا  حمصية', id: 'm3', order: 2),
    ]);

    test('alef variants fold: "احمد" finds "أحمد"', () {
      expect(_titles(runSearch(index, 'احمد')), ['أحمد كنعان']);
    });

    test('diacritics and shadda are decoration, not spelling', () {
      expect(_titles(runSearch(index, 'سلمى نجار')), ['سلمى نجّار']);
    });

    test('ta-marbuta and ya variants fold', () {
      expect(_titles(runSearch(index, 'حمصيه')), ['رانيا  حمصية']);
    });

    test('a personal number types either way', () {
      expect(_titles(runSearch(index, '107')), ['سلمى نجّار']);
      expect(_titles(runSearch(index, '١٠٧')), ['سلمى نجّار']);
    });

    test('repeated whitespace collapses on both sides', () {
      expect(_titles(runSearch(index, 'رانيا حمصية')), ['رانيا  حمصية']);
    });
  });

  group('query length', () {
    final index = _index([_result(title: 'علي منصور')]);

    test('an empty query searches nothing', () {
      expect(runSearch(index, ''), isEmpty);
      expect(runSearch(index, '   '), isEmpty);
    });

    test('one character is below the floor', () {
      expect(minSearchQueryLength, 2);
      expect(runSearch(index, 'ع'), isEmpty);
      expect(runSearch(index, 'عل'), isNotEmpty);
    });
  });

  group('grouping', () {
    final index = _index([
      _result(
        title: 'مفرزة دمشق',
        category: AdminDataCategory.detachments,
        id: 'd1',
        order: 0,
      ),
      _result(title: 'دمشق كنعان', id: 'm1', order: 1),
      _result(
        title: 'شاش دمشقي',
        category: AdminDataCategory.inventory,
        id: 'i1',
        order: 2,
      ),
    ]);

    test('groups come back in the fixed display order, members first', () {
      expect(
        [for (final g in runSearch(index, 'دمشق')) g.category],
        [
          AdminDataCategory.members,
          AdminDataCategory.detachments,
          AdminDataCategory.inventory,
        ],
      );
    });

    test('a category with no hits is not an empty section', () {
      final groups = runSearch(index, 'دمشق');
      expect(groups.map((g) => g.category),
          isNot(contains(AdminDataCategory.shifts)));
    });

    test('one chip narrows to one group', () {
      final groups =
          runSearch(index, 'دمشق', only: AdminDataCategory.inventory);
      expect(groups, hasLength(1));
      expect(groups.single.category, AdminDataCategory.inventory);
    });

    test(
        'a category the index does not allow is dropped even when its rows '
        'are still in the corpus', () {
      // The narrowing case: the grant lost `member.view` while the screen was
      // open. Filtering happens before display, not at the destination.
      final narrowed = _index(
        index.results,
        allowed: const {
          AdminDataCategory.detachments,
          AdminDataCategory.inventory,
        },
      );
      final groups = runSearch(narrowed, 'دمشق');
      expect(groups.map((g) => g.category),
          isNot(contains(AdminDataCategory.members)));
      expect(_titles(groups), isNot(contains('دمشق كنعان')));
    });

    test('a long group is capped and says how many it kept back', () {
      final many = _index([
        for (var i = 0; i < 25; i++)
          _result(title: 'علي $i', id: 'm$i', order: i),
      ]);
      final group = runSearch(many, 'علي', limitPerCategory: 20).single;
      expect(group.results, hasLength(20));
      expect(group.total, 25);
      expect(group.hidden, 5);
      expect(totalResults([group]), 25);
    });
  });
}
