import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_presets.dart';
import 'package:mtm/core/access/detachment_access.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/detachment/data/detachment_providers.dart';
import 'package:mtm/features/detachment/domain/detachment_models.dart';

/// The half of the archive a person cannot check by looking.
///
/// Three questions, none of them visual: does the lifecycle filter actually
/// separate finished detachments from running ones, does scope still hold over
/// history, and does the read-only rule close every write key rather than the
/// ones somebody remembered.

/// The seeded archived detachment, and the detachment group it belongs to.
const _archived = 'd_north_arch';
const _archivedGroup = 't_central';

/// A seeded active detachment inside the same detachment group.
const _active = 'd_homs';

AuthUser _user(Capabilities caps) => AuthUser(
      id: 'u',
      name: 'مشرف',
      email: 'admin@mtm.org',
      role: AuthRole.mainAdmin,
      saasTenantId: 'saas_test',
      capabilities: caps,
      orgName: 'MTM',
    );

ProviderContainer _container(AuthUser user) {
  final container = ProviderContainer(
    overrides: [
      currentUserResultProvider.overrideWith(
        (ref) async => Success<AuthUser?>(user),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<List<Detachment>> _list(
  ProviderContainer container,
  DetachmentListQuery query,
) async {
  final result = await container.read(detachmentListProvider(query).future);
  return result.when(
    success: (List<Detachment> data, {bool stale = false}) => data,
    failure: (m, _) => fail('list failed: $m'),
    offline: (cached) => cached ?? const <Detachment>[],
  );
}

DetachmentAccess _access(DetachmentMode mode, {Capabilities? caps}) =>
    DetachmentAccess(
      detachmentId: _archived,
      capabilities: caps ?? const Capabilities(global: Cap.all),
      mode: mode,
    );

void main() {
  group('lifecycle — the archive is the existing domain state, filtered', () {
    test('archived is a real status on the record, not a UI label', () async {
      final container = _container(_user(const Capabilities(global: Cap.all)));
      final result =
          await container.read(detachmentRepositoryProvider).byId(_archived);
      final detachment = result.when(
        success: (Detachment d, {bool stale = false}) => d,
        failure: (m, _) => fail(m),
        offline: (cached) => cached,
      );
      expect(detachment!.status, DetachmentStatus.archived);
    });

    test('the archive list holds finished detachments and only those',
        () async {
      final container = _container(_user(const Capabilities(global: Cap.all)));
      final archive = await _list(
        container,
        const DetachmentListQuery(filter: DetachmentStatus.archived),
      );
      expect(archive.map((d) => d.id), contains(_archived));
      expect(archive.map((d) => d.id), isNot(contains(_active)));
      expect(
        archive.every((d) => d.status == DetachmentStatus.archived),
        isTrue,
      );
    });

    test('the active list never leaks a finished detachment into operations',
        () async {
      final container = _container(_user(const Capabilities(global: Cap.all)));
      final active = await _list(
        container,
        const DetachmentListQuery(filter: DetachmentStatus.active),
      );
      expect(active.map((d) => d.id), isNot(contains(_archived)));
      expect(active.map((d) => d.id), contains(_active));
    });

    test('the archive filter composes with the detachment-group scope',
        () async {
      final container = _container(_user(const Capabilities(global: Cap.all)));
      final inGroup = await _list(
        container,
        const DetachmentListQuery(
          detachmentGroupId: _archivedGroup,
          filter: DetachmentStatus.archived,
        ),
      );
      expect(inGroup.map((d) => d.id), [_archived]);

      final elsewhere = await _list(
        container,
        const DetachmentListQuery(
          detachmentGroupId: 't_damascus',
          filter: DetachmentStatus.archived,
        ),
      );
      expect(elsewhere, isEmpty);
    });

    test('the lifecycle maps onto the mode with no third reading', () async {
      final container = _container(_user(const Capabilities(global: Cap.all)));
      // Held open the way a screen holds it: `detachmentByIdProvider` is
      // autoDispose, so a bare `read` would drop the record the moment it
      // landed and the mode would read `unknown` for the wrong reason.
      for (final id in const [_archived, _active]) {
        container.listen(detachmentByIdProvider(id), (_, __) {});
      }
      await container.read(detachmentByIdProvider(_archived).future);
      await container.read(detachmentByIdProvider(_active).future);
      expect(
        container.read(detachmentModeProvider(_archived)),
        DetachmentMode.historical,
      );
      expect(
        container.read(detachmentModeProvider(_active)),
        DetachmentMode.active,
      );
    });

    test('a detachment that cannot be read denies writes rather than guessing',
        () async {
      final container = _container(_user(const Capabilities(global: Cap.all)));
      final mode = container.read(detachmentModeProvider('no_such_detachment'));
      expect(mode, DetachmentMode.unknown);
      expect(mode.allowsOperationalWrites, isFalse);
    });
  });

  group('scope — history obeys the same security model as live data', () {
    test('a full admin sees the archive; a scoped admin sees only their own',
        () async {
      final full = _container(_user(const Capabilities(global: Cap.all)));
      expect(
        (await _list(
          full,
          const DetachmentListQuery(filter: DetachmentStatus.archived),
        ))
            .map((d) => d.id),
        contains(_archived),
      );

      // Granted a *different* detachment. The archived one is history, which
      // is exactly the argument that must not open it.
      final scoped = _container(
        _user(CapabilityPreset.subAdmin.grant(detachments: const [_active])),
      );
      expect(
        await _list(
          scoped,
          const DetachmentListQuery(filter: DetachmentStatus.archived),
        ),
        isEmpty,
      );
    });

    test('a scoped admin granted the archived detachment does see it',
        () async {
      final scoped = _container(
        _user(CapabilityPreset.subAdmin.grant(detachments: const [_archived])),
      );
      expect(
        (await _list(
          scoped,
          const DetachmentListQuery(filter: DetachmentStatus.archived),
        ))
            .map((d) => d.id),
        [_archived],
      );
    });

    test('a session granted nothing has no archive at all', () async {
      final bare = _container(_user(Capabilities.none));
      expect(
        await _list(
          bare,
          const DetachmentListQuery(filter: DetachmentStatus.archived),
        ),
        isEmpty,
      );
    });
  });

  group('read-only — every write key closes, and only write keys', () {
    test('a finished detachment refuses every operational write capability',
        () {
      final historical = _access(DetachmentMode.historical);
      for (final key in historicallyClosedCapabilities) {
        expect(historical.can(key), isFalse, reason: '$key survived archiving');
      }
      // The same grant, on a running detachment, holds all of them.
      final active = _access(DetachmentMode.active);
      for (final key in historicallyClosedCapabilities) {
        expect(active.can(key), isTrue, reason: '$key was lost while active');
      }
    });

    test('the closed set is exactly the scoped write keys', () {
      // Guards against a capability being added to `Cap.scoped` and quietly
      // staying live on finished records.
      const reads = <String>{
        Cap.detachmentView,
        Cap.memberView,
        Cap.memberContactView,
        Cap.statsView,
        // The lifecycle key itself: it is what undoes archiving, so closing
        // it would make the archive a door with no handle on the inside.
        Cap.detachmentArchive,
      };
      expect(historicallyClosedCapabilities.union(reads), Cap.scoped);
      expect(
        historicallyClosedCapabilities.intersection(reads),
        isEmpty,
      );
    });

    test('reading a finished detachment is untouched', () {
      final historical = _access(DetachmentMode.historical);
      expect(historical.can(Cap.detachmentView), isTrue);
      expect(historical.can(Cap.memberView), isTrue);
      expect(historical.can(Cap.memberContactView), isTrue);
      // Statistics and the report that is a file of them stay open — §13/§14.
      expect(historical.can(Cap.statsView), isTrue);
      // And the lifecycle act that reopens it.
      expect(historical.can(Cap.detachmentArchive), isTrue);
    });

    test('an unknown lifecycle is as closed as a finished one', () {
      final unknown = _access(DetachmentMode.unknown);
      for (final key in historicallyClosedCapabilities) {
        expect(unknown.can(key), isFalse, reason: '$key opened on an unknown');
      }
      expect(unknown.can(Cap.statsView), isTrue);
    });

    test('the lifecycle never grants what the session was not given', () {
      // Read-only is a narrowing, never a widening: an active detachment
      // still refuses a key the grant does not carry.
      final ungranted = _access(
        DetachmentMode.active,
        caps: const Capabilities(scoped: {
          _archived: {Cap.memberView}
        }),
      );
      expect(ungranted.can(Cap.memberView), isTrue);
      expect(ungranted.can(Cap.shiftManage), isFalse);
      expect(ungranted.can(Cap.inventoryAdjust), isFalse);
    });

    test('canAny narrows the two-key routes the same way', () {
      const shiftKeys = Cap.shiftRoute;
      expect(_access(DetachmentMode.active).canAny(shiftKeys), isTrue);
      expect(_access(DetachmentMode.historical).canAny(shiftKeys), isFalse);
    });
  });
}
