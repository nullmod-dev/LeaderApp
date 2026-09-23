import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';

/// Point 2 — `AuthRole` and the role/SaasTenant invariant.
///
/// The thing that has to be right here is not the enum, it is the pairing.
/// A `main_admin` whose `saasTenantId` went missing, or a `super_admin` that
/// somehow acquired one, is an account whose isolation boundary is unknown —
/// and the one outcome that must never happen is the client quietly picking
/// a boundary for it. So these tests assert two things about every invalid
/// shape: that it is *recognised* as invalid, and that nothing repairs it.

AuthUser _user({
  required AuthRole role,
  required String? saasTenantId,
}) =>
    AuthUser(
      id: 'u',
      name: 'مشرف',
      email: 'admin@mtm.org',
      role: role,
      saasTenantId: saasTenantId,
      capabilities: const Capabilities(),
      orgName: 'MTM',
    );

void main() {
  group('role ↔ saasTenantId invariant', () {
    test('super_admin with a null saasTenantId is valid', () {
      expect(
        _user(role: AuthRole.superAdmin, saasTenantId: null).isWellFormed,
        isTrue,
      );
    });

    test('super_admin carrying a saasTenantId is invalid', () {
      // The platform owner is not inside a paying team. An id here means the
      // server sent an account whose surface and whose scope disagree.
      expect(
        _user(role: AuthRole.superAdmin, saasTenantId: 'saas_1').isWellFormed,
        isFalse,
      );
    });

    test('main_admin with a saasTenantId is valid', () {
      expect(
        _user(role: AuthRole.mainAdmin, saasTenantId: 'saas_1').isWellFormed,
        isTrue,
      );
    });

    test('main_admin without a saasTenantId is invalid', () {
      expect(
        _user(role: AuthRole.mainAdmin, saasTenantId: null).isWellFormed,
        isFalse,
      );
    });

    test('admin with a saasTenantId is valid', () {
      expect(
        _user(role: AuthRole.admin, saasTenantId: 'saas_1').isWellFormed,
        isTrue,
      );
    });

    test('admin without a saasTenantId is invalid', () {
      expect(
        _user(role: AuthRole.admin, saasTenantId: null).isWellFormed,
        isFalse,
      );
    });

    test('customer_demo has no SaasTenant', () {
      expect(
        _user(role: AuthRole.customerDemo, saasTenantId: null).isWellFormed,
        isTrue,
      );
      expect(
        _user(role: AuthRole.customerDemo, saasTenantId: 'saas_1').isWellFormed,
        isFalse,
      );
    });

    test('an empty string is not a SaasTenant id', () {
      // `''` is the shape a naive serializer produces for a missing value.
      // Accepting it would give a tenant-scoped account a boundary that
      // matches nothing — worse than no account at all, because it looks
      // valid to everything downstream.
      expect(
        _user(role: AuthRole.mainAdmin, saasTenantId: '').isWellFormed,
        isFalse,
      );
    });
  });

  group('wire mapping', () {
    test('administrator and customer-demo roles carry contracted values', () {
      expect(AuthRole.superAdmin.wire, 'super_admin');
      expect(AuthRole.mainAdmin.wire, 'main_admin');
      expect(AuthRole.admin.wire, 'admin');
      expect(AuthRole.customerDemo.wire, 'customer_demo');
      expect(AuthRole.values, hasLength(4));
    });

    test('parse round-trips every role and refuses anything else', () {
      for (final role in AuthRole.values) {
        expect(AuthRole.parse(role.wire), role);
      }
      // Refused, not defaulted: a role this build cannot classify must not
      // be handed a product surface on a guess.
      expect(AuthRole.parse('owner'), isNull);
      expect(AuthRole.parse('superadmin'), isNull);
      expect(AuthRole.parse('Super_Admin'), isNull);
      expect(AuthRole.parse(null), isNull);
    });

    test('belongsToSaasTenant is true for exactly the two tenant roles', () {
      expect(AuthRole.superAdmin.belongsToSaasTenant, isFalse);
      expect(AuthRole.mainAdmin.belongsToSaasTenant, isTrue);
      expect(AuthRole.admin.belongsToSaasTenant, isTrue);
      expect(AuthRole.customerDemo.belongsToSaasTenant, isFalse);
    });
  });

  group('AuthUser JSON', () {
    test('a tenant account round-trips role and saasTenantId', () {
      final user = _user(role: AuthRole.admin, saasTenantId: 'saas_1');
      final json = user.toJson();
      expect(json['role'], 'admin');
      expect(json['saasTenantId'], 'saas_1');

      final back = AuthUser.fromJson(json);
      expect(back.role, AuthRole.admin);
      expect(back.saasTenantId, 'saas_1');
    });

    test('a platform account round-trips a null saasTenantId', () {
      final json =
          _user(role: AuthRole.superAdmin, saasTenantId: null).toJson();
      expect(json['role'], 'super_admin');
      // Present and null, not absent: the field is part of the contract and
      // its null is the statement "this account is not in a tenant".
      expect(json.containsKey('saasTenantId'), isTrue);
      expect(json['saasTenantId'], isNull);
      expect(AuthUser.fromJson(json).saasTenantId, isNull);
    });

    test('a payload with no role is refused', () {
      final json = _user(role: AuthRole.mainAdmin, saasTenantId: 'saas_1')
          .toJson()
        ..remove('role');
      expect(() => AuthUser.fromJson(json), throwsFormatException);
    });

    test('a payload with an unknown role is refused', () {
      final json = _user(role: AuthRole.mainAdmin, saasTenantId: 'saas_1')
          .toJson()
        ..['role'] = 'owner';
      expect(() => AuthUser.fromJson(json), throwsFormatException);
    });

    test('an invalid role/tenant pair is refused, never repaired', () {
      // Both directions. The point of throwing rather than returning a
      // corrected object is that there is no correct object to return: the
      // client cannot know whether the role or the id is the wrong one.
      final orphan = _user(role: AuthRole.mainAdmin, saasTenantId: 'saas_1')
          .toJson()
        ..['saasTenantId'] = null;
      expect(() => AuthUser.fromJson(orphan), throwsFormatException);

      final strayScope = _user(role: AuthRole.superAdmin, saasTenantId: null)
          .toJson()
        ..['saasTenantId'] = 'saas_1';
      expect(() => AuthUser.fromJson(strayScope), throwsFormatException);
    });
  });
}
