import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/platform/data/platform_commerce_providers.dart';
import 'package:mtm/features/platform/presentation/platform_commerce_page.dart';
import 'package:mtm/features/platform/presentation/platform_coupon_edit_page.dart';
import 'package:mtm/features/platform/presentation/platform_offer_edit_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/pricing/data/commerce_control_plane.dart';
import 'package:mtm/features/pricing/domain/billing_option.dart';
import 'package:mtm/features/pricing/domain/promotion.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

void main() {
  const empty = CommerceState(offers: [], coupons: []);

  test('only Super Admin resolves a commerce actor', () async {
    for (final (user, allowed) in [
      (DemoPersona.superAdmin.user, true),
      (DemoPersona.mainAdmin.user, false),
      (DemoPersona.simpleAdmin.user, false),
      (
        const AuthUser(
          id: 'demo_user',
          name: 'Demo',
          email: 'demo@example.com',
          role: AuthRole.mainAdmin,
          saasTenantId: null,
          capabilities: Capabilities.none,
          orgName: 'Demo',
        ),
        false,
      ),
    ]) {
      final scope = platformContainer(user, overrides: [
        commerceControlPlaneSeedProvider.overrideWithValue(empty),
      ]);
      await scope.read(currentUserProvider.future);
      expect(scope.read(platformCommerceActorProvider) != null, allowed);
      final result = scope.read(platformCommerceActionsProvider).createOffer(
            target: BillingOptionId.monthly,
            discount: const PercentageDiscount(10),
            enabled: false,
          );
      expect(result.isSuccess, allowed);
      if (!allowed) {
        expect(
            (result as Failure<GlobalOffer>).code, CommerceCodes.notAuthorized);
      }
    }
  });

  testWidgets('Super Admin opens commerce and sees read-only base prices',
      (tester) async {
    final scope = platformContainer(superAdmin, overrides: [
      commerceControlPlaneSeedProvider.overrideWithValue(empty),
    ]);
    final router = await bootPlatform(tester, scope, height: 1200);
    router.go(PlatformOperationsRoutes.commerce);
    await settlePlatform(tester);

    expect(find.byType(PlatformCommercePage), findsOneWidget);
    expect(find.text(S.platformCommerceDevOnly), findsOneWidget);
    expect(find.text('\$6'), findsOneWidget);
    expect(find.text('\$14'), findsOneWidget);
    expect(find.text('\$24'), findsOneWidget);
    expect(find.text('\$40'), findsOneWidget);
    expect(find.text(S.platformCommerceBasePricesNote), findsOneWidget);
    expect(find.byKey(const Key('platform-commerce-create-offer')),
        findsOneWidget);
    expect(find.byKey(const Key('platform-commerce-create-coupon')),
        findsOneWidget);
  });

  testWidgets('offer form exposes only eligible targets and creates locally',
      (tester) async {
    final scope = platformContainer(superAdmin, overrides: [
      commerceControlPlaneSeedProvider.overrideWithValue(empty),
    ]);
    final router = await bootPlatform(tester, scope, height: 1000);
    router.go(PlatformOperationsRoutes.commerceOffer);
    await settlePlatform(tester);

    expect(find.byType(PlatformOfferEditPage), findsOneWidget);
    expect(find.text(S.pricingOneMonth), findsOneWidget);
    expect(find.text(S.pricingThreeMonths), findsOneWidget);
    expect(find.text(S.pricingSixMonths), findsNothing);
    expect(find.text(S.pricingTwelveMonths), findsNothing);

    await tester.enterText(find.byKey(const Key('platform-offer-value')), '20');
    await tester.tap(find.byKey(const Key('platform-offer-save')));
    await settlePlatform(tester);
    expect(scope.read(commerceControlPlaneProvider).offers, hasLength(1));
  });

  testWidgets('coupon form creates a targeted normalized coupon',
      (tester) async {
    final scope = platformContainer(superAdmin, overrides: [
      commerceControlPlaneSeedProvider.overrideWithValue(empty),
    ]);
    final router = await bootPlatform(tester, scope, height: 1400);
    router.go(PlatformOperationsRoutes.commerceCoupon);
    await settlePlatform(tester);

    expect(find.byType(PlatformCouponEditPage), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('platform-coupon-code')), ' team 20 ');
    await tester.enterText(
        find.byKey(const Key('platform-coupon-value')), '20');
    await tester.tap(find.text(S.platformCommerceTargeted));
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('platform-coupon-account')), 'account_42');
    await tester.ensureVisible(find.byKey(const Key('platform-coupon-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('platform-coupon-save')));
    await settlePlatform(tester);

    final coupon = scope.read(commerceControlPlaneProvider).coupons.single;
    expect(coupon.code, 'TEAM20');
    expect(coupon.assignment, isA<CouponAssignmentAccount>());
  });

  testWidgets('offer and coupon editors reflow at 320dp and 1.6x text',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final inherited = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = inherited);
    final scope = platformContainer(superAdmin, overrides: [
      commerceControlPlaneSeedProvider.overrideWithValue(empty),
    ]);
    final router = await bootPlatform(
      tester,
      scope,
      width: 320,
      height: 900,
      textScale: 1.6,
    );

    for (final path in [
      PlatformOperationsRoutes.commerceOffer,
      PlatformOperationsRoutes.commerceCoupon,
    ]) {
      router.go(path);
      await settlePlatform(tester);
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 5; i++) {
        await tester.drag(scrollable, const Offset(0, -350));
        await tester.pump();
      }
    }
    expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
  });
}
