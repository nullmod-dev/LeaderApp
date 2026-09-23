import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/announcement/data/announcement_providers.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/customer_demo.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/demo/data/demo_workspace.dart';
import 'package:mtm/features/demo/domain/demo_capabilities.dart';
import 'package:mtm/features/demo/domain/demo_seed.dart';
import 'package:mtm/features/detachment/data/detachment_providers.dart';
import 'package:mtm/features/detachment/domain/detachment_models.dart';
import 'package:mtm/features/detachment_group/data/detachment_group_providers.dart';
import 'package:mtm/features/home/data/home_providers.dart';
import 'package:mtm/features/inventory/data/inventory_providers.dart';
import 'package:mtm/features/notification/data/notification_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/team/data/team_providers.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';
import 'package:mtm/features/workshop/data/workshop_providers.dart';
import 'package:mtm/features/workshop/domain/workshop_models.dart';

/// The Customer Demo isolation boundary, asserted where it is decided: the
/// repository providers, the session envelope and the seeded workspace.

T _ok<T>(dynamic result) => (result as dynamic).when(
      success: (T data, {bool stale = false}) => data,
      failure: (String m, String? c) => fail('expected success, got: $m'),
      offline: (T? cached) => fail('expected success, got offline'),
    ) as T;

ProviderContainer _demoContainer({AuthUser? user, SessionAccess? access}) {
  final container = ProviderContainer(overrides: [
    currentUserResultProvider
        .overrideWith((ref) async => Success(user ?? customerDemoUser)),
    sessionAccessOverrideProvider.overrideWith(
      (ref) => access ?? const SessionAccess(demo: DemoMode.active),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Reads the session once so the sync providers below see it resolved.
Future<ProviderContainer> _demo() async {
  final container = _demoContainer();
  await container.read(currentUserProvider.future);
  return container;
}

void main() {
  group('the workspace is what a demo session reads', () {
    test('every operational repository is the demo one', () async {
      final container = await _demo();
      final workspace = container.read(demoWorkspaceProvider);
      expect(workspace, isNotNull);

      expect(identical(container.read(teamRepositoryProvider), workspace!.team),
          isTrue);
      expect(
          identical(container.read(detachmentRepositoryProvider),
              workspace.detachments),
          isTrue);
      expect(
          identical(container.read(detachmentGroupRepositoryProvider),
              workspace.detachmentGroups),
          isTrue);
      expect(
          identical(container.read(shiftRepositoryProvider), workspace.shifts),
          isTrue);
      expect(
          identical(
              container.read(inventoryRepositoryProvider), workspace.inventory),
          isTrue);
      expect(
          identical(
              container.read(workshopRepositoryProvider), workspace.workshops),
          isTrue);
      expect(identical(container.read(homeRepositoryProvider), workspace.home),
          isTrue);
      expect(
          identical(container.read(announcementRepositoryProvider),
              workspace.announcements),
          isTrue);
      expect(
          identical(container.read(notificationRepositoryProvider),
              workspace.notifications),
          isTrue);
    });

    test('a real session gets none of them', () async {
      final container = _demoContainer(
        user: const AuthUser(
          id: 'u_admin',
          name: 'مشرف',
          email: 'admin@mtm.org',
          role: AuthRole.mainAdmin,
          saasTenantId: 'saas_hilal',
          capabilities: Capabilities(global: Cap.all),
          orgName: 'ليدر',
        ),
        access: SessionAccess.normal,
      );
      await container.read(currentUserProvider.future);
      expect(container.read(demoWorkspaceProvider), isNull);
      expect(container.read(isCustomerDemoSessionProvider), isFalse);
    });

    test('a demo identity without the demo envelope is not a demo', () async {
      final container = _demoContainer(access: SessionAccess.normal);
      await container.read(currentUserProvider.future);
      // Both halves must agree, exactly as the startup classifier requires.
      expect(container.read(isCustomerDemoSessionProvider), isFalse);
      expect(container.read(demoWorkspaceProvider), isNull);
    });
  });

  group('the sample dataset is the product limit', () {
    test('exactly two detachments and exactly two workshops', () async {
      final container = await _demo();
      final workspace = container.read(demoWorkspaceProvider)!;

      final detachments =
          _ok<List<Detachment>>(await workspace.detachments.list());
      expect(detachments.length, 2);
      expect(detachments.map((d) => d.id), containsAll(DemoSeed.detachmentIds));

      final workshops = _ok<List<Workshop>>(await workspace.workshops.list());
      expect(workshops.length, 2);
      expect(workshops.map((w) => w.name).toSet().length, 2);
    });

    test('one roster feeds the detachments, the shifts and the workshops',
        () async {
      final container = await _demo();
      final workspace = container.read(demoWorkspaceProvider)!;

      final city = _ok<List<TeamMember>>(
          await workspace.team.listForDetachment(DemoSeed.cityDetachment));
      final field = _ok<List<TeamMember>>(
          await workspace.team.listForDetachment(DemoSeed.fieldDetachment));
      expect(city.length + field.length, DemoSeed.members().length);

      // The register points at the same people, by id.
      final register = _ok<List<WorkshopParticipant>>(
          await workspace.workshops.participants('dw1'));
      final rosterIds = {
        for (final m in [...city, ...field]) m.id
      };
      for (final line in register.where((p) => p.memberId != null)) {
        expect(rosterIds, contains(line.memberId));
      }
      expect(register, isNotEmpty);
    });

    test('nothing in the demo carries a tenant fixture id', () async {
      final container = await _demo();
      final workspace = container.read(demoWorkspaceProvider)!;
      final detachments =
          _ok<List<Detachment>>(await workspace.detachments.list());
      for (final detachment in detachments) {
        expect(detachment.id, startsWith('d_demo_'));
      }
      final members = [
        ..._ok<List<TeamMember>>(
            await workspace.team.listForDetachment(DemoSeed.cityDetachment)),
        ..._ok<List<TeamMember>>(
            await workspace.team.listForDetachment(DemoSeed.fieldDetachment)),
      ];
      for (final member in members) {
        expect(member.id, startsWith('dm'));
      }
    });
  });

  group('what a demo may and may not be', () {
    test('it holds the demo envelope and neither administration key', () {
      expect(customerDemoUser.capabilities, demoCapabilities);
      expect(demoCapabilityKeys.contains(Cap.adminManage), isFalse);
      expect(demoCapabilityKeys.contains(Cap.orgEdit), isFalse);
      // Everything else this build knows is offered, so the trial can
      // exercise the product.
      expect(
        Cap.all.difference(demoCapabilityKeys),
        {Cap.adminManage, Cap.orgEdit},
      );
    });

    test('it is no tenant: no id, no membership, no tenant feature grant',
        () async {
      final container = await _demo();
      expect(customerDemoUser.saasTenantId, isNull);
      expect(customerDemoUser.role.belongsToSaasTenant, isFalse);

      // The demo's modules are a product decision, not a subscription: the
      // tenant store is never consulted, and holds nothing for the demo.
      final access = container.read(currentTenantFeatureAccessProvider);
      expect(access.kind, TenantFeatureContextKind.customerDemo);
      expect(access.features, isNull);
      expect(container.read(platformTenantStoreProvider).featuresOf('g_demo'),
          isNull);
      for (final key in TenantFeatureKey.values) {
        expect(container.read(tenantFeatureAvailableProvider(key)),
            demoTenantFeatures.contains(key));
      }
    });
  });

  group('demo mutations stay inside the demo', () {
    test('a workshop change never reaches the ordinary repositories', () async {
      final container = await _demo();
      final workspace = container.read(demoWorkspaceProvider)!;

      final before = _ok<List<WorkshopParticipant>>(
          await workspace.workshops.participants('dw1'));
      _ok<List<WorkshopParticipant>>(
          await workspace.workshops.addMemberParticipants('dw1', ['dm5']));
      final after = _ok<List<WorkshopParticipant>>(
          await workspace.workshops.participants('dw1'));
      expect(after.length, before.length + 1);

      // The member is still on the demo roster, and the demo roster is still
      // the only roster this session can see.
      final member = _ok<TeamMember>(await workspace.team.byId('dm5'));
      expect(member.detachmentId, DemoSeed.cityDetachment);

      // A second, ordinary workspace — what a real session would read — is
      // untouched by any of it.
      final real = DemoWorkspace();
      final realRegister = _ok<List<WorkshopParticipant>>(
          await real.workshops.participants('dw1'));
      expect(realRegister.length, before.length);
    });

    test('ending the demo drops the workspace and everything in it', () async {
      final container = ProviderContainer(overrides: [
        currentUserResultProvider
            .overrideWith((ref) async => const Success(customerDemoUser)),
        sessionAccessOverrideProvider
            .overrideWith((ref) => const SessionAccess(demo: DemoMode.active)),
      ]);
      addTearDown(container.dispose);
      await container.read(currentUserProvider.future);

      final workspace = container.read(demoWorkspaceProvider);
      expect(workspace, isNotNull);
      _ok<WorkshopParticipant>(
          await workspace!.workshops.addGuestParticipant('dw1', 'ضيف تجريبي'));

      // The session stops being a demo — sign-out, or the trial ending.
      container.read(sessionAccessOverrideProvider.notifier).state =
          SessionAccess.normal;
      expect(container.read(demoWorkspaceProvider), isNull);
      expect(
          identical(
              container.read(workshopRepositoryProvider), workspace.workshops),
          isFalse);
    });
  });
}
