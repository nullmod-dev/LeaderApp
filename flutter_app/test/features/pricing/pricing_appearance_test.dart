import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/pricing/data/commerce_control_plane.dart';
import 'package:mtm/features/pricing/presentation/pricing_page.dart';
import 'package:mtm/l10n/strings.dart';

void main() {
  Future<void> render(
    WidgetTester tester, {
    required PaletteId palette,
    required Brightness brightness,
    required bool eyeProtect,
    required double width,
    required double textScale,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        commerceControlPlaneSeedProvider.overrideWithValue(
          const CommerceState(offers: [], coupons: []),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(palette, eyeProtect: eyeProtect),
        darkTheme: AppTheme.dark(palette, eyeProtect: eyeProtect),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: PricingPage(
          key: ValueKey(
            '${palette.name}-${brightness.name}-$eyeProtect-$width-$textScale',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(S.pricingFullAccess), findsOneWidget);

    final page = find.byKey(const Key('pricing-page'));
    for (var i = 0; i < 8; i++) {
      await tester.drag(page, const Offset(0, -500));
      await tester.pump();
    }
    expect(find.text(S.pricingContactTitle), findsOneWidget);
  }

  for (final palette in PaletteId.values) {
    testWidgets('${palette.name} light and dark render at 390dp',
        (tester) async {
      for (final brightness in Brightness.values) {
        await render(
          tester,
          palette: palette,
          brightness: brightness,
          eyeProtect: false,
          width: 390,
          textScale: 1,
        );
      }
    });

    testWidgets('${palette.name} eye protection survives 320dp at 1.6x',
        (tester) async {
      await render(
        tester,
        palette: palette,
        brightness: Brightness.light,
        eyeProtect: true,
        width: 320,
        textScale: 1.6,
      );
    });
  }

  testWidgets('the maximum text sweep renders at 320dp and 2x', (tester) async {
    await render(
      tester,
      palette: PaletteId.medical,
      brightness: Brightness.dark,
      eyeProtect: true,
      width: 320,
      textScale: 2,
    );
  });
}
