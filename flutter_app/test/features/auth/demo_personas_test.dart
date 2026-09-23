import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/admin_experience.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/features/auth/data/dev_test_credentials.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';

/// Point 2 — the three development personas.
///
/// What is worth testing here is not the names. It is that the three are
/// *actually* three different things: that Main and Simple share one paying
/// customer, that Simple is genuinely narrower rather than differently
/// labelled, and that Super Admin has not quietly been handed the tenant
/// application through its grant. Every one of those is a mistake that would
/// look correct on screen for a while.

void main() {
  group('identity', () {
    test('Super Admin is the platform owner and is in no SaasTenant', () {
      final user = DemoPersona.superAdmin.user;
      expect(user.role, AuthRole.superAdmin);
      expect(user.saasTenantId, isNull);
      expect(user.isWellFormed, isTrue);
      expect(user.id, 'u_demo_platform');
    });

    test('Main Admin leads one SaasTenant', () {
      final user = DemoPersona.mainAdmin.user;
      expect(user.role, AuthRole.mainAdmin);
      expect(user.saasTenantId, kDemoSaasTenantId);
      expect(user.isWellFormed, isTrue);
      expect(user.id, 'u_demo_main');
    });

    test('Simple Admin is a sub-admin, not a second Main Admin', () {
      final user = DemoPersona.simpleAdmin.user;
      expect(user.role, AuthRole.admin);
      expect(user.saasTenantId, kDemoSaasTenantId);
      expect(user.isWellFormed, isTrue);
      expect(user.id, 'u_demo_simple');
    });

    test('Main Admin and Simple Admin are two admins of ONE customer', () {
      // The single most important assertion in this file. If these ever
      // diverge, every scoping demonstration built on the pair becomes a
      // demonstration of two separate tenants instead.
      expect(
        DemoPersona.simpleAdmin.user.saasTenantId,
        DemoPersona.mainAdmin.user.saasTenantId,
      );
      expect(DemoPersona.mainAdmin.user.saasTenantId, isNotNull);
    });

    test('the three personas have distinct ids, emails and persona keys', () {
      final users = DemoPersona.values.map((p) => p.user).toList();
      expect(users.map((u) => u.id).toSet(), hasLength(3));
      expect(users.map((u) => u.email).toSet(), hasLength(3));
      expect(DemoPersona.values.map((p) => p.wire).toSet(), hasLength(3));
    });

    test('every persona is stable across reads', () {
      // No randomness, no clock: a persona restored after a restart must be
      // the same account it was before one.
      expect(DemoPersona.mainAdmin.user.id, DemoPersona.mainAdmin.user.id);
      expect(
        DemoPersona.simpleAdmin.user.capabilities,
        DemoPersona.simpleAdmin.user.capabilities,
      );
    });
  });

  group('development identity lookup', () {
    test('parse maps a stored key back to its persona', () {
      for (final persona in DemoPersona.values) {
        expect(DemoPersona.parse(persona.wire), persona);
      }
      expect(DemoPersona.parse('main_admin'), isNull);
      expect(DemoPersona.parse(null), isNull);
      expect(DemoPersona.parse(''), isNull);
    });

    test('DevTestCredentials owns the deterministic typed-login table', () {
      for (final credential in DevTestCredentials.values) {
        expect(
          DevTestCredentials.forEmail(credential.email),
          credential,
        );
        expect(credential.password, isNotEmpty);
      }
      // Trimmed and case-insensitive, because a soft keyboard is neither.
      expect(
        DevTestCredentials.forEmail('  PBEA4007@MTU.edu.iq '),
        DevTestCredentials.mainAdmin,
      );
      expect(DevTestCredentials.forEmail('someone@else.org'), isNull);
      expect(DevTestCredentials.forEmail(''), isNull);
    });
  });

  group('capabilities differ as intended', () {
    final main = DemoPersona.mainAdmin.user.capabilities;
    final simple = DemoPersona.simpleAdmin.user.capabilities;

    test('Main Admin holds the full tenant grant, organisation-wide', () {
      expect(main.global, containsAll(Cap.all));
      expect(AdminView.of(main).experience, AdminExperience.full);
      expect(AdminView.of(main).organisationWideDetachments, isTrue);
    });

    test('Simple Admin is scoped to its two named detachments only', () {
      final view = AdminView.of(simple);
      expect(view.experience, AdminExperience.scoped);
      expect(view.organisationWideDetachments, isFalse);
      expect(view.namedDetachmentIds, kDemoSimpleAdminDetachments);

      for (final id in kDemoSimpleAdminDetachments) {
        expect(view.coversDetachment(id), isTrue);
      }
      // A detachment it was not granted stays invisible — the difference the
      // detachment list and the dashboard switcher actually render.
      expect(view.coversDetachment('d_coast'), isFalse);
      expect(view.coversDetachment('d_dam_rural'), isFalse);
    });

    test('Simple Admin does not hold any administration capability', () {
      // The three keys `AdminView` calls Administration. Acquiring one of
      // these by accident is what would silently promote the persona to the
      // full experience and make the whole demo pair prove nothing.
      expect(simple.can(Cap.adminManage), isFalse);
      expect(simple.can(Cap.orgEdit), isFalse);
      expect(simple.can(Cap.detachmentCreate), isFalse);
    });

    test('Simple Admin holds no lifecycle or override key, in scope either',
        () {
      const withheld = {
        Cap.detachmentEdit,
        Cap.detachmentArchive,
        Cap.memberDeactivate,
        Cap.shiftDelete,
        Cap.shiftAttendanceOverride,
        Cap.announcementPublish,
      };
      for (final key in withheld) {
        for (final id in kDemoSimpleAdminDetachments) {
          expect(simple.canIn(id, key), isFalse, reason: key);
        }
        expect(simple.canAnywhere(key), isFalse, reason: key);
      }
    });

    test('Simple Admin still has real work to do in its detachments', () {
      // Narrower must not mean empty: an account that can see nothing proves
      // nothing about scoping, it just looks broken.
      const granted = {
        Cap.detachmentView,
        Cap.memberView,
        Cap.memberContactView,
        Cap.shiftManage,
        Cap.shiftAssign,
        Cap.shiftAttendanceRecord,
        Cap.inventoryAdjust,
        Cap.statsView,
      };
      for (final key in granted) {
        expect(simple.canIn('d_dam_central', key), isTrue, reason: key);
      }
    });

    test('the Main Admin grant is a strict superset of the Simple one', () {
      for (final key in Cap.all) {
        if (!simple.canAnywhere(key)) continue;
        expect(main.canAnywhere(key), isTrue, reason: key);
      }
      // And strictly bigger, in both directions that matter.
      expect(main.can(Cap.adminManage), isTrue);
      expect(simple.can(Cap.adminManage), isFalse);
    });
  });

  group('Super Admin borrows nothing from the tenant application', () {
    final caps = DemoPersona.superAdmin.user.capabilities;

    test('it holds no tenant capability at all', () {
      expect(caps, Capabilities.none);
      for (final key in Cap.all) {
        expect(caps.canAnywhere(key), isFalse, reason: key);
      }
    });

    test('its role does not make it an in-tenant full admin', () {
      // `AdminView` is capability-derived and knows nothing about roles, so
      // a Super Admin is never classified as the broad in-tenant experience
      // merely by being a Super Admin. What keeps it out of the tenant app
      // is the router, not this — see `demo_login_test.dart`.
      final view = AdminView.of(caps);
      expect(view.experience, AdminExperience.scoped);
      expect(view.organisationWideDetachments, isFalse);
      expect(view.namedDetachmentIds, isEmpty);
      expect(view.hasNoDetachment, isTrue);
    });
  });
}
