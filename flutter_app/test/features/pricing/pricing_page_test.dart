import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/pricing/data/commerce_control_plane.dart';
import 'package:mtm/features/pricing/domain/billing_option.dart';
import 'package:mtm/features/pricing/domain/money.dart';
import 'package:mtm/features/pricing/domain/promotion.dart';
import 'package:mtm/features/pricing/presentation/pricing_page.dart';
import 'package:mtm/l10n/strings.dart';

void main() {
  final now = DateTime.utc(2026, 9, 16);
  const user = AuthUser(
    id: 'account_1',
    name: 'Test',
    email: 'test@example.com',
    role: AuthRole.mainAdmin,
    saasTenantId: 'tenant_1',
    capabilities: Capabilities.none,
    orgName: 'Org',
    avatarInitials: 'T',
  );

  Future<void> pump(
    WidgetTester tester, {
    CommerceState seed = const CommerceState(offers: [], coupons: []),
    double width = 390,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        currentUserProvider.overrideWith((ref) async => user),
        commerceControlPlaneSeedProvider.overrideWithValue(seed),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: PricingPage(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('default state shows four approved plans and full access copy',
      (tester) async {
    await pump(tester);
    expect(find.text(S.pricingTitle), findsOneWidget);
    expect(find.text('\$6'), findsWidgets);
    expect(find.text('\$14'), findsOneWidget);
    expect(find.text('\$24'), findsOneWidget);
    expect(find.text('\$40'), findsOneWidget);
    expect(find.text(S.pricingBestValue), findsOneWidget);
    expect(find.text(S.pricingFullAccess), findsOneWidget);
    expect(find.byKey(const Key('pricing-offer-banner')), findsNothing);
  });

  testWidgets('a live global offer appears and changes only its target',
      (tester) async {
    await pump(
      tester,
      seed: CommerceState(offers: [
        GlobalOffer(
          id: 'offer',
          enabled: true,
          target: BillingOptionId.monthly,
          discount: const FixedFinalPriceDiscount(Money.cents(200)),
          createdAt: now,
          title: S.pricingSpecialOffer,
        ),
      ], coupons: const []),
    );
    expect(find.byKey(const Key('pricing-offer-banner')), findsOneWidget);
    expect(find.text('\$2'), findsWidgets);
    expect(find.text('\$6'), findsOneWidget); // struck original.
    expect(find.text('\$14'), findsOneWidget);
  });

  testWidgets('coupon validates, updates its plan, and does not redeem',
      (tester) async {
    final coupon = Coupon(
      id: 'try2',
      code: 'TRY2',
      enabled: true,
      target: BillingOptionId.monthly,
      discount: const FixedFinalPriceDiscount(Money.cents(200)),
      assignment: const CouponAssignmentPublic(),
      createdAt: now,
    );
    await pump(
      tester,
      seed: CommerceState(offers: const [], coupons: [coupon]),
    );
    await tester.tap(find.byKey(const Key('pricing-plan-monthly')));
    await tester.enterText(
        find.byKey(const Key('pricing-coupon-input')), ' try 2 ');
    await tester
        .ensureVisible(find.byKey(const Key('pricing-coupon-validate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pricing-coupon-validate')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pricing-coupon-valid')), findsOneWidget);
    expect(find.text('\$2'), findsWidgets);
    expect(coupon.enabled, isTrue, reason: 'validation is not redemption');
  });

  testWidgets('invalid coupon keeps the typed text and all contact UI',
      (tester) async {
    await pump(tester);
    final field = find.byKey(const Key('pricing-coupon-input'));
    await tester.enterText(field, 'NOPE');
    await tester
        .ensureVisible(find.byKey(const Key('pricing-coupon-validate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pricing-coupon-validate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pricing-coupon-invalid')), findsOneWidget);
    expect(find.text('NOPE'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const Key('pricing-contact-section')));
    await tester.pumpAndSettle();
    expect(find.text('@jjkkkj'), findsOneWidget);
    expect(find.text('07701322947'), findsOneWidget);
    expect(find.text('nullmod.dev@gmail.com'), findsOneWidget);
  });

  testWidgets('the surface contains contact language and no purchase promise',
      (tester) async {
    await pump(tester);
    expect(find.text(S.pricingContactTitle), findsOneWidget);
    expect(find.textContaining('ادفع'), findsNothing);
    expect(find.textContaining('نجاح الدفع'), findsNothing);
    expect(find.textContaining('اشترك الآن'), findsNothing);
  });
}
