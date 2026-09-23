import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/admin_experience.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_presets.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/inventory/data/inventory_providers.dart';
import 'package:mtm/features/inventory/domain/inventory_models.dart';
import 'package:mtm/features/inventory/domain/inventory_repository.dart';
import 'package:mtm/features/search/data/search_providers.dart';
import 'package:mtm/features/search/domain/search_models.dart';
import 'package:mtm/features/search/domain/search_query.dart';
import 'package:mtm/features/team/data/team_providers.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/features/team/domain/team_repository.dart';

/// What Global Search may see, and what it must not.
///
/// The half a person cannot check by looking: not that the restricted rows are
/// hidden, but that they were never loaded, never matched, and cannot be
/// reached after a grant narrows.

/// The seeded detachment a scoped admin is granted.
const _mine = 'd_dam_central';

/// A seeded member of each, and a seeded stock item of the other detachment.
const _myMember = 'أحمد كنعان';
const _theirMember = 'أمين رياض';
const _theirItem = 'أتروبين';

AuthUser _user(Capabilities caps) => AuthUser(
      id: 'u',
      name: 'مشرف',
      email: 'admin@mtm.org',
      role: AuthRole.mainAdmin,
      saasTenantId: kDemoSaasTenantId,
      capabilities: caps,
      orgName: 'MTM',
    );

final _full = _user(const Capabilities(global: Cap.all));
final _scoped =
    _user(CapabilityPreset.subAdmin.grant(detachments: const [_mine]));

/// A session answer a test can change mid-flight, the way a re-issued grant
/// changes it in production.
class _Session {
  _Session(this.user);
  AuthUser user;
}

ProviderContainer _container(
  _Session session, {
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      currentUserResultProvider.overrideWith(
        (ref) async => Success<AuthUser?>(session.user),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<SearchIndex> _index(ProviderContainer container) =>
    container.read(searchIndexProvider.future);

List<SearchResult> _of(SearchIndex index, AdminDataCategory category) => [
      for (final result in index.results)
        if (result.category == category) result,
    ];

void main() {
  group('a full admin searches the organisation', () {
    test('every category is offered and more than one detachment is in it',
        () async {
      final index = await _index(_container(_Session(_full)));

      expect(index.allowed, searchCategoryOrder.toSet());
      expect(index.detachmentCount, greaterThan(1));
      for (final category in searchCategoryOrder) {
        expect(_of(index, category), isNotEmpty, reason: '$category is empty');
      }
      // Records from a detachment a scoped admin would never see.
      expect(
        _of(index, AdminDataCategory.members).map((r) => r.title),
        contains(_theirMember),
      );
    });

    test(
        'a row from a second detachment carries the detachment in its context '
        'line, so two records with the same shape are distinguishable',
        () async {
      final index = await _index(_container(_Session(_full)));
      final members = _of(index, AdminDataCategory.members);
      final theirs = members.firstWhere((r) => r.title == _theirMember);
      expect(theirs.subtitle, contains('حمص'));
    });
  });

  group('a scoped admin searches only their own scope', () {
    test('the corpus holds nothing from a detachment they were not granted',
        () async {
      final index = await _index(_container(_Session(_scoped)));

      expect(index.detachmentCount, 1);
      for (final result in index.results) {
        expect(result.detachmentId, _mine,
            reason: '${result.title} leaked from ${result.detachmentId}');
      }
      expect(
        _of(index, AdminDataCategory.members).map((r) => r.title),
        contains(_myMember),
      );
    });

    test('a record outside the scope cannot be found by typing its name',
        () async {
      final index = await _index(_container(_Session(_scoped)));
      expect(runSearch(index, _theirMember), isEmpty);
      expect(runSearch(index, _theirItem), isEmpty);
      expect(runSearch(index, 'حمص'), isEmpty);
    });

    test(
        'a single-detachment session gets no detachment name repeated on '
        'every row', () async {
      final index = await _index(_container(_Session(_scoped)));
      final member = _of(index, AdminDataCategory.members)
          .firstWhere((r) => r.title == _myMember);
      expect(member.subtitle, isNot(contains('مفرزة')));
    });
  });

  group('a missing capability removes a whole category', () {
    test('without member.view there is no members group and no roster row',
        () async {
      final index = await _index(_container(_Session(_user(
        const Capabilities(scoped: {
          _mine: {Cap.inventoryAdjust}
        }),
      ))));

      expect(index.allowed, isNot(contains(AdminDataCategory.members)));
      expect(_of(index, AdminDataCategory.members), isEmpty);
      expect(
        runSearch(index, _myMember).map((g) => g.category),
        isNot(contains(AdminDataCategory.members)),
      );
      // The detachment itself, its schedule and its store still open on
      // `detachment.view`, which any scoped grant implies.
      expect(index.allowed, contains(AdminDataCategory.inventory));
      expect(_of(index, AdminDataCategory.inventory), isNotEmpty);
    });

    test(
        'a shift is still findable by its supervisor without member.view — '
        'the schedule already names them', () async {
      // Not a leak, and worth pinning so it is not "fixed" into one. The
      // schedule tab and the dashboard both render `Shift.manager.name` on
      // `detachment.view` alone; `member.view` gates the *roster*. Search
      // matching the same name a shift card already prints exposes nothing the
      // destination does not, and hiding it would make the schedule
      // unsearchable by the one person answerable for it.
      final index = await _index(_container(_Session(_user(
        const Capabilities(scoped: {
          _mine: {Cap.inventoryAdjust}
        }),
      ))));

      final groups = runSearch(index, _myMember);
      expect(groups, hasLength(1));
      expect(groups.single.category, AdminDataCategory.shifts);
    });

    test(
        'a session granted nothing searches nothing, and says so rather than '
        'showing an empty list', () async {
      final index =
          await _index(_container(_Session(_user(Capabilities.none))));
      expect(index.allowed, isEmpty);
      expect(index.results, isEmpty);
      expect(runSearch(index, 'أحمد'), isEmpty);
    });

    test('an unknown grant key unlocks nothing it names', () async {
      // A key the backend invented and this build does not understand is
      // denied by `Capabilities.canIn`, so it cannot switch a category on.
      // What it does still do — because any scoped entry at all implies
      // `detachment.view` (`CAPABILITIES.md` §4/Q3) — is make that one
      // detachment visible. That is the documented scoping rule, not an
      // escalation: the categories it asked for stay shut.
      final index = await _index(_container(_Session(_user(
        const Capabilities(
          global: {'search.everything'},
          scoped: {
            _mine: {'member.readAll'}
          },
        ),
      ))));

      expect(index.allowed, isNot(contains(AdminDataCategory.members)));
      expect(_of(index, AdminDataCategory.members), isEmpty);
      expect(index.detachmentCount, 1);
      for (final result in index.results) {
        expect(result.detachmentId, _mine);
      }
    });

    test('a global-only unknown key grants no scope at all', () async {
      final index = await _index(_container(_Session(_user(
        const Capabilities(global: {'search.everything'}),
      ))));
      expect(index.allowed, isEmpty);
      expect(index.results, isEmpty);
    });
  });

  test('a grant that narrows while search is open takes its results with it',
      () async {
    final session = _Session(_full);
    final container = _container(session);

    final before = await _index(container);
    expect(runSearch(before, _theirMember), isNotEmpty);

    session.user = _scoped;
    container.invalidate(currentUserResultProvider);

    final after = await _index(container);
    expect(after.detachmentCount, 1);
    expect(runSearch(after, _theirMember), isEmpty);
    for (final result in after.results) {
      expect(result.detachmentId, _mine);
    }
  });

  group('one source failing does not take the others down', () {
    test('a failed category is named and the rest of the results stand',
        () async {
      final index = await _index(_container(
        _Session(_scoped),
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(_BrokenInventory()),
        ],
      ));

      expect(index.degraded, {AdminDataCategory.inventory});
      expect(index.isFullyDegraded, isFalse);
      expect(_of(index, AdminDataCategory.inventory), isEmpty);
      expect(_of(index, AdminDataCategory.members), isNotEmpty);
      expect(_of(index, AdminDataCategory.shifts), isNotEmpty);
      expect(runSearch(index, _myMember), isNotEmpty);
    });

    test('an offline source with a cached copy is usable data, marked offline',
        () async {
      final index = await _index(_container(
        _Session(_scoped),
        overrides: [
          teamRepositoryProvider.overrideWithValue(_CachedTeam()),
        ],
      ));

      expect(index.offline, isTrue);
      expect(index.degraded, isEmpty);
      expect(
        _of(index, AdminDataCategory.members).map((r) => r.title),
        contains('عضو مخزّن'),
      );
    });

    test('offline with no cached copy is honest rather than "no results"',
        () async {
      final index = await _index(_container(
        _Session(_user(const Capabilities(scoped: {
          _mine: {Cap.memberView}
        }))),
        overrides: [
          teamRepositoryProvider.overrideWithValue(_OfflineTeam()),
          inventoryRepositoryProvider.overrideWithValue(_BrokenInventory()),
        ],
      ));

      // Members is the only category with a source that answered nothing.
      expect(index.offline, isTrue);
      expect(index.degraded, contains(AdminDataCategory.members));
      expect(_of(index, AdminDataCategory.members), isEmpty);
    });
  });
}

// -----------------------------------------------------------------------------
// Fakes. Only the reads Global Search performs are answered; every write throws
// through `noSuchMethod`, because a search screen that called one would be a
// bug worth a loud failure.
// -----------------------------------------------------------------------------

class _BrokenInventory implements InventoryRepository {
  @override
  Future<Result<List<InventoryItem>>> listForDetachment(
          String detachmentId) async =>
      const Failure('تعذّر تحميل المخزن.', code: 'server_error');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CachedTeam implements TeamRepository {
  @override
  Future<Result<List<TeamMember>>> listForDetachment(
          String detachmentId) async =>
      Offline(cached: [
        TeamMember(
          id: 'cached-1',
          name: 'عضو مخزّن',
          initials: TeamMember.initialsOf('عضو مخزّن'),
          role: TeamRole.member,
          detachmentId: detachmentId,
          attendance: AttendanceState.notCheckedIn,
        ),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineTeam implements TeamRepository {
  @override
  Future<Result<List<TeamMember>>> listForDetachment(
          String detachmentId) async =>
      const Offline();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
