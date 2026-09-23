import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_presets.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';

/// Locks the rulings of 2026-09-02 (`CAPABILITIES.md` §0) into executable form.
/// If a count here fails, either the document or the code moved without the
/// other — decide which, do not just update the number.
void main() {
  group('key partition', () {
    // 29 at the 2026-09-02 ruling; `announcement.publish` was added
    // 2026-09-07 for the internal announcement system (`CAPABILITIES.md` §10)
    // and is per-detachment, so the scoped half is the one that grew.
    test('30 keys, split 10 global / 20 scoped', () {
      expect(Cap.all.length, 30);
      expect(Cap.global.length, 10);
      expect(Cap.scoped.length, 20);
    });

    test('global and scoped are disjoint and cover everything', () {
      expect(Cap.global.intersection(Cap.scoped), isEmpty);
      expect(Cap.global.union(Cap.scoped), Cap.all);
    });

    test('workshops are org-level, so no workshop key is scoped', () {
      final workshopKeys = Cap.all.where((k) => k.startsWith('workshop.'));
      expect(workshopKeys, hasLength(7));
      expect(workshopKeys.every(Cap.global.contains), isTrue);
    });

    test('the three dropped view keys are gone', () {
      expect(Cap.all, isNot(contains('shift.view')));
      expect(Cap.all, isNot(contains('inventory.view')));
      expect(Cap.all, isNot(contains('workshop.view')));
      expect(Cap.all, contains(Cap.detachmentView));
    });

    test('the merged keys replaced their halves', () {
      expect(Cap.all, contains(Cap.shiftManage));
      expect(Cap.all, contains(Cap.inventoryItemManage));
      expect(Cap.all, isNot(contains('shift.create')));
      expect(Cap.all, isNot(contains('shift.edit')));
      expect(Cap.all, isNot(contains('inventory.item.create')));
      expect(Cap.all, isNot(contains('inventory.item.edit')));
    });
  });

  group('presets', () {
    test('three presets — Super Admin is not a mobile role', () {
      expect(CapabilityPreset.values, hasLength(3));
    });

    test('Main Admin holds every key', () {
      expect(CapabilityPreset.mainAdmin.keys, Cap.all);
    });

    test('sub-Admin: every operational act, no lifecycle, money, or admin', () {
      const withheld = {
        Cap.detachmentCreate,
        Cap.detachmentEdit,
        Cap.detachmentArchive,
        Cap.memberDeactivate,
        Cap.shiftDelete,
        Cap.shiftAttendanceOverride,
        Cap.workshopArchive,
        Cap.workshopPaymentRecord,
        Cap.adminManage,
        Cap.orgEdit,
        // Added 2026-09-07 and deliberately withheld: Point 14 §4 rules that a
        // scoped administrator may publish announcements **only when granted**
        // the key, so it fails closed like every key added after a preset was
        // written. Granting it is one deliberate act on the admin screen.
        Cap.announcementPublish,
      };
      final keys = CapabilityPreset.subAdmin.keys;
      expect(keys, hasLength(19));
      expect(Cap.all.difference(keys), withheld);
      // The two cells that looked inconsistent and are not.
      expect(keys, contains(Cap.memberRoleAssign));
      expect(keys, contains(Cap.statsView));
    });

    test('Volunteer holds exactly the roster pair, without contact details',
        () {
      expect(
        CapabilityPreset.volunteer.keys,
        {Cap.detachmentView, Cap.memberView},
      );
      expect(
        CapabilityPreset.volunteer.keys,
        isNot(contains(Cap.memberContactView)),
      );
    });

    test('grant() puts each key on the right side of the partition', () {
      final caps = CapabilityPreset.mainAdmin.grant(detachments: ['d_homs']);
      expect(caps.global, Cap.global);
      expect(caps.scoped.keys, ['d_homs']);
      expect(caps.scoped['d_homs'], Cap.scoped);
    });

    test('grant() with no detachments yields global keys only', () {
      final caps = CapabilityPreset.subAdmin.grant();
      expect(caps.scoped, isEmpty);
      expect(caps.global, isNot(contains(Cap.shiftManage)));
      expect(caps.can(Cap.workshopCreate), isTrue);
    });
  });

  group('resolver', () {
    final subAdmin = CapabilityPreset.subAdmin.grant(detachments: ['d_homs']);

    test('an unknown key is denied, never granted', () {
      const caps = Capabilities(global: {'shift.teleport'});
      expect(caps.canIn('d_homs', 'shift.teleport'), isFalse);
      expect(caps.canIn(null, 'shift.teleport'), isFalse);
    });

    test('Capabilities.none denies every key', () {
      for (final key in Cap.all) {
        expect(Capabilities.none.canIn('d_homs', key), isFalse, reason: key);
      }
    });

    test('a global key holds with or without a detachment', () {
      expect(subAdmin.can(Cap.workshopCreate), isTrue);
      expect(subAdmin.canIn('d_homs', Cap.workshopCreate), isTrue);
      expect(subAdmin.canIn('d_coast', Cap.workshopCreate), isTrue);
    });

    test('a scoped key holds only inside the granted detachment', () {
      expect(subAdmin.canIn('d_homs', Cap.shiftManage), isTrue);
      expect(subAdmin.canIn('d_coast', Cap.shiftManage), isFalse);
      expect(subAdmin.canIn(null, Cap.shiftManage), isFalse);
    });

    test('a withheld key is denied even inside the granted detachment', () {
      expect(subAdmin.canIn('d_homs', Cap.shiftDelete), isFalse);
      expect(subAdmin.canIn('d_homs', Cap.memberDeactivate), isFalse);
    });

    test('union, not override: a global grant needs no per-detachment entry',
        () {
      const caps = Capabilities(global: {Cap.shiftManage});
      expect(caps.canIn('d_coast', Cap.shiftManage), isTrue);
    });

    test('Q3 — any scoped grant implies seeing that detachment', () {
      const caps = Capabilities(scoped: {
        'd_homs': {Cap.shiftManage},
      });
      expect(caps.canIn('d_homs', Cap.detachmentView), isTrue);
      expect(caps.canIn('d_coast', Cap.detachmentView), isFalse);
      // ...and implies nothing else.
      expect(caps.canIn('d_homs', Cap.memberEdit), isFalse);
    });

    test('an empty scoped entry implies nothing', () {
      const caps = Capabilities(scoped: {'d_homs': <String>{}});
      expect(caps.canIn('d_homs', Cap.detachmentView), isFalse);
      expect(caps.visibleDetachmentIds, isEmpty);
    });

    test('canAnyIn opens a two-key route on either key', () {
      const recorder = Capabilities(scoped: {
        'd_homs': {Cap.shiftAttendanceRecord},
      });
      const neither = Capabilities(scoped: {
        'd_homs': {Cap.memberView},
      });
      expect(recorder.canAnyIn('d_homs', Cap.shiftRoute), isTrue);
      expect(subAdmin.canAnyIn('d_homs', Cap.shiftRoute), isTrue);
      expect(neither.canAnyIn('d_homs', Cap.shiftRoute), isFalse);
    });

    test('can() rejects a per-detachment key instead of silently denying', () {
      expect(() => subAdmin.can(Cap.shiftManage), throwsAssertionError);
    });

    test('visibleDetachmentIds lists the detachments with real grants', () {
      final caps =
          CapabilityPreset.subAdmin.grant(detachments: ['d_homs', 'd_coast']);
      expect(caps.visibleDetachmentIds, ['d_homs', 'd_coast']);
    });
  });

  group('wire format', () {
    test('Capabilities survives a JSON round trip', () {
      final caps = CapabilityPreset.subAdmin.grant(detachments: ['d_homs']);
      expect(Capabilities.fromJson(caps.toJson()), caps);
    });

    test('a missing or empty payload parses as no grants', () {
      expect(Capabilities.fromJson(const {}), Capabilities.none);
    });

    test('an unknown key is kept on the wire but still denied', () {
      final parsed = Capabilities.fromJson(const {
        'global': ['admin.manage', 'org.teleport'],
      });
      expect(parsed.toJson()['global'], contains('org.teleport'));
      expect(parsed.can('org.teleport'), isFalse);
      expect(parsed.can(Cap.adminManage), isTrue);
    });

    test('equal grants compare equal so gated controls do not rebuild', () {
      final a = CapabilityPreset.volunteer.grant(detachments: ['d_homs']);
      final b = CapabilityPreset.volunteer.grant(detachments: ['d_homs']);
      final c = CapabilityPreset.volunteer.grant(detachments: ['d_coast']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    // `AuthUser.role` was added for Point 2. It classifies the product
    // surface — platform, or one paying team — and it is deliberately **not**
    // a second source of authority: the grant still round-trips
    // independently, and nothing in `Capabilities` consults the role. The
    // preset the account was created from is still not recoverable from the
    // payload, which is the property that stopped a role being an authority
    // check in the first place.
    test('AuthUser carries its capability grant through JSON beside the role',
        () {
      final user = AuthUser(
        id: 'u_1',
        name: 'ليلى ياسين',
        email: 'l.yaseen@mtm.org',
        role: AuthRole.mainAdmin,
        saasTenantId: 'saas_test',
        capabilities: CapabilityPreset.mainAdmin.grant(detachments: ['d_homs']),
        orgName: 'فريق الإسعاف التطوعي · دمشق',
        avatarInitials: 'لي',
      );
      final json = user.toJson();
      expect(json['role'], 'main_admin');
      expect(AuthUser.fromJson(json).capabilities, user.capabilities);
      expect(AuthUser.fromJson(json).role, AuthRole.mainAdmin);
    });
  });
}
