import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/about/presentation/about_page.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/organization/data/mock_organization_repository.dart';
import 'package:mtm/features/organization/data/organization_providers.dart';
import 'package:mtm/features/organization/domain/organization_models.dart';
import 'package:mtm/features/organization/domain/organization_repository.dart';
import 'package:mtm/features/organization/presentation/organization_page.dart';
import 'package:mtm/features/organization/presentation/plan_page.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

/// Point 15 — Organization (`/more/organization`) and Plan (`/more/plan`),
/// entered through the real router as each role, over the canonical tenant
/// store. States that no fixture produces are handed in through a fixed
/// read, never by pumping a page on its own.
void main() {
  final now = DateTime.utc(2026, 9, 12, 9);

  AuthUser tenantUser(
    String tenantId, {
    AuthRole role = AuthRole.mainAdmin,
    Capabilities capabilities = const Capabilities(global: Cap.all),
  }) =>
      AuthUser(
        id: 'u_$tenantId',
        name: 'مشرف',
        email: 'admin@mtm.org',
        role: role,
        saasTenantId: tenantId,
        capabilities: capabilities,
        orgName: 'MTM',
      );

  OrganizationSnapshot snapshotOf(String tenantId, {bool usage = true}) =>
      MockOrganizationRepository.project(
        PlatformTenantStore(clock: () => now).byId(tenantId)!,
        now: now,
        usage: usage,
      );

  Future<(ProviderContainer, GoRouter)> boot(
    WidgetTester tester, {
    required String location,
    AuthUser? user,
    MockOrganizationMode mode = MockOrganizationMode.loaded,
    OrganizationRepository? repository,
    double width = 400,
    double height = 2600,
    double textScale = 1,
    ThemeData? theme,
    bool reduceMotion = false,
  }) async {
    ignoreKnownTenantComplaints();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
    final container = platformContainer(
      user ?? mainAdmin,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        organizationMockConfigProvider.overrideWithValue(
          OrganizationMockConfig(mode: mode, latency: Duration.zero),
        ),
        if (repository != null)
          organizationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: theme ?? AppTheme.light(PaletteId.medical),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await settlePlatform(tester);
    router.go(location);
    await settlePlatform(tester);
    return (container, router);
  }

  String semanticsOf(WidgetTester tester, String key) =>
      tester.getSemantics(find.byKey(Key(key))).label;

  const org = OrganizationPage.routePath;
  const plan = PlanPage.routePath;

  group('Organization', () {
    testWidgets('Main Admin sees identity, states and safe context',
        (tester) async {
      final (_, router) = await boot(tester, location: org);
      expect(locationOf(router), org);
      expect(find.byType(OrganizationPage), findsOneWidget);
      expect(find.text('فرق الهلال الطبية'), findsOneWidget);
      expect(find.text(S.orgAccessActive), findsOneWidget);
      expect(find.text(S.orgSubscriptionActive), findsOneWidget);
      expect(find.byKey(const Key('org-registered')), findsOneWidget);
      // Main Admin context: the display name only.
      expect(find.text('سلمى الحارثي'), findsOneWidget);
      // The support reference, not the control-plane slug it is derived from.
      expect(find.text('HILAL'), findsOneWidget);
      expect(find.text('saas_hilal'), findsNothing);
      expect(find.text(S.planTitleAdvanced), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Team Code, login email and any control are absent',
        (tester) async {
      await boot(tester, location: org);
      final record = PlatformTenantStore(clock: () => now).byId('saas_hilal')!;
      expect(find.textContaining(record.teamCode), findsNothing);
      expect(find.textContaining('MTM-'), findsNothing);
      expect(find.textContaining(record.mainAdmin.email), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('Simple Admin reads the same organisation', (tester) async {
      await boot(tester, location: org, user: simpleAdmin);
      expect(find.byType(OrganizationPage), findsOneWidget);
      expect(find.text('فرق الهلال الطبية'), findsOneWidget);
      expect(find.text(S.orgAccessActive), findsOneWidget);
      expect(find.text('سلمى الحارثي'), findsOneWidget);
    });

    testWidgets('the chips announce what they are the status of',
        (tester) async {
      final handle = tester.ensureSemantics();
      await boot(tester, location: org);
      expect(
        semanticsOf(tester, 'org-subscription-chip'),
        S.orgSubscriptionAnnouncement
            .replaceFirst('%s', S.orgSubscriptionActive),
      );
      expect(semanticsOf(tester, 'org-access-chip'), S.orgAccessActive);
      handle.dispose();
    });

    testWidgets('the reference copies exactly what is shown', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await boot(tester, location: org);
      final copy = find.byKey(const Key('org-reference-copy'));
      expect(tester.getSize(copy).height, greaterThanOrEqualTo(48));
      await tester.tap(copy);
      await tester.pump();
      // What is copied is what is shown: the support reference, not the
      // control-plane slug behind it.
      expect(copied, 'HILAL');
      expect(find.text(S.orgIdCopied), findsOneWidget);
    });

    testWidgets('the reference is an LTR island inside the RTL page',
        (tester) async {
      await boot(tester, location: org);
      final value = find.byKey(const Key('org-reference-value'));
      expect(Directionality.of(tester.element(value)), TextDirection.ltr);
      expect(
        Directionality.of(tester.element(find.byKey(const Key('org-name')))),
        TextDirection.rtl,
      );
    });

    testWidgets('the plan row opens Plan; support opens About', (tester) async {
      await boot(tester, location: org);
      await tester.tap(find.byKey(const Key('org-open-plan')));
      await settlePlatform(tester);
      // Pushed, so Organization stays underneath and Back returns to it.
      expect(find.byType(PlanPage), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settlePlatform(tester);
      expect(find.byType(PlanPage), findsNothing);
      expect(find.byType(OrganizationPage), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('org-contact-support')));
      await tester.tap(find.byKey(const Key('org-contact-support')));
      await settlePlatform(tester);
      expect(find.byType(AboutPage), findsOneWidget);
    });

    testWidgets('the pre-Point-15 path redirects to Organization',
        (tester) async {
      final (_, router) = await boot(tester, location: '/more/org');
      expect(locationOf(router), org);
      expect(find.byType(OrganizationPage), findsOneWidget);
    });

    testWidgets('offline with a cached copy says so and offers a read',
        (tester) async {
      final repo = _FixedRead(Offline(cached: snapshotOf('saas_hilal')));
      await boot(tester, location: org, repository: repo);
      expect(find.text(S.orgOfflineNotice), findsOneWidget);
      expect(find.textContaining(S.orgLastRead), findsOneWidget);
      expect(find.text('فرق الهلال الطبية'), findsOneWidget);
      final refresh = find.byKey(const Key('org-refresh'));
      expect(tester.getSize(refresh).height, greaterThanOrEqualTo(48));
      final before = repo.reads;
      await tester.tap(refresh);
      await settlePlatform(tester);
      expect(repo.reads, before + 1);
    });

    testWidgets('stale says the refresh failed, not that it is offline',
        (tester) async {
      await boot(tester, location: org, mode: MockOrganizationMode.stale);
      expect(find.text(S.orgStaleNotice), findsOneWidget);
      expect(find.text(S.orgOfflineNotice), findsNothing);
    });

    testWidgets('offline without a cached copy is its own state',
        (tester) async {
      await boot(tester, location: org, mode: MockOrganizationMode.offline);
      expect(find.text(S.orgOfflineNoCache), findsOneWidget);
      expect(find.text(S.retry), findsOneWidget);
      expect(find.byKey(const Key('org-identity')), findsNothing);
    });

    testWidgets('a failure offers a retry, never a half screen',
        (tester) async {
      await boot(tester, location: org, mode: MockOrganizationMode.failure);
      expect(find.text(S.retry), findsOneWidget);
      expect(find.byKey(const Key('org-identity')), findsNothing);
    });

    testWidgets('a session with no organisation gets a designed state',
        (tester) async {
      await boot(
        tester,
        location: org,
        repository: _FixedRead(Failure(
          'x',
          code: OrganizationProblemCode.contextUnavailable.wire,
        )),
      );
      expect(find.text(S.orgUnavailableTitle), findsOneWidget);
      expect(find.text(S.retry), findsNothing);
    });

    testWidgets('unknown states stay unknown', (tester) async {
      await boot(tester, location: org, mode: MockOrganizationMode.unsupported);
      expect(find.text(S.orgAccessUnknown), findsOneWidget);
      expect(find.text(S.orgSubscriptionUnknown), findsOneWidget);
      expect(find.text(S.planTitleUnknown), findsOneWidget);
      expect(find.text(S.orgAccessActive), findsNothing);
      expect(find.text(S.orgSubscriptionActive), findsNothing);
      expect(find.text(S.planTitleBasic), findsNothing);
    });

    testWidgets('320dp at 1.6x lays out without overflow', (tester) async {
      await boot(
        tester,
        location: org,
        width: 320,
        height: 2200,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('فرق الهلال الطبية'), findsOneWidget);
      expect(find.text('HILAL'), findsOneWidget);
    });
  });

  group('Plan', () {
    for (final (tenantId, title) in const [
      ('saas_wadi', S.planTitleBasic),
      ('saas_najd', S.planTitleStandard),
      ('saas_hilal', S.planTitleAdvanced),
    ]) {
      testWidgets('$tenantId shows $title', (tester) async {
        await boot(tester, location: plan, user: tenantUser(tenantId));
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the plan heading is announced as the current plan',
        (tester) async {
      final handle = tester.ensureSemantics();
      await boot(tester, location: plan);
      final node = tester.getSemantics(find.byKey(const Key('plan-title')));
      expect(
        node.label,
        S.planCurrentAnnouncement.replaceFirst('%s', S.planTitleAdvanced),
      );
      expect(node.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets('active shows the administrative renewal date', (tester) async {
      await boot(tester, location: plan);
      expect(find.text(S.orgSubscriptionActive), findsOneWidget);
      expect(find.text(S.planRenews), findsOneWidget);
      expect(find.byKey(const Key('plan-subscription-note')), findsNothing);
    });

    testWidgets('trial shows when the trial ends', (tester) async {
      await boot(tester, location: plan, user: tenantUser('saas_masar'));
      expect(find.text(S.orgSubscriptionTrial), findsOneWidget);
      expect(find.text(S.planTrialEnds), findsOneWidget);
    });

    testWidgets('grace shows its end and a neutral note, with no day count',
        (tester) async {
      await boot(tester, location: plan, user: tenantUser('saas_afiah'));
      expect(find.text(S.orgSubscriptionGrace), findsOneWidget);
      expect(find.text(S.planGraceEnds), findsOneWidget);
      expect(find.text(S.planGraceNote), findsOneWidget);
      expect(find.textContaining('١٤'), findsNothing);
      expect(find.textContaining('14'), findsNothing);
    });

    testWidgets('inactive is separate from access and carries no date',
        (tester) async {
      final base = snapshotOf('saas_hilal');
      final inactive = OrganizationSnapshot(
        tenantId: base.tenantId,
        displayName: base.displayName,
        lifecycle: SaasTenantStatus.active,
        subscription: const OrganizationSubscription(
          status: SubscriptionStatus.inactive,
          plan: OrganizationPlanKnown(PlanTier.standard),
        ),
        limits: base.limits,
        readAt: now,
      );
      await boot(
        tester,
        location: plan,
        repository: _FixedRead(Success(inactive)),
      );
      expect(find.text(S.orgSubscriptionInactive), findsOneWidget);
      expect(find.text(S.planInactiveNote), findsOneWidget);
      expect(find.byKey(const Key('plan-subscription-date')), findsNothing);
    });

    testWidgets('a default limit reads usage over the plan default',
        (tester) async {
      final handle = tester.ensureSemantics();
      await boot(tester, location: plan);
      expect(
        semanticsOf(tester, 'plan-limit-detachments'),
        'المفارز، الاستخدام ٢٣ من ٤٠، ضمن الحد',
      );
      handle.dispose();
    });

    testWidgets('an override is shown with the plan default beside it',
        (tester) async {
      final handle = tester.ensureSemantics();
      await boot(tester, location: plan, user: tenantUser('saas_sahel'));
      expect(
        semanticsOf(tester, 'plan-limit-detachments'),
        startsWith('المفارز، الاستخدام ٧ من ١٠'),
      );
      expect(
        find.text(S.limitCustom.replaceFirst('%s', '١٥')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('at limit and over limit are said in words', (tester) async {
      final base = snapshotOf('saas_hilal');
      final edges = OrganizationSnapshot(
        tenantId: base.tenantId,
        displayName: base.displayName,
        lifecycle: base.lifecycle,
        subscription: base.subscription,
        readAt: now,
        limits: OrganizationLimits(usageIncluded: true, items: [
          for (final line in base.limits.items)
            switch (line.key) {
              PlanLimitKey.detachments =>
                OrganizationLimit(key: line.key, effective: 20, usage: 20),
              PlanLimitKey.members => OrganizationLimit(
                  key: line.key,
                  effective: 200,
                  planDefault: 1000,
                  overridden: true,
                  usage: 233),
              _ => line,
            },
        ]),
      );
      await boot(tester,
          location: plan, repository: _FixedRead(Success(edges)));
      expect(
          find.byKey(const Key('plan-limit-flag-detachments')), findsOneWidget);
      expect(find.byKey(const Key('plan-limit-flag-members')), findsOneWidget);
      expect(find.text(S.limitAt), findsOneWidget);
      expect(find.text(S.limitOver), findsOneWidget);
      expect(find.text(S.limitAtNote), findsOneWidget);
      expect(find.text(S.limitOverNote), findsOneWidget);
      // Nothing is "near" a limit.
      expect(find.byKey(const Key('plan-limit-flag-workshops')), findsNothing);
    });

    testWidgets('no plan shows no limits and never claims unlimited',
        (tester) async {
      await boot(tester, location: plan, user: tenantUser('saas_nabd'));
      expect(find.text(S.planTitleNone), findsOneWidget);
      expect(find.text(S.planNoPlanLimits), findsOneWidget);
      expect(find.byKey(const Key('plan-limit-detachments')), findsNothing);
      expect(find.textContaining('غير محدود'), findsNothing);
    });

    testWidgets('Simple Admin sees the limits without organisation usage',
        (tester) async {
      final handle = tester.ensureSemantics();
      await boot(tester, location: plan, user: simpleAdmin);
      expect(find.text(S.planUsageHiddenNote), findsOneWidget);
      expect(
        semanticsOf(tester, 'plan-limit-members'),
        'الأعضاء، الحد الأقصى ١٠٠٠',
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      handle.dispose();
    });

    testWidgets('Main Admin sees usage, and the bars carry no animation',
        (tester) async {
      await boot(tester, location: plan);
      expect(find.text(S.planUsageHiddenNote), findsNothing);
      final bars = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bars, hasLength(PlanLimitKey.values.length));
      expect(bars.every((bar) => bar.value != null), isTrue);
    });

    testWidgets('the four modules show their tenant-wide state',
        (tester) async {
      final handle = tester.ensureSemantics();
      final (container, _) = await boot(tester, location: plan);
      expect(tenantFeatureCatalog, hasLength(4));
      for (final definition in tenantFeatureCatalog) {
        expect(
          semanticsOf(tester, 'plan-feature-${definition.key.wire}'),
          '${definition.arabicLabel}: ${S.featureEnabled}',
        );
      }
      container
          .read(platformTenantStoreProvider)
          .updateFeature('saas_hilal', TenantFeatureKey.workshops, false);
      container.read(tenantFeatureRevisionProvider.notifier).changed();
      await settlePlatform(tester);
      expect(
        semanticsOf(tester, 'plan-feature-workshops'),
        'الورش: ${S.featureDisabled}',
      );
      handle.dispose();
    });

    testWidgets('an enabled module is not a capability, and back',
        (tester) async {
      final handle = tester.ensureSemantics();
      // A session with no workshop capability at all still sees the module
      // enabled for the organisation…
      await boot(
        tester,
        location: plan,
        user: tenantUser(
          'saas_hilal',
          role: AuthRole.admin,
          capabilities: const Capabilities(scoped: {
            'd_dam_central': {Cap.detachmentView},
          }),
        ),
      );
      expect(
        semanticsOf(tester, 'plan-feature-workshops'),
        'الورش: ${S.featureEnabled}',
      );
      expect(find.text(S.planExplainBody), findsOneWidget);
      handle.dispose();
    });

    testWidgets('…and every capability does not enable a disabled module',
        (tester) async {
      final handle = tester.ensureSemantics();
      final store = PlatformTenantStore(clock: () => now);
      final (container, _) = await boot(tester, location: plan);
      container
          .read(platformTenantStoreProvider)
          .updateFeature('saas_hilal', TenantFeatureKey.inventory, false);
      container.read(tenantFeatureRevisionProvider.notifier).changed();
      await settlePlatform(tester);
      expect(store, isNotNull);
      expect(
        semanticsOf(tester, 'plan-feature-inventory'),
        'المخزون: ${S.featureDisabled}',
      );
      handle.dispose();
    });

    testWidgets('an unreadable entitlement is said, not drawn as disabled',
        (tester) async {
      await boot(
        tester,
        location: plan,
        user: tenantUser('saas_unknown'),
        repository: _FixedRead(Success(snapshotOf('saas_hilal'))),
      );
      expect(find.text(S.planFeaturesUnavailable), findsOneWidget);
      expect(find.text(S.featureDisabled), findsNothing);
    });

    testWidgets('unknown plan, status and limit key fail safe', (tester) async {
      await boot(tester,
          location: plan, mode: MockOrganizationMode.unsupported);
      expect(find.text(S.planTitleUnknown), findsOneWidget);
      expect(find.text(S.planDescUnknown), findsOneWidget);
      expect(find.text(S.orgSubscriptionUnknown), findsOneWidget);
      expect(find.text(S.planStatusUnknownNote), findsOneWidget);
      expect(find.text(S.planLimitsUnsupported), findsOneWidget);
      expect(find.text(S.limitUnavailable), findsOneWidget);
      for (final known in [
        S.planTitleBasic,
        S.planTitleStandard,
        S.planTitleAdvanced,
        S.orgSubscriptionActive,
      ]) {
        expect(find.text(known), findsNothing, reason: known);
      }
      // No raw wire value reaches the screen.
      for (final raw in ['paused_v2', 'mtm_enterprise_v2', 'api_calls_v2']) {
        expect(find.textContaining(raw), findsNothing, reason: raw);
      }
    });

    testWidgets('stale and offline copies are marked on Plan too',
        (tester) async {
      await boot(tester, location: plan, mode: MockOrganizationMode.stale);
      expect(find.text(S.orgStaleNotice), findsOneWidget);
    });

    testWidgets('no billing, upgrade or platform control exists',
        (tester) async {
      await boot(tester, location: plan);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(IconButton), findsOneWidget); // the back button
      for (final word in [
        'سعر',
        'دفع',
        'فاتورة',
        'ترقية',
        'إلغاء الاشتراك',
        'تغيير الخطة',
        r'$',
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });

    testWidgets('320dp at 1.6x with limits at and over lays out',
        (tester) async {
      final base = snapshotOf('saas_afiah');
      await boot(
        tester,
        location: plan,
        user: tenantUser('saas_afiah'),
        repository: _FixedRead(Success(OrganizationSnapshot(
          tenantId: base.tenantId,
          displayName: base.displayName,
          lifecycle: base.lifecycle,
          subscription: base.subscription,
          readAt: now,
          limits: OrganizationLimits(usageIncluded: true, items: [
            for (final line in base.limits.items)
              OrganizationLimit(
                key: line.key,
                effective: line.effective,
                planDefault: line.planDefault,
                overridden: true,
                usage: (line.effective ?? 0) + 1,
              ),
          ]),
        ))),
        width: 320,
        height: 6000,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(S.limitOver), findsNWidgets(PlanLimitKey.values.length));
    });
  });

  group('responsive, themes and reduced motion', () {
    for (final width in [320.0, 390.0, 600.0, 900.0]) {
      for (final location in [org, plan]) {
        testWidgets('$location at ${width.toInt()}dp', (tester) async {
          await boot(tester, location: location, width: width);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('at 900dp Plan puts modules beside the limits', (tester) async {
      await boot(tester, location: plan, width: 900, height: 1600);
      final limits = tester
          .getTopLeft(find.byKey(const Key('plan-limit-detachment_groups')));
      final modules =
          tester.getTopLeft(find.byKey(const Key('plan-feature-inventory')));
      // RTL: the start column is on the right.
      expect(modules.dx, lessThan(limits.dx));
      expect((modules.dy - limits.dy).abs(), lessThan(40));
    });

    for (final (name, theme) in [
      ('Dark Cyber', AppTheme.dark(PaletteId.teal)),
      ('Purple Arena', AppTheme.dark(PaletteId.indigo)),
      ('Light', AppTheme.light(PaletteId.medical)),
      ('Eye Protection', AppTheme.light(PaletteId.medical, eyeProtect: true)),
    ]) {
      testWidgets('$name builds both screens', (tester) async {
        final (_, router) = await boot(tester, location: plan, theme: theme);
        expect(tester.takeException(), isNull);
        router.go(org);
        await settlePlatform(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reduced motion renders the same final state', (tester) async {
      await boot(tester, location: plan, reduceMotion: true);
      expect(tester.takeException(), isNull);
      expect(find.text(S.planTitleAdvanced), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });
  });

  group('access', () {
    for (final location in [org, plan, '/more/org']) {
      testWidgets('the Super Admin is turned around from $location',
          (tester) async {
        final (_, router) =
            await boot(tester, location: location, user: superAdmin);
        expect(locationOf(router), PlatformShell.location);
        expect(find.byType(OrganizationPage), findsNothing);
        expect(find.byType(PlanPage), findsNothing);
      });
    }

    test('the Super Admin read itself fails closed', () async {
      final container = platformContainer(superAdmin, overrides: [
        organizationMockConfigProvider.overrideWithValue(
          const OrganizationMockConfig(latency: Duration.zero),
        ),
      ]);
      final keepAlive =
          container.listen(organizationSnapshotProvider, (_, __) {});
      addTearDown(keepAlive.close);
      final result = await container.read(organizationSnapshotProvider.future);
      expect(
        OrganizationProblemCode.parse((result as Failure).code),
        OrganizationProblemCode.contextUnavailable,
      );
    });

    for (final (role, user) in [('main', mainAdmin), ('simple', simpleAdmin)]) {
      for (final location in [org, plan]) {
        testWidgets('$role admin enters $location', (tester) async {
          final (_, router) =
              await boot(tester, location: location, user: user);
          expect(locationOf(router), location);
        });
      }
    }
  });
}

class _FixedRead implements OrganizationRepository {
  _FixedRead(this.result);
  final Result<OrganizationSnapshot> result;
  int reads = 0;

  @override
  Future<Result<OrganizationSnapshot>> readCurrent() async {
    reads++;
    return result;
  }
}
