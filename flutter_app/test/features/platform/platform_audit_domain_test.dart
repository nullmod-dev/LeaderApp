import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/presentation/platform_audit_copy.dart';

void main() {
  group('PlatformAuditEvent', () {
    test('round-trips JSON while normalizing timestamps to UTC', () {
      final event = PlatformAuditEvent(
        id: 'audit-1',
        occurredAt: DateTime.parse('2026-09-10T08:15:00-04:00'),
        actor: const PlatformAuditAdministratorActor(
          id: 'admin-1',
          displayName: 'Platform Admin',
        ),
        action: PlatformAuditAction.featureFlagChanged,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenantFeature,
          id: 'feature-1',
          displayName: 'Scheduling',
        ),
        tenant: const PlatformAuditTenantReference(
          id: 'tenant-1',
          displayName: 'North Team',
          isDeleted: false,
        ),
        changes: const [
          PlatformAuditChange(
            field: PlatformAuditChangeField.featureEnabled,
            before: PlatformAuditBoolValue(false),
            after: PlatformAuditBoolValue(true),
          ),
        ],
      );

      final json = event.toJson();
      final decoded = PlatformAuditEvent.fromJson(json);

      expect(json['occurredAt'], '2026-09-10T12:15:00.000Z');
      expect(decoded.occurredAt.isUtc, isTrue);
      expect(decoded.toJson(), json);
      expect(decoded.category, PlatformAuditCategory.entitlement);
    });

    test('unknown enum wires remain typed and do not crash', () {
      final event = PlatformAuditEvent.fromJson(const {
        'id': 'audit-future',
        'occurredAt': '2026-09-10T12:00:00Z',
        'actor': {'kind': 'service_robot', 'token': 'must-not-survive'},
        'action': 'future_action',
        'target': {'type': 'future_resource', 'id': 'future-1'},
        'changes': <Object?>[],
      });

      expect(event.actor, isA<PlatformAuditUnknownActor>());
      expect(event.action, PlatformAuditAction.unknown);
      expect(event.category, PlatformAuditCategory.unknown);
      expect(event.target.type, PlatformAuditTargetResource.unknown);
      expect(event.actor.toJson(), {'kind': 'unknown'});
    });

    test('actor variants expose only their invariant fields', () {
      expect(
        const PlatformAuditAdministratorActor(
          id: 'admin-1',
          displayName: 'Admin',
        ).toJson().keys,
        unorderedEquals(['kind', 'id', 'displayName']),
      );
      expect(
        const PlatformAuditSystemActor().toJson(),
        {'kind': 'system'},
      );
      expect(
        const PlatformAuditUnknownActor().toJson(),
        {'kind': 'unknown'},
      );
    });

    test('target and tenant snapshots contain only approved keys', () {
      expect(
        const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenant,
          id: 'tenant-1',
          displayName: 'North Team',
        ).toJson().keys,
        unorderedEquals(['type', 'id', 'displayName']),
      );
      expect(
        const PlatformAuditTenantReference(
          id: 'tenant-1',
          displayName: 'North Team',
          isDeleted: true,
        ).toJson().keys,
        unorderedEquals(['id', 'displayName', 'isDeleted']),
      );
    });

    test('changes are unmodifiable', () {
      final source = <PlatformAuditChange>[];
      final event = PlatformAuditEvent(
        id: 'audit-1',
        occurredAt: DateTime.utc(2026),
        actor: const PlatformAuditSystemActor(),
        action: PlatformAuditAction.tenantRegistered,
        target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.tenant,
          id: 'tenant-1',
        ),
        changes: source,
      );

      source.add(const PlatformAuditChange(
        field: PlatformAuditChangeField.lifecycleStatus,
      ));
      expect(event.changes, isEmpty);
      expect(
        () => event.changes.add(const PlatformAuditChange(
          field: PlatformAuditChangeField.lifecycleStatus,
        )),
        throwsUnsupportedError,
      );
    });
  });

  group('PlatformAuditSafetyPolicy', () {
    test('forbidden snake and camel field names are always redacted', () {
      for (final field in [
        'password',
        'temporary_password',
        'tempPassword',
        'otpCode',
        'access_token',
        'clientSecret',
        'authorizationHeader',
        'sessionId',
        'team_code',
        'teamCode',
      ]) {
        final change = PlatformAuditChange.fromJson({
          'field': field,
          'before': const {'kind': 'text', 'value': 'old-secret'},
          'after': const {'kind': 'text', 'value': 'new-secret'},
        });

        expect(change.field, PlatformAuditChangeField.unknown);
        expect(change.before, isA<PlatformAuditRedactedValue>());
        expect(change.after, isA<PlatformAuditRedactedValue>());
        expect(change.toJson(), {
          'field': 'unknown',
          'before': {'kind': 'redacted'},
          'after': {'kind': 'redacted'},
        });
      }
    });

    test('unknown fields discard their raw name and values', () {
      final change = PlatformAuditChange.fromJson(const {
        'field': 'future_private_field',
        'before': {'kind': 'text', 'value': 'raw-before'},
        'after': {'kind': 'text', 'value': 'raw-after'},
      });

      expect(change.toJson(), {
        'field': 'unknown',
        'before': {'kind': 'redacted'},
        'after': {'kind': 'redacted'},
      });
    });

    test('known fields accept only their expected value kind', () {
      final malformed = PlatformAuditChange.fromJson(const {
        'field': 'feature_enabled',
        'before': {'kind': 'text', 'value': 'no'},
        'after': {'kind': 'bool', 'value': true},
      });

      expect(malformed.before, isA<PlatformAuditRedactedValue>());
      expect(malformed.after, isA<PlatformAuditBoolValue>());
      expect(malformed.toJson()['before'], {'kind': 'redacted'});
    });

    test('direct construction cannot bypass value-kind redaction', () {
      const malformed = PlatformAuditChange(
        field: PlatformAuditChangeField.featureEnabled,
        before: PlatformAuditTextValue('must-not-pass-through'),
        after: PlatformAuditBoolValue(true),
      );
      const unknown = PlatformAuditChange(
        field: PlatformAuditChangeField.unknown,
        before: PlatformAuditTextValue('must-not-pass-through'),
      );

      expect(malformed.before, isA<PlatformAuditRedactedValue>());
      expect(malformed.after, isA<PlatformAuditBoolValue>());
      expect(unknown.before, isA<PlatformAuditRedactedValue>());
    });

    test('known enum wires round-trip and unknown values fail safely', () {
      for (final value in PlatformAuditActorKind.values) {
        expect(PlatformAuditActorKind.parse(value.wire), value);
      }
      for (final value in PlatformAuditAction.values) {
        expect(PlatformAuditAction.parse(value.wire), value);
      }
      for (final value in PlatformAuditCategory.values) {
        expect(PlatformAuditCategory.parse(value.wire), value);
      }
      for (final value in PlatformAuditTargetResource.values) {
        expect(PlatformAuditTargetResource.parse(value.wire), value);
      }
      expect(
        PlatformAuditAction.parse('newer_action'),
        PlatformAuditAction.unknown,
      );
    });

    test('break-glass catalogue maps to emergency access without raw keys', () {
      for (final action in [
        PlatformAuditAction.breakGlassActivated,
        PlatformAuditAction.breakGlassEnded,
        PlatformAuditAction.breakGlassExpired,
        PlatformAuditAction.breakGlassRevoked,
      ]) {
        expect(action.category, PlatformAuditCategory.emergencyAccess);
        expect(PlatformAuditAction.parse(action.wire), action);
        expect(AuditCopy.action(action), isNot(contains('break_glass')));
      }
      expect(
        PlatformAuditTargetResource.parse('break_glass_grant'),
        PlatformAuditTargetResource.breakGlassGrant,
      );
      expect(
        AuditCopy.category(PlatformAuditCategory.emergencyAccess),
        'الوصول الطارئ',
      );
      expect(
        AuditCopy.resource(PlatformAuditTargetResource.breakGlassGrant),
        'منحة الوصول الطارئ',
      );
    });

    test('Main Admin catalogue parses, renders, filters, and redacts identity',
        () {
      final actions = [
        PlatformAuditAction.mainAdminSetupResent,
        PlatformAuditAction.mainAdminSuspended,
        PlatformAuditAction.mainAdminReactivated,
        PlatformAuditAction.mainAdminReplacementStarted,
        PlatformAuditAction.mainAdminReplacementCancelled,
        PlatformAuditAction.mainAdminReplaced,
      ];
      for (final action in actions) {
        expect(PlatformAuditAction.parse(action.wire), action);
        expect(action.category, PlatformAuditCategory.accountManagement);
        expect(AuditCopy.action(action), isNot(contains(action.wire)));
      }
      expect(
        PlatformAuditCategory.parse('account_management'),
        PlatformAuditCategory.accountManagement,
      );
      expect(
        PlatformAuditTargetResource.parse('main_admin_account'),
        PlatformAuditTargetResource.mainAdminAccount,
      );
      expect(
        AuditCopy.category(PlatformAuditCategory.accountManagement),
        isNot(contains('account_management')),
      );
      expect(
        AuditCopy.resource(PlatformAuditTargetResource.mainAdminAccount),
        isNot(contains('main_admin_account')),
      );

      final status = PlatformAuditChange.fromJson(const {
        'field': 'account_status',
        'before': {'kind': 'text', 'value': 'active'},
        'after': {'kind': 'text', 'value': 'suspended'},
      });
      final identity = PlatformAuditChange.fromJson(const {
        'field': 'login_identity',
        'before': {'kind': 'text', 'value': 'old@example.org'},
        'after': {'kind': 'text', 'value': 'new@example.org'},
      });
      expect(status.field, PlatformAuditChangeField.accountStatus);
      expect(AuditCopy.value(status.field, status.after), 'موقوف');
      expect(identity.field, PlatformAuditChangeField.loginIdentity);
      expect(identity.before, isA<PlatformAuditRedactedValue>());
      expect(identity.after, isA<PlatformAuditRedactedValue>());
      expect(identity.toJson().toString(), isNot(contains('@example.org')));

      final query = PlatformAuditQuery(
        category: PlatformAuditCategory.accountManagement,
        action: PlatformAuditAction.mainAdminSuspended,
        targetType: PlatformAuditTargetResource.mainAdminAccount,
      );
      expect(query.category, PlatformAuditCategory.accountManagement);
      expect(query.action, PlatformAuditAction.mainAdminSuspended);
      expect(query.targetType, PlatformAuditTargetResource.mainAdminAccount);
    });
  });

  group('PlatformAuditQuery and page', () {
    test('normalizes bounds, validates interval and limit', () {
      final query = PlatformAuditQuery(
        from: DateTime.parse('2026-09-01T00:00:00-04:00'),
        before: DateTime.parse('2026-09-02T00:00:00-04:00'),
      );

      expect(query.from, DateTime.utc(2026, 9, 1, 4));
      expect(query.before, DateTime.utc(2026, 9, 2, 4));
      expect(query.limit, 50);
      expect(
        () => PlatformAuditQuery(
          from: DateTime.utc(2026, 9, 2),
          before: DateTime.utc(2026, 9, 2),
        ),
        throwsAssertionError,
      );
      expect(() => PlatformAuditQuery(limit: 0), throwsAssertionError);
      expect(() => PlatformAuditQuery(limit: 101), throwsAssertionError);
    });

    test('has value equality and firstPage clears only the cursor', () {
      final first = PlatformAuditQuery(
        from: DateTime.utc(2026, 9),
        actorKind: PlatformAuditActorKind.platformAdministrator,
        actorId: 'admin-1',
        action: PlatformAuditAction.planChanged,
        category: PlatformAuditCategory.subscription,
        tenantId: 'tenant-1',
        targetType: PlatformAuditTargetResource.planAssignment,
        search: 'North',
        cursor: 'opaque-cursor',
        limit: 25,
      );
      final equal = PlatformAuditQuery(
        from: DateTime.utc(2026, 9),
        actorKind: PlatformAuditActorKind.platformAdministrator,
        actorId: 'admin-1',
        action: PlatformAuditAction.planChanged,
        category: PlatformAuditCategory.subscription,
        tenantId: 'tenant-1',
        targetType: PlatformAuditTargetResource.planAssignment,
        search: 'North',
        cursor: 'opaque-cursor',
        limit: 25,
      );

      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first.firstPage.cursor, isNull);
      expect(first.firstPage.search, first.search);
      expect(first.firstPage.limit, first.limit);
    });

    test('page round-trips and owns an unmodifiable item list', () {
      final source = <PlatformAuditEvent>[
        PlatformAuditEvent(
          id: 'audit-1',
          occurredAt: DateTime.utc(2026, 9, 10),
          actor: const PlatformAuditSystemActor(),
          action: PlatformAuditAction.tenantRegistered,
          target: const PlatformAuditTarget(
            type: PlatformAuditTargetResource.tenant,
            id: 'tenant-1',
          ),
          changes: const [],
        ),
      ];
      final page = PlatformAuditPage(
        items: source,
        nextCursor: 'next',
      );

      source.clear();
      expect(page.items, hasLength(1));
      expect(() => page.items.clear(), throwsUnsupportedError);
      expect(PlatformAuditPage.fromJson(page.toJson()).toJson(), page.toJson());
      expect(page.hasMore, isTrue);
      expect(page.toJson().containsKey('total'), isFalse);
    });
  });
}
