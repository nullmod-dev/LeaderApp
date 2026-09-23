import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/features/announcement/domain/announcement_models.dart';
import 'package:mtm/features/detachment/domain/detachment_models.dart';
import 'package:mtm/features/announcement/domain/announcement_selectors.dart';

/// The rules of the announcement system, against a pinned clock.
///
/// Everything here is a boundary somebody will cross at exactly the wrong
/// second: the one-hour Home promotion, the expiry, the target list a narrowing
/// grant just shortened. None of it is reproducible by tapping the screen —
/// which is why it is tested here and the layout is not tested at all.

final _now = DateTime(2026, 9, 7, 10);

const _dam = 'd_dam_central';
const _homs = 'd_homs';
const _coast = 'd_coast';

/// Publishes everywhere. What the shipped mock session holds.
const _mainAdmin = Capabilities(global: Cap.all);

/// Publishes in Damascus only, and cannot even see the coast.
const _scoped = Capabilities(
  scoped: {
    _dam: {Cap.detachmentView, Cap.announcementPublish},
  },
);

/// Sees Damascus, may not publish anywhere.
const _reader = Capabilities(
  scoped: {
    _dam: {Cap.detachmentView},
  },
);

Announcement _a(
  String id, {
  List<String> targets = const [_dam],
  Set<AnnouncementPlacement> placements = const {
    AnnouncementPlacement.notifications,
  },
  Duration publishedAgo = const Duration(minutes: 5),
  Duration expiresIn = const Duration(hours: 24),
  AnnouncementStatus status = AnnouncementStatus.active,
}) =>
    Announcement(
      id: id,
      text: 'نص الإعلان',
      detachmentIds: targets,
      placements: placements,
      publishedAt: _now.subtract(publishedAgo),
      expiresAt: _now.add(expiresIn),
      status: status,
    );

void main() {
  group('the one-hour Home promotion', () {
    const onHome = {
      AnnouncementPlacement.notifications,
      AnnouncementPlacement.home,
    };

    test('a just-published announcement is promoted immediately', () {
      final a = _a('a', placements: onHome, publishedAgo: Duration.zero);
      expect(isPromotedOnHome(a, _now), isTrue);
    });

    test('still promoted at +59m59s', () {
      final a = _a(
        'a',
        placements: onHome,
        publishedAgo: const Duration(minutes: 59, seconds: 59),
      );
      expect(isPromotedOnHome(a, _now), isTrue);
    });

    test('no longer promoted at exactly +1h — the boundary is half-open', () {
      final a = _a('a', placements: onHome, publishedAgo: homePromotionWindow);
      expect(isPromotedOnHome(a, _now), isFalse);
    });

    test('an announcement without the Home placement is never promoted', () {
      final a = _a('a', publishedAgo: Duration.zero);
      expect(isPromotedOnHome(a, _now), isFalse);
    });

    test('a withdrawn announcement leaves Home even inside its first hour', () {
      final a = _a(
        'a',
        placements: onHome,
        publishedAgo: const Duration(minutes: 10),
        status: AnnouncementStatus.withdrawn,
      );
      expect(isPromotedOnHome(a, _now), isFalse);
    });

    test('a lifetime shorter than an hour ends the promotion with it', () {
      // Published 40 minutes ago with a 30-minute lifetime: inside the hour,
      // past the expiry. The expiry wins.
      final a = Announcement(
        id: 'a',
        text: 'نص',
        detachmentIds: const [_dam],
        placements: onHome,
        publishedAt: _now.subtract(const Duration(minutes: 40)),
        expiresAt: _now.subtract(const Duration(minutes: 10)),
      );
      expect(isPromotedOnHome(a, _now), isFalse);
      expect(homePromotionEndsAt(a), a.expiresAt);
    });

    test('the promotion ends an hour after publication, not after expiry', () {
      final a = _a(
        'a',
        placements: onHome,
        publishedAgo: Duration.zero,
        expiresIn: const Duration(days: 2),
      );
      expect(homePromotionEndsAt(a), _now.add(homePromotionWindow));
    });

    test('losing the Home promotion does not end the announcement', () {
      final a = _a(
        'a',
        placements: onHome,
        publishedAgo: const Duration(hours: 4),
      );
      expect(isPromotedOnHome(a, _now), isFalse);
      // Still live, still addressed to the detachment: the Notifications
      // Center row is built from exactly this.
      expect(isAnnouncementActive(a, _now), isTrue);
      expect(a.targets(_dam), isTrue);
    });

    test('one card is chosen deterministically when several are promoted', () {
      final older = _a(
        'a_older',
        placements: onHome,
        publishedAgo: const Duration(minutes: 30),
      );
      final newer = _a(
        'a_newer',
        placements: onHome,
        publishedAgo: const Duration(minutes: 5),
      );
      final rows = homeAnnouncementsFor(
        [older, newer],
        detachmentId: _dam,
        now: _now,
      );
      expect(rows.map((a) => a.id), ['a_newer', 'a_older']);
    });

    test('a tie on publication time breaks on id, so the card cannot flicker',
        () {
      final a = _a('a_b', placements: onHome, publishedAgo: Duration.zero);
      final b = _a('a_a', placements: onHome, publishedAgo: Duration.zero);
      expect(
        homeAnnouncementsFor([a, b], detachmentId: _dam, now: _now)
            .map((x) => x.id),
        ['a_a', 'a_b'],
      );
      // And the reverse input order gives the same answer.
      expect(
        homeAnnouncementsFor([b, a], detachmentId: _dam, now: _now)
            .map((x) => x.id),
        ['a_a', 'a_b'],
      );
    });
  });

  group('expiry', () {
    test('an expired announcement has no active placement anywhere', () {
      final a = Announcement(
        id: 'a',
        text: 'نص',
        detachmentIds: const [_dam],
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.home,
          AnnouncementPlacement.detachment,
        },
        publishedAt: _now.subtract(const Duration(days: 3)),
        expiresAt: _now.subtract(const Duration(days: 2)),
      );
      expect(isAnnouncementActive(a, _now), isFalse);
      expect(isPromotedOnHome(a, _now), isFalse);
      expect(
        detachmentAnnouncementsFor([a], detachmentId: _dam, now: _now),
        isEmpty,
      );
    });

    test('an expired announcement is still visible history', () {
      final a = _a('a', expiresIn: const Duration(hours: -1));
      expect(
        visibleAnnouncements([a], detachmentId: _dam, capabilities: _reader)
            .map((x) => x.id),
        ['a'],
      );
    });

    test('reopening later re-evaluates from the clock alone', () {
      final a = _a(
        'a',
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.home,
        },
        publishedAgo: Duration.zero,
        expiresIn: const Duration(hours: 6),
      );
      expect(isPromotedOnHome(a, _now), isTrue);
      // The app was closed and reopened two hours on. No timer ran.
      final later = _now.add(const Duration(hours: 2));
      expect(isPromotedOnHome(a, later), isFalse);
      expect(isAnnouncementActive(a, later), isTrue);
      // And a day on, it is history everywhere.
      final tomorrow = _now.add(const Duration(days: 1));
      expect(isAnnouncementActive(a, tomorrow), isFalse);
    });

    test('the detachment placement lasts until expiry, not one hour', () {
      final a = _a(
        'a',
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.detachment,
        },
        publishedAgo: const Duration(hours: 5),
      );
      expect(isPromotedOnHome(a, _now), isFalse);
      expect(
        detachmentAnnouncementsFor([a], detachmentId: _dam, now: _now)
            .map((x) => x.id),
        ['a'],
      );
    });

    test('withdrawal stops the detachment placement too', () {
      final a = _a(
        'a',
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.detachment,
        },
        status: AnnouncementStatus.withdrawn,
      );
      expect(
        detachmentAnnouncementsFor([a], detachmentId: _dam, now: _now),
        isEmpty,
      );
      // But not the history.
      expect(
        visibleAnnouncements([a], detachmentId: _dam, capabilities: _reader),
        hasLength(1),
      );
    });
  });

  group('addressing and scope', () {
    test('an announcement reaches every detachment it names', () {
      final a = _a('a', targets: const [_dam, _homs]);
      expect(
        visibleAnnouncements([a],
            detachmentId: _homs, capabilities: _mainAdmin),
        hasLength(1),
      );
    });

    test('a session that cannot see the detachment sees no announcement', () {
      final a = _a('a', targets: const [_coast]);
      expect(
        visibleAnnouncements([a], detachmentId: _coast, capabilities: _scoped),
        isEmpty,
      );
    });

    test('a reader with no publish key still sees announcements', () {
      final a = _a('a');
      expect(
        visibleAnnouncements([a], detachmentId: _dam, capabilities: _reader),
        hasLength(1),
      );
    });

    test('the target list is narrowed to detachments the key covers', () {
      final ids = [_dam, _homs, _coast];
      expect(
        publishableDetachments(ids, (id) => id, _scoped),
        [_dam],
      );
      expect(
        publishableDetachments(ids, (id) => id, _mainAdmin),
        ids,
      );
      expect(publishableDetachments(ids, (id) => id, _reader), isEmpty);
    });

    test('duplicate targets collapse, order preserved', () {
      expect(dedupeTargets([_dam, _homs, _dam, _homs]), [_dam, _homs]);
    });

    test('authorizedTargets drops what the grant no longer covers', () {
      expect(authorizedTargets([_dam, _homs], _scoped), [_dam]);
    });

    test('acting on an announcement needs the key in one of its targets', () {
      final multi = _a('a1', targets: const [_homs, _dam]);
      final elsewhere = _a('a2', targets: const [_homs]);

      expect(canManageAnnouncement(multi, _scoped), isTrue);
      expect(canManageAnnouncement(elsewhere, _scoped), isFalse);
      expect(canManageAnnouncement(elsewhere, _mainAdmin), isTrue);
      // Reading a detachment is not acting on its notices.
      expect(canManageAnnouncement(multi, _reader), isFalse);
    });
  });

  group('archived targets', () {
    test('an active target passes', () {
      expect(
        refuseArchivedTargets(
          const [_dam],
          const {_dam: DetachmentStatus.active},
        ),
        isNull,
      );
    });

    test('one archived target refuses the whole publish', () {
      expect(
        refuseArchivedTargets(
          const [_dam, _homs],
          const {
            _dam: DetachmentStatus.active,
            _homs: DetachmentStatus.archived,
          },
        ),
        AnnouncementRefusal.archivedTarget,
      );
    });

    test('a target whose record could not be read is not assumed active', () {
      expect(
        refuseArchivedTargets(const [_dam], const {_dam: null}),
        AnnouncementRefusal.archivedTarget,
      );
      expect(
        refuseArchivedTargets(const [_dam], const {}),
        AnnouncementRefusal.archivedTarget,
      );
    });
  });

  group('publish validation', () {
    DateTime tomorrow() => _now.add(const Duration(days: 1));

    AnnouncementRefusal? refuse({
      String text = 'اجتماع المسؤولين غدا الساعة السابعة',
      List<String> targets = const [_dam],
      DateTime? expiresAt,
      Capabilities capabilities = _mainAdmin,
    }) =>
        refuseAnnouncement(
          text: text,
          detachmentIds: targets,
          expiresAt: expiresAt ?? tomorrow(),
          now: _now,
          capabilities: capabilities,
        );

    test('a valid announcement is not refused', () {
      expect(refuse(), isNull);
    });

    test('whitespace-only text is refused as empty', () {
      expect(refuse(text: '   \n  '), AnnouncementRefusal.emptyText);
    });

    test('text under the minimum is refused', () {
      expect(refuse(text: 'نعم'), AnnouncementRefusal.textTooShort);
    });

    test('text over the maximum is refused', () {
      expect(
        refuse(text: 'ا' * (announcementTextMax + 1)),
        AnnouncementRefusal.textTooLong,
      );
    });

    test('text is measured after trimming, so padding does not smuggle length',
        () {
      expect(refuse(text: '  ${'ا' * announcementTextMin}  '), isNull);
    });

    test('at least one target is always required', () {
      expect(refuse(targets: const []), AnnouncementRefusal.noTarget);
    });

    test('a target outside the grant is refused', () {
      expect(
        refuse(targets: const [_dam, _homs], capabilities: _scoped),
        AnnouncementRefusal.unauthorizedTarget,
      );
    });

    test('a scoped admin publishing inside its own scope is allowed', () {
      expect(refuse(targets: const [_dam], capabilities: _scoped), isNull);
    });

    test('a session with no publish key is refused whatever it selected', () {
      expect(
        refuse(capabilities: _reader),
        AnnouncementRefusal.unauthorizedTarget,
      );
    });

    test('duplicated targets do not defeat the authorization check', () {
      // Deduped first, then checked: three entries collapsing to two must not
      // make a count comparison pass by accident.
      expect(
        refuse(targets: const [_dam, _dam, _homs], capabilities: _scoped),
        AnnouncementRefusal.unauthorizedTarget,
      );
    });

    test('an expiry in the past is refused', () {
      expect(
        refuse(expiresAt: _now.subtract(const Duration(minutes: 1))),
        AnnouncementRefusal.expiryNotInFuture,
      );
    });

    test('an expiry exactly now is refused — there is no zero-length notice',
        () {
      expect(refuse(expiresAt: _now), AnnouncementRefusal.expiryNotInFuture);
    });
  });

  group('placements', () {
    test('the Notifications Center is always included', () {
      expect(resolvePlacements(), {AnnouncementPlacement.notifications});
      expect(
        resolvePlacements(onHome: true, onDetachment: true),
        AnnouncementPlacement.values.toSet(),
      );
    });
  });

  group('the management list', () {
    test('active announcements sort above finished ones, newest first', () {
      final expired = _a('a_expired', expiresIn: const Duration(hours: -1));
      final oldActive = _a('a_old', publishedAgo: const Duration(hours: 6));
      final newActive = _a('a_new', publishedAgo: const Duration(minutes: 2));
      final withdrawn = _a(
        'a_withdrawn',
        publishedAgo: const Duration(minutes: 1),
        status: AnnouncementStatus.withdrawn,
      );

      expect(
        manageableAnnouncements(
          [expired, oldActive, withdrawn, newActive],
          _now,
        ).map((a) => a.id),
        ['a_new', 'a_old', 'a_withdrawn', 'a_expired'],
      );
    });
  });
}
