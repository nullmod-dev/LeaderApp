import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/customer_demo_controller.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/data/in_memory_demo_session_store.dart';
import 'package:mtm/features/auth/data/mock_auth_repository.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/customer_demo.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/demo/data/demo_workspace.dart';
import 'package:mtm/features/demo/domain/demo_capabilities.dart';
import 'package:mtm/features/demo/presentation/demo_trial_bar.dart';
import 'package:mtm/features/auth/presentation/login_page.dart';
import 'package:mtm/l10n/strings.dart';

void main() {
  test('Customer Demo has its own identity and isolated session', () async {
    final store = InMemoryDemoSessionStore(seed: DemoPersona.simpleAdmin);
    final repository = MockAuthRepository(demoSessions: store);

    final result = await repository.startCustomerDemo(
      policy: const CustomerDemoPolicy(available: true),
    );
    final user = result.when<AuthUser?>(
      success: (data, {stale = false}) => data,
      failure: (_, __) => null,
      offline: (_) => null,
    );

    expect(user, customerDemoUser);
    expect(user!.role, AuthRole.customerDemo);
    expect(user.saasTenantId, isNull);
    // The demo-only envelope: enough to run the product, and never the two
    // administration keys.
    expect(user.capabilities, demoCapabilities);
    expect(user.capabilities.global.contains(Cap.adminManage), isFalse);
    expect(user.capabilities.global.contains(Cap.orgEdit), isFalse);
    expect(user.capabilities.scoped, isEmpty);
    expect(repository.currentSessionAccess.demo, DemoMode.active);
    expect(user.name, contains(S.productNameAr));
    expect(user.orgName, contains(S.productNameAr));
    expect(user.name, isNot(contains('MTM')));
    expect(user.orgName, isNot(contains('MTM')));
    expect(await store.read(), isNull,
        reason: 'the product demo never occupies the developer-persona key');
  });

  test('Customer Demo classifies only to the isolated demo surface', () {
    final destination = resolveStartup(StartupInputs(
      gate: AuthGate.signedIn,
      now: DateTime.utc(2026, 9, 12),
      user: customerDemoUser,
      access: const SessionAccess(demo: DemoMode.active),
    ));
    expect(destination, StartupDestination.demoActive);
    expect(destination, isNot(StartupDestination.tenantSurface));
    expect(destination, isNot(StartupDestination.platformSurface));
  });

  test('unavailable policy never creates a session', () async {
    final repository = MockAuthRepository(
      demoSessions: InMemoryDemoSessionStore(seed: null),
    );
    final result = await repository.startCustomerDemo(
      policy: const CustomerDemoPolicy(available: false),
    );
    expect(result.isFailure, isTrue);
    expect(
        (await repository.currentUser()).when<AuthUser?>(
          success: (data, {stale = false}) => data,
          failure: (_, __) => null,
          offline: (_) => null,
        ),
        isNull);
  });

  testWidgets('Login never exposes Customer Demo even when globally enabled',
      (tester) async {
    final container = ProviderContainer(overrides: [
      customerDemoPolicyProvider.overrideWithValue(
        const CustomerDemoPolicy(available: true),
      ),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: LoginPage(),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('customer-demo-entry')), findsNothing);
    expect(find.text(S.customerDemoAction), findsNothing);
  });

  testWidgets('the demo bar fits 320dp at 1.6x text in RTL', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isCustomerDemoSessionProvider.overrideWith((ref) => true),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: const Scaffold(body: DemoTrialBar()),
      ),
    ));
    await tester.pump();

    expect(find.text(S.demoTrialNotice), findsOneWidget);
    expect(find.textContaining('MTM'), findsNothing);
    expect(tester.takeException(), isNull);
    final exit = find.widgetWithText(TextButton, S.customerDemoExit);
    expect(exit, findsOneWidget);
    expect(tester.getSize(exit).height, greaterThanOrEqualTo(48));
  });

  testWidgets('the demo bar is not rendered for a real session',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isCustomerDemoSessionProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: DemoTrialBar()),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text(S.demoTrialNotice), findsNothing);
    expect(find.text(S.customerDemoExit), findsNothing);
  });
}
