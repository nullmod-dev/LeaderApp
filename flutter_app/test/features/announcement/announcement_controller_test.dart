import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/announcement/data/announcement_providers.dart';
import 'package:mtm/features/announcement/domain/announcement_models.dart';
import 'package:mtm/features/announcement/domain/announcement_repository.dart';
import 'package:mtm/features/announcement/domain/announcement_selectors.dart';

/// What the publish and withdraw paths do when something goes wrong, and what
/// they refuse to do at all.
///
/// The interesting cases are all invisible from the screen: a second tap that
/// arrives while the first request is still in flight, a grant that narrows
/// between opening the form and pressing publish, a failed withdraw that must
/// leave the announcement running.

final _now = DateTime(2026, 9, 7, 10);

const _dam = 'd_dam_central';
const _homs = 'd_homs';

/// The archived detachment in the shipped detachment mock. Nothing may be
/// published into it — `announcement.publish` is one of the keys an archived
/// detachment stops honouring.
const _archived = 'd_north_arch';

const _mainAdmin = Capabilities(global: Cap.all);
const _scopedToDam = Capabilities(
  scoped: {
    _dam: {Cap.detachmentView, Cap.announcementPublish},
  },
);
const _reader = Capabilities(
  scoped: {
    _dam: {Cap.detachmentView},
  },
);

/// A repository that counts calls, can be made to fail, and can be held open
/// so a second call arrives while the first is still in flight.
class _FakeRepository implements AnnouncementRepository {
  _FakeRepository();

  final List<Announcement> stored = [];
  int publishCalls = 0;
  int withdrawCalls = 0;

  Result<Announcement>? publishAnswer;
  Result<Announcement>? withdrawAnswer;

  /// Completed by the test to release an in-flight call.
  Completer<void>? gate;

  @override
  Future<Result<List<Announcement>>> list() async => Success(stored);

  @override
  Future<Result<Announcement>> byId(String id) async {
    for (final a in stored) {
      if (a.id == id) return Success(a);
    }
    return const Failure('gone', code: 'not_found');
  }

  @override
  Future<Result<Announcement>> publish({
    required String text,
    required List<String> detachmentIds,
    required Set<AnnouncementPlacement> placements,
    required DateTime publishedAt,
    required DateTime expiresAt,
    String? authorName,
  }) async {
    publishCalls++;
    if (gate != null) await gate!.future;
    final answer = publishAnswer;
    if (answer != null) return answer;
    final record = Announcement(
      id: 'a_$publishCalls',
      text: text.trim(),
      detachmentIds: detachmentIds,
      placements: placements,
      publishedAt: publishedAt,
      expiresAt: expiresAt,
      authorName: authorName,
    );
    stored.add(record);
    return Success(record);
  }

  @override
  Future<Result<Announcement>> withdraw(String id) async {
    withdrawCalls++;
    if (gate != null) await gate!.future;
    final answer = withdrawAnswer;
    if (answer != null) return answer;
    final i = stored.indexWhere((a) => a.id == id);
    if (i < 0) return const Failure('gone', code: 'not_found');
    final stopped = stored[i].copyWith(status: AnnouncementStatus.withdrawn);
    stored[i] = stopped;
    return Success(stopped);
  }
}

/// A capabilities provider a test can narrow mid-session, exactly as the
/// server re-issuing a session would.
class _Grants extends Notifier<Capabilities> {
  _Grants(this._initial);
  final Capabilities _initial;

  @override
  Capabilities build() => _initial;

  void narrowTo(Capabilities next) => state = next;
}

({ProviderContainer container, _FakeRepository repository, _Grants grants})
    _boot({Capabilities capabilities = _mainAdmin}) {
  final repository = _FakeRepository();
  final grants = _Grants(capabilities);
  final grantsProvider = NotifierProvider<_Grants, Capabilities>(() => grants);
  final container = ProviderContainer(overrides: [
    clockProvider.overrideWithValue(() => _now),
    announcementRepositoryProvider.overrideWithValue(repository),
    capabilitiesProvider.overrideWith((ref) => ref.watch(grantsProvider)),
  ]);
  addTearDown(container.dispose);
  // Force the grants notifier to build: a test that narrows the session before
  // ever reading it would otherwise be writing to an uninitialized notifier
  // rather than exercising a mid-session change.
  container.read(capabilitiesProvider);
  return (container: container, repository: repository, grants: grants);
}

Future<AnnouncementOutcome> _publish(
  ProviderContainer container, {
  String text = 'اجتماع المسؤولين غدا الساعة السابعة مساء',
  List<String> targets = const [_dam],
  Set<AnnouncementPlacement> placements = const {
    AnnouncementPlacement.notifications,
  },
  Duration expiresIn = const Duration(hours: 24),
}) =>
    container.read(announcementControllerProvider.notifier).publish(
          text: text,
          detachmentIds: targets,
          placements: placements,
          expiresAt: _now.add(expiresIn),
        );

void main() {
  group('publishing', () {
    test('a valid announcement is stored once', () async {
      final (:container, :repository, :grants) = _boot();
      final outcome = await _publish(container);

      expect(outcome, isA<AnnouncementSaved>());
      expect(repository.publishCalls, 1);
      expect(repository.stored.single.detachmentIds, [_dam]);
      // The canonical placement is on the record whatever the caller passed.
      expect(
        repository.stored.single.placements,
        contains(AnnouncementPlacement.notifications),
      );
    });

    test('the text is trimmed before it is stored', () async {
      final (:container, :repository, :grants) = _boot();
      await _publish(container, text: '   انقطاع الماء عن المركز اليوم   ');
      expect(repository.stored.single.text, 'انقطاع الماء عن المركز اليوم');
    });

    test('publishedAt comes from the injected clock', () async {
      final (:container, :repository, :grants) = _boot();
      await _publish(container);
      expect(repository.stored.single.publishedAt, _now);
    });

    test('duplicate targets reach the repository once', () async {
      final (:container, :repository, :grants) = _boot();
      await _publish(container, targets: const [_dam, _homs, _dam]);
      expect(repository.stored.single.detachmentIds, [_dam, _homs]);
    });

    test('a second publish while the first is in flight sends nothing',
        () async {
      final (:container, :repository, :grants) = _boot();
      repository.gate = Completer<void>();

      final first = _publish(container);
      // The controller is busy; the screen may well still be rebuilding.
      // Busy from the moment the first call passed validation — before it has
      // resolved its targets' lifecycles, let alone reached the repository —
      // which is the point: the guard is the controller's state, not "a
      // request is open".
      final second = await _publish(container);
      expect(second, isA<AnnouncementIgnored>());

      repository.gate!.complete();
      expect(await first, isA<AnnouncementSaved>());
      expect(repository.publishCalls, 1);
      expect(repository.stored, hasLength(1));
    });

    test('the busy guard is released after a failure, so a retry works',
        () async {
      final (:container, :repository, :grants) = _boot();
      repository.publishAnswer = const Failure('server', code: 'server');
      expect(await _publish(container), isA<AnnouncementFailed>());
      expect(
          container.read(announcementControllerProvider).publishing, isFalse);

      repository.publishAnswer = null;
      expect(await _publish(container), isA<AnnouncementSaved>());
      expect(repository.publishCalls, 2);
    });
  });

  group('authorization at submit', () {
    test('a scoped admin cannot publish outside its scope', () async {
      final (:container, :repository, :grants) = _boot(
        capabilities: _scopedToDam,
      );
      final outcome = await _publish(container, targets: const [_dam, _homs]);

      expect(
        outcome,
        isA<AnnouncementRefusedOutcome>().having(
          (o) => o.reason,
          'reason',
          AnnouncementRefusal.unauthorizedTarget,
        ),
      );
      // Refused before anything left the client.
      expect(repository.publishCalls, 0);
    });

    test('a scoped admin publishes inside its scope', () async {
      final (:container, :repository, :grants) = _boot(
        capabilities: _scopedToDam,
      );
      expect(await _publish(container), isA<AnnouncementSaved>());
    });

    test('a grant that narrows while composing blocks the publish', () async {
      final (:container, :repository, :grants) = _boot();
      // The form was built when both detachments were addressable.
      expect(
        publishableDetachments(
            [_dam, _homs], (id) => id, container.read(capabilitiesProvider)),
        [_dam, _homs],
      );

      // The session is re-issued with a narrower grant while the author types.
      grants.narrowTo(_scopedToDam);

      final outcome = await _publish(container, targets: const [_dam, _homs]);
      expect(
        outcome,
        isA<AnnouncementRefusedOutcome>().having(
          (o) => o.reason,
          'reason',
          AnnouncementRefusal.unauthorizedTarget,
        ),
      );
      expect(repository.publishCalls, 0);
    });

    test('a revoked publish key stops publishing entirely', () async {
      final (:container, :repository, :grants) = _boot(
        capabilities: _scopedToDam,
      );
      grants.narrowTo(_reader);
      expect(container.read(canPublishAnnouncementsProvider), isFalse);
      expect(await _publish(container), isA<AnnouncementRefusedOutcome>());
      expect(repository.publishCalls, 0);
    });

    test('an archived detachment cannot be newly targeted', () async {
      // The picker is built from the active-filtered list and never offers
      // `d_north_arch`. This is the *action* refusing it — the bypass a direct
      // call, a stale form or a deep link would otherwise have.
      final (:container, :repository, :grants) = _boot();
      final outcome = await _publish(container, targets: const [_archived]);

      expect(
        outcome,
        isA<AnnouncementRefusedOutcome>().having(
          (o) => o.reason,
          'reason',
          AnnouncementRefusal.archivedTarget,
        ),
      );
      expect(repository.publishCalls, 0);
    });

    test('one archived detachment among active ones refuses the whole publish',
        () async {
      final (:container, :repository, :grants) = _boot();
      final outcome =
          await _publish(container, targets: const [_dam, _archived]);

      expect(outcome, isA<AnnouncementRefusedOutcome>());
      expect(repository.publishCalls, 0);
      expect(repository.stored, isEmpty);
    });

    test('a target whose record cannot be read is refused, never assumed open',
        () async {
      final (:container, :repository, :grants) = _boot();
      final outcome = await _publish(container, targets: const ['d_nowhere']);

      expect(
        outcome,
        isA<AnnouncementRefusedOutcome>().having(
          (o) => o.reason,
          'reason',
          AnnouncementRefusal.archivedTarget,
        ),
      );
      expect(repository.publishCalls, 0);
    });

    test('calling the controller directly cannot bypass the checks', () async {
      // No screen was involved and no button was disabled — the guard is in
      // the controller, which is the whole point.
      final (:container, :repository, :grants) = _boot(capabilities: _reader);
      expect(
        await _publish(container, targets: const [_dam, _homs]),
        isA<AnnouncementRefusedOutcome>(),
      );
      expect(repository.publishCalls, 0);
    });

    test('canAnywhere is what the entry points ask', () {
      final (:container, :repository, :grants) = _boot(
        capabilities: _scopedToDam,
      );
      // The scoped admin holds nothing globally, so the org-level question
      // would refuse them — and it would be the wrong question.
      expect(
        container
            .read(capabilitiesProvider)
            .canIn(null, Cap.announcementPublish),
        isFalse,
      );
      expect(container.read(canPublishAnnouncementsProvider), isTrue);
    });
  });

  group('refusals keep the author\'s work', () {
    test('empty text is refused with a reason, nothing is sent', () async {
      final (:container, :repository, :grants) = _boot();
      expect(
        await _publish(container, text: '   '),
        isA<AnnouncementRefusedOutcome>().having(
          (o) => o.reason,
          'reason',
          AnnouncementRefusal.emptyText,
        ),
      );
      expect(repository.publishCalls, 0);
    });

    test('an expiry that is not in the future is refused', () async {
      final (:container, :repository, :grants) = _boot();
      expect(
        await _publish(container, expiresIn: const Duration(hours: -1)),
        isA<AnnouncementRefusedOutcome>().having(
          (o) => o.reason,
          'reason',
          AnnouncementRefusal.expiryNotInFuture,
        ),
      );
      expect(repository.publishCalls, 0);
    });

    test('no target at all is refused', () async {
      final (:container, :repository, :grants) = _boot();
      expect(
        await _publish(container, targets: const []),
        isA<AnnouncementRefusedOutcome>().having(
          (o) => o.reason,
          'reason',
          AnnouncementRefusal.noTarget,
        ),
      );
    });
  });

  group('offline and failure', () {
    test('offline is reported honestly and nothing is queued', () async {
      final (:container, :repository, :grants) = _boot();
      repository.publishAnswer = const Offline();
      expect(await _publish(container), isA<AnnouncementOffline>());
      // No announcement stored, and — deliberately — no outbox operation
      // created: there is no endpoint a queued write could ever reach.
      expect(repository.stored, isEmpty);
    });

    test('a publish failure stores nothing', () async {
      final (:container, :repository, :grants) = _boot();
      repository.publishAnswer = const Failure('تعذّر النشر.', code: 'server');
      final outcome = await _publish(container);
      expect(
        outcome,
        isA<AnnouncementFailed>().having((o) => o.code, 'code', 'server'),
      );
      expect(repository.stored, isEmpty);
    });
  });

  group('withdrawing', () {
    Future<Announcement> seed(
        ProviderContainer container, _FakeRepository repository) async {
      await _publish(container);
      return repository.stored.single;
    }

    test('withdrawing stops the announcement without deleting it', () async {
      final (:container, :repository, :grants) = _boot();
      final a = await seed(container, repository);

      final outcome = await container
          .read(announcementControllerProvider.notifier)
          .withdraw(a.id);

      expect(outcome, isA<AnnouncementSaved>());
      expect(repository.stored, hasLength(1));
      expect(repository.stored.single.status, AnnouncementStatus.withdrawn);
      // The record is still there to be history.
      expect(repository.stored.single.text, a.text);
    });

    test('a second withdraw while the first is in flight sends nothing',
        () async {
      final (:container, :repository, :grants) = _boot();
      final a = await seed(container, repository);
      repository.gate = Completer<void>();

      final notifier = container.read(announcementControllerProvider.notifier);
      final first = notifier.withdraw(a.id);
      expect(await notifier.withdraw(a.id), isA<AnnouncementIgnored>());
      expect(repository.withdrawCalls, 1);

      repository.gate!.complete();
      await first;
      expect(repository.withdrawCalls, 1);
    });

    test('a failed withdraw leaves the announcement active', () async {
      final (:container, :repository, :grants) = _boot();
      final a = await seed(container, repository);
      repository.withdrawAnswer = const Failure('تعذّر', code: 'server');

      expect(
        await container
            .read(announcementControllerProvider.notifier)
            .withdraw(a.id),
        isA<AnnouncementFailed>(),
      );
      expect(repository.stored.single.status, AnnouncementStatus.active);
      expect(isAnnouncementActive(repository.stored.single, _now), isTrue);
      // And the guard is released, so the retry is possible.
      expect(
          container.read(announcementControllerProvider).withdrawing, isNull);
    });

    test('withdrawing something that is gone fails safely', () async {
      final (:container, :repository, :grants) = _boot();
      expect(
        await container
            .read(announcementControllerProvider.notifier)
            .withdraw('a_missing'),
        isA<AnnouncementFailed>().having((o) => o.code, 'code', 'not_found'),
      );
    });
  });

  group('withdraw authorization', () {
    /// Stores an announcement addressed to [targets] without going through the
    /// controller — the state a management list would have been built from.
    Announcement seedFor(_FakeRepository repository, List<String> targets) {
      final record = Announcement(
        id: 'a_seeded',
        text: 'إعلان مفرزة أخرى',
        detachmentIds: targets,
        placements: const {AnnouncementPlacement.notifications},
        publishedAt: _now,
        expiresAt: _now.add(const Duration(hours: 12)),
      );
      repository.stored.add(record);
      return record;
    }

    test('a scoped admin cannot withdraw another detachment\'s announcement',
        () async {
      // The row is never rendered for this session, but a row is a view. An id
      // is the one thing a caller supplies freely, so the action re-reads the
      // record and authorizes it.
      final (:container, :repository, :grants) =
          _boot(capabilities: _scopedToDam);
      final a = seedFor(repository, const [_homs]);

      final outcome = await container
          .read(announcementControllerProvider.notifier)
          .withdraw(a.id);

      expect(
        outcome,
        isA<AnnouncementRefusedOutcome>().having(
          (o) => o.reason,
          'reason',
          AnnouncementRefusal.unauthorizedTarget,
        ),
      );
      expect(repository.withdrawCalls, 0);
      expect(repository.stored.single.status, AnnouncementStatus.active);
    });

    test('a reader with no publish key anywhere cannot withdraw', () async {
      final (:container, :repository, :grants) = _boot(capabilities: _reader);
      final a = seedFor(repository, const [_dam]);

      expect(
        await container
            .read(announcementControllerProvider.notifier)
            .withdraw(a.id),
        isA<AnnouncementRefusedOutcome>(),
      );
      expect(repository.withdrawCalls, 0);
    });

    test('holding the key in one of several targets is enough', () async {
      final (:container, :repository, :grants) =
          _boot(capabilities: _scopedToDam);
      final a = seedFor(repository, const [_homs, _dam]);

      expect(
        await container
            .read(announcementControllerProvider.notifier)
            .withdraw(a.id),
        isA<AnnouncementSaved>(),
      );
      expect(repository.stored.single.status, AnnouncementStatus.withdrawn);
    });

    test('a grant narrowed after the list was drawn blocks the withdraw',
        () async {
      final (:container, :repository, :grants) = _boot();
      final a = seedFor(repository, const [_homs]);
      grants.narrowTo(_scopedToDam);

      expect(
        await container
            .read(announcementControllerProvider.notifier)
            .withdraw(a.id),
        isA<AnnouncementRefusedOutcome>(),
      );
      expect(repository.withdrawCalls, 0);
      // And the guard is released, so a legitimate withdraw still works.
      expect(
          container.read(announcementControllerProvider).withdrawing, isNull);
    });
  });
}
