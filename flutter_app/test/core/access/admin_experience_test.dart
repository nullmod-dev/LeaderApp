import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/admin_experience.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_presets.dart';

/// The admin-experience resolver: how broad a session's UI is, and — the part
/// that has to be right — that deciding so never grants anything.
///
/// Everything here is pure. The router's half of the same question (a deep
/// link past a hidden destination) is
/// `test/features/auth/admin_experience_routes_test.dart`.

const _d1 = 'd1';
const _d2 = 'd2';

/// A main admin as the mock issues one: every key, organisation-wide.
const _fullGrant = Capabilities(global: Cap.all);

/// A sub-Admin over one detachment, built from the shipped preset rather than
/// a hand-written key list — if the preset changes, this test changes with it
/// instead of quietly testing a fiction.
final _subAdmin = CapabilityPreset.subAdmin.grant(detachments: const [_d1]);

/// A volunteer's two keys, scoped to one detachment.
final _volunteer = CapabilityPreset.volunteer.grant(detachments: const [_d1]);

void main() {
  group('experience classification', () {
    test('a full-capability account resolves to the full experience', () {
      final view = AdminView.of(_fullGrant);
      expect(view.experience, AdminExperience.full);
      expect(view.isFull, isTrue);
      expect(view.managesAdmins, isTrue);
      expect(view.editsOrganisation, isTrue);
      expect(view.organisationWideDetachments, isTrue);
    });

    test('a scoped account resolves to the scoped experience', () {
      final view = AdminView.of(_subAdmin);
      expect(view.experience, AdminExperience.scoped);
      expect(view.managesAdmins, isFalse);
      expect(view.editsOrganisation, isFalse);
      expect(view.createsContainers, isFalse);
      expect(view.organisationWideDetachments, isFalse);
      expect(view.namedDetachmentIds, [_d1]);
    });

    test('each of the three administration keys alone is enough', () {
      // The documented mapping, asserted key by key so it cannot drift into
      // "whatever the sub-admin preset happens not to hold".
      for (final key in [Cap.adminManage, Cap.orgEdit, Cap.detachmentCreate]) {
        expect(
          AdminView.of(Capabilities(global: {key})).experience,
          AdminExperience.full,
          reason: '$key should carry the full experience',
        );
      }
    });

    test('operational breadth alone is not the full experience', () {
      // A sub-Admin holds every operational key in a detachment and five
      // organisation-level workshop keys. Breadth of *work* is not
      // administration of the organisation, and must not read as it.
      expect(AdminView.of(_subAdmin).workshops, isTrue);
      expect(AdminView.of(_subAdmin).isFull, isFalse);
    });

    test('an unknown capability state is scoped, never full', () {
      // The state every cold start passes through, and the one a failed
      // capability read leaves behind. Failing open here would hand the broad
      // experience to a session whose grant never arrived.
      final view = AdminView.none;
      expect(view.experience, AdminExperience.scoped);
      expect(view.managesAdmins, isFalse);
      expect(view.workshops, isFalse);
      expect(view.hasNoDetachment, isTrue);
      expect(AdminView.of(Capabilities.none), view);
    });
  });

  group('classification grants nothing', () {
    test('the full experience does not answer a capability check', () {
      // `admin.manage` withheld, everything else global: broad enough to be
      // the full experience, and still not an admin manager.
      final caps = Capabilities(
          global: Cap.all.difference(const {
        Cap.adminManage,
      }));
      final view = AdminView.of(caps);
      expect(view.isFull, isTrue, reason: 'org.edit alone carries it');
      expect(view.managesAdmins, isFalse);
      expect(view.capabilities.can(Cap.adminManage), isFalse);
    });

    test('the scoped experience does not withhold a granted capability', () {
      // The inverse failure: a scoped label must not become a second, quieter
      // gate that removes something the server actually granted.
      const caps = Capabilities(scoped: {
        _d1: {Cap.shiftManage, Cap.memberView}
      });
      final view = AdminView.of(caps);
      expect(view.isScoped, isTrue);
      expect(view.capabilities.canIn(_d1, Cap.shiftManage), isTrue);
      expect(view.capabilities.canIn(_d1, Cap.memberView), isTrue);
    });
  });

  group('detachment scope', () {
    test('an organisation-wide grant covers every id, named or not', () {
      final view = AdminView.of(_fullGrant);
      expect(view.coversDetachment('anything-at-all'), isTrue);
      expect(view.namedDetachmentIds, isEmpty);
      expect(view.hasNoDetachment, isFalse);
      expect(view.hasSingleDetachment, isFalse);
    });

    test('a scoped grant covers only what it names', () {
      final view = AdminView.of(_subAdmin);
      expect(view.coversDetachment(_d1), isTrue);
      expect(view.coversDetachment(_d2), isFalse);
      expect(view.hasSingleDetachment, isTrue);
    });

    test('any scoped grant implies seeing that detachment', () {
      // `CAPABILITIES.md` §4/Q3 — a grant inside a detachment implies the
      // right to see it, without a second `detachment.view`.
      final view = AdminView.of(const Capabilities(scoped: {
        _d2: {Cap.shiftManage}
      }));
      expect(view.coversDetachment(_d2), isTrue);
      expect(view.coversDetachment(_d1), isFalse);
    });

    test('the list filter narrows to scope and keeps order', () {
      final ids = [_d1, _d2, 'd3'];
      expect(
        visibleDetachments(AdminView.of(_fullGrant), ids, (id) => id),
        ids,
      );
      expect(
        visibleDetachments(
          AdminView.of(const Capabilities(scoped: {
            'd3': {Cap.memberView},
            _d1: Cap.scoped,
          })),
          ids,
          (id) => id,
        ),
        [_d1, 'd3'],
      );
      expect(
        visibleDetachments(AdminView.none, ids, (id) => id),
        isEmpty,
      );
    });
  });

  group('the Global Search scope seam', () {
    test('a full grant may search every category', () {
      expect(
        AdminView.of(_fullGrant).searchableCategories,
        AdminDataCategory.values.toSet(),
      );
    });

    test('a scoped grant may search only inside what it holds', () {
      final view = AdminView.of(_subAdmin);
      expect(view.categoriesIn(_d1), {
        AdminDataCategory.detachments,
        AdminDataCategory.shifts,
        AdminDataCategory.inventory,
        AdminDataCategory.members,
        AdminDataCategory.statistics,
        AdminDataCategory.workshops,
      });
      // Outside its scope only the organisation-level category survives —
      // workshops carry no detachment, so they are not narrowed by one.
      expect(view.categoriesIn(_d2), {AdminDataCategory.workshops});
    });

    test('statistics is its own category, not implied by membership', () {
      // A volunteer sees the schedule and the store from membership alone,
      // and must still not be searching performance data about named people.
      final view = AdminView.of(_volunteer);
      expect(view.categoriesIn(_d1), contains(AdminDataCategory.shifts));
      expect(view.categoriesIn(_d1), contains(AdminDataCategory.inventory));
      expect(view.categoriesIn(_d1), contains(AdminDataCategory.members));
      expect(
        view.categoriesIn(_d1),
        isNot(contains(AdminDataCategory.statistics)),
      );
      expect(
        view.categoriesIn(_d1),
        isNot(contains(AdminDataCategory.workshops)),
      );
    });

    test('a session granted nothing may search nothing', () {
      expect(AdminView.none.searchableCategories, isEmpty);
    });
  });

  group('inventory capability variants', () {
    // The three real outcomes §11 asks for, stated against the two keys the
    // domain actually has. The seam is the capability check; nothing about the
    // experience label changes any of them.
    test('view-only, adjust-only and manage are three different grants', () {
      final viewOnly = AdminView.of(const Capabilities(scoped: {
        _d1: {Cap.detachmentView}
      }));
      final adjustOnly = AdminView.of(const Capabilities(scoped: {
        _d1: {Cap.inventoryAdjust}
      }));
      final manage = AdminView.of(const Capabilities(scoped: {
        _d1: {Cap.inventoryAdjust, Cap.inventoryItemManage}
      }));

      // Seeing the store follows membership, so all three reach the tab.
      for (final view in [viewOnly, adjustOnly, manage]) {
        expect(view.coversDetachment(_d1), isTrue);
        expect(view.categoriesIn(_d1), contains(AdminDataCategory.inventory));
      }
      expect(viewOnly.capabilities.canIn(_d1, Cap.inventoryAdjust), isFalse);
      expect(adjustOnly.capabilities.canIn(_d1, Cap.inventoryAdjust), isTrue);
      expect(
        adjustOnly.capabilities.canIn(_d1, Cap.inventoryItemManage),
        isFalse,
      );
      expect(manage.capabilities.canIn(_d1, Cap.inventoryItemManage), isTrue);
    });
  });
}
