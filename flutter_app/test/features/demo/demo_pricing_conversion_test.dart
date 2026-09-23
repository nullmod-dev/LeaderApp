import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/customer_demo.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/demo/presentation/demo_trial_bar.dart';
import 'package:mtm/features/pricing/data/commerce_control_plane.dart';
import 'package:mtm/features/pricing/presentation/pricing_page.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

void main() {
  Future<(GoRouter, ProviderContainer)> bootDemo(
    WidgetTester tester, {
    double width = 390,
    double textScale = 1,
  }) async {
    final container = platformContainer(customerDemoUser, overrides: [
      sessionAccessOverrideProvider
          .overrideWith((ref) => const SessionAccess(demo: DemoMode.active)),
      commerceControlPlaneSeedProvider.overrideWithValue(
        const CommerceState(offers: [], coupons: []),
      ),
    ]);
    final router = await bootPlatform(
      tester,
      container,
      width: width,
      height: 1200,
      textScale: textScale,
    );
    return (router, container);
  }

  testWidgets('trial bar CTA opens the one canonical pricing page',
      (tester) async {
    final (router, _) = await bootDemo(tester);
    expect(find.byType(DemoTrialBar), findsOneWidget);
    expect(find.byKey(const Key('demo-see-plans')), findsOneWidget);

    await tester.tap(find.byKey(const Key('demo-see-plans')));
    await settlePlatform(tester);

    expect(locationOf(router), PricingPage.routePath);
    expect(find.byType(PricingPage), findsOneWidget);
    expect(find.text(S.pricingTitle), findsOneWidget);
  });

  testWidgets('pricing access is read-only and constructs no tenant repository',
      (tester) async {
    final watch = TenantRepositoryWatch();
    final container = platformContainer(
      customerDemoUser,
      watch: watch,
      overrides: [
        commerceControlPlaneSeedProvider.overrideWithValue(
          const CommerceState(offers: [], coupons: []),
        ),
      ],
    );
    await container.read(currentUserProvider.future);
    final before = container.read(commerceControlPlaneProvider);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: PricingPage(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(PricingPage), findsOneWidget);
    expect(container.read(commerceControlPlaneProvider).offers, before.offers);
    expect(
        container.read(commerceControlPlaneProvider).coupons, before.coupons);
    expect(watch.built, isEmpty);
  });

  testWidgets('at 320dp and 2x text both CTA and exit remain reachable',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final inherited = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = inherited);

    await bootDemo(tester, width: 320, textScale: 2);

    expect(find.byKey(const Key('demo-see-plans')), findsOneWidget);
    expect(find.byKey(const Key('demo-exit')), findsOneWidget);
    expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
  });
}
