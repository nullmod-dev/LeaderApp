import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/platform/domain/platform_area.dart';
import 'package:mtm/features/platform/presentation/platform_destinations.dart';
import 'package:mtm/features/platform/presentation/platform_more_page.dart';
import 'package:mtm/features/platform/presentation/platform_overview_page.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/platform/presentation/platform_tenants_page.dart';
import 'package:mtm/features/platform/presentation/widgets/platform_navigation.dart';

import 'platform_harness.dart';

/// Point 4 — the platform navigation: one destination model, two controls.
///
/// What these hold: that the compact bar and the expanded rail are the *same*
/// navigation (same destinations, same selection, same branch), that the
/// switch between them is driven by available width rather than by a device
/// guess, that crossing the breakpoint does not move the operator, and that
/// the whole thing survives a 320 dp phone at a 1.6 text scale — the size
/// `§35` names, where an Arabic label that does not fit is the likeliest
/// defect in the surface.

void main() {
  /// Whichever navigation control the current width put on screen.
  ///
  /// Every finder below is scoped through it, because a destination's label is
  /// also its page's title — «المنصة» is on the bar *and* in the header — and
  /// an unscoped `find.text` would be asserting about the wrong widget half
  /// the time.
  final navControl = find.byWidgetPredicate(
    (w) => w is PlatformNavigationBar || w is PlatformNavigationRail,
  );

  Finder navLabel(PlatformDestination destination) => find.descendant(
        of: navControl,
        matching: find.text(destination.label),
      );

  Finder navItem(PlatformDestination destination) => find.ancestor(
        of: navLabel(destination),
        matching: find.byType(InkWell),
      );

  /// Whether the destination is announced as selected — read off the
  /// `Semantics` the item declares, not off its tint. `§32` asks for the
  /// selected destination to be *announced*, and an assertion about colour
  /// would pass on a bar no screen reader could describe.
  ///
  /// The declared property rather than the composed node, because the rail
  /// scrolls: a `SingleChildScrollView` contributes a semantics node of its
  /// own between the item and the label, and which node `getSemantics`
  /// resolves to would then differ between the two controls for reasons that
  /// have nothing to do with selection. The rendered tree is checked directly
  /// once, below, where it is unambiguous.
  bool isSelected(WidgetTester tester, PlatformDestination destination) =>
      tester
          .widgetList<Semantics>(
            find.ancestor(
              of: navLabel(destination),
              matching: find.byType(Semantics),
            ),
          )
          .firstWhere((s) => s.properties.selected != null)
          .properties
          .selected!;

  group('the destination registry is the one source', () {
    test('every area has exactly one destination, in branch order', () {
      expect(platformDestinations.length, PlatformArea.values.length);
      for (var i = 0; i < platformDestinations.length; i++) {
        expect(platformDestinations[i].area, PlatformArea.values[i]);
        expect(destinationFor(PlatformArea.values[i]), platformDestinations[i]);
        expect(platformDestinations[i].route, PlatformArea.values[i].route);
      }
    });

    test('no two destinations share a label or a route', () {
      final labels = platformDestinations.map((d) => d.label).toSet();
      final routes = platformDestinations.map((d) => d.route).toSet();
      expect(labels.length, platformDestinations.length);
      expect(routes.length, platformDestinations.length);
    });

    test('every area now has real available content', () {
      // Point 10 makes Operations useful through its Health and Security
      // modules. A stale reserved flag would put a «قيد الإعداد» treatment
      // back onto a branch that now owns real destinations.
      expect(
        [
          for (final d in platformDestinations)
            if (d.isReserved) d.area
        ],
        isEmpty,
      );
    });
  });

  group('compact', () {
    testWidgets('a phone gets the bar and no rail', (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 390,
      );

      expect(locationOf(router), PlatformShell.location);
      expect(find.byType(PlatformNavigationBar), findsOneWidget);
      expect(find.byType(PlatformNavigationRail), findsNothing);
      // All four labels are legible at once — the reason this is not the
      // tenant's glass pill, which shows only the selected one.
      for (final destination in platformDestinations) {
        expect(navLabel(destination), findsOneWidget,
            reason: destination.label);
      }
    });

    testWidgets('tapping a row moves the shell to that area', (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 390,
      );

      await tester.tap(navItem(destinationFor(PlatformArea.tenants)));
      await settlePlatform(tester);

      expect(locationOf(router), PlatformArea.tenants.route);
      expect(find.byType(PlatformTenantsPage), findsOneWidget);
    });

    testWidgets('the selected row follows the route, however it was reached',
        (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 390,
      );

      // Navigated, not tapped: the bar reads the shell's index rather than
      // remembering what was pressed, so a deep link selects the right row.
      router.go(PlatformArea.operations.route);
      await settlePlatform(tester);

      expect(
        isSelected(tester, destinationFor(PlatformArea.operations)),
        isTrue,
      );
      expect(
          isSelected(tester, destinationFor(PlatformArea.overview)), isFalse);
    });

    testWidgets('the selected destination is announced to a screen reader',
        (tester) async {
      // The rendered semantics node, checked once and in the simple control:
      // the item is a button, it carries its label, and it reports selection.
      await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 390,
      );

      final overview = destinationFor(PlatformArea.overview);
      final node = tester.getSemantics(navItem(overview));
      expect(node.label, overview.label);
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.flagsCollection.isButton, isTrue);

      final tenants = destinationFor(PlatformArea.tenants);
      expect(
        tester.getSemantics(navItem(tenants)).flagsCollection.isSelected,
        Tristate.isFalse,
      );
    });

    testWidgets('a nested page keeps its own area selected', (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 390,
      );

      router.go('${PlatformArea.more.route}/security');
      await settlePlatform(tester);

      expect(isSelected(tester, destinationFor(PlatformArea.more)), isTrue);
    });
  });

  group('expanded', () {
    testWidgets('at the breakpoint the rail replaces the bar', (tester) async {
      await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: PlatformShell.expandedBreakpoint,
        height: 900,
      );

      expect(find.byType(PlatformNavigationRail), findsOneWidget);
      expect(find.byType(PlatformNavigationBar), findsNothing);
    });

    testWidgets('one logical pixel below it, the bar is still there',
        (tester) async {
      await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: PlatformShell.expandedBreakpoint - 1,
        height: 900,
      );

      expect(find.byType(PlatformNavigationBar), findsOneWidget);
      expect(find.byType(PlatformNavigationRail), findsNothing);
    });

    testWidgets('the rail selects, and sits on the leading edge in RTL',
        (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 900,
        height: 900,
      );

      final rail = tester.getRect(find.byType(PlatformNavigationRail));
      // Arabic reads right to left, so the leading edge is the right one. A
      // rail on the left would be a mirrored layout, not an RTL one.
      expect(rail.right, closeTo(900, 0.5));
      expect(rail.width, PlatformNavigationRail.width);

      await tester.tap(navItem(destinationFor(PlatformArea.more)));
      await settlePlatform(tester);

      expect(locationOf(router), PlatformArea.more.route);
      expect(find.byType(PlatformMorePage), findsOneWidget);
    });

    testWidgets('content is constrained rather than stretched', (tester) async {
      await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 1200,
        height: 900,
      );

      final list = tester.getRect(find.byType(ListView).first);
      expect(
        list.width,
        lessThan(1200 - PlatformNavigationRail.width),
        reason: 'a wide window should gain margins, not a wider card',
      );
    });
  });

  group('crossing the breakpoint', () {
    testWidgets('keeps the destination and the branch', (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 390,
      );

      router.go('${PlatformArea.more.route}/profile');
      await settlePlatform(tester);
      expect(find.byType(PlatformNavigationBar), findsOneWidget);

      // The window widens — a rotation, an unfolded device, a resized split
      // view. Nothing about *where the operator is* may change.
      tester.view.physicalSize = const Size(900, 900);
      await settlePlatform(tester);

      expect(find.byType(PlatformNavigationRail), findsOneWidget);
      expect(find.byType(PlatformNavigationBar), findsNothing);
      expect(locationOf(router), '${PlatformArea.more.route}/profile');
      expect(isSelected(tester, destinationFor(PlatformArea.more)), isTrue);

      // And back again.
      tester.view.physicalSize = const Size(390, 800);
      await settlePlatform(tester);

      expect(find.byType(PlatformNavigationBar), findsOneWidget);
      expect(locationOf(router), '${PlatformArea.more.route}/profile');
    });
  });

  group('small phone, large text', () {
    for (final area in PlatformArea.values) {
      testWidgets('${area.name} fits 320 dp at a 1.6 text scale',
          (tester) async {
        // `bootPlatform` leaves `FlutterError.onError` alone, so any overflow
        // on any of these four surfaces fails the test by itself — there is no
        // suppression in this file.
        final router = await bootPlatform(
          tester,
          platformContainer(superAdmin),
          width: 320,
          height: 900,
          textScale: 1.6,
        );

        router.go(area.route);
        await settlePlatform(tester);

        expect(locationOf(router), area.route);
        expect(find.byType(PlatformNavigationBar), findsOneWidget);
        // The label is rendered in full — not abbreviated into fitting.
        expect(navLabel(destinationFor(area)), findsOneWidget);
      });
    }

    testWidgets('the bar grows with the text rather than clipping it',
        (tester) async {
      await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 320,
        height: 900,
      );
      final normal = tester.getSize(find.byType(PlatformNavigationBar)).height;

      await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 320,
        height: 900,
        textScale: 1.6,
      );
      final scaled = tester.getSize(find.byType(PlatformNavigationBar)).height;

      expect(scaled, greaterThan(normal),
          reason: 'a fixed-height bar would have to shrink or clip the label');
    });
  });

  group('reduced motion', () {
    testWidgets('the shell is immediate and still correct', (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin),
        width: 390,
        reduceMotion: true,
      );

      expect(find.byType(PlatformOverviewPage), findsOneWidget);

      await tester.tap(navItem(destinationFor(PlatformArea.tenants)));
      // One frame, not a settle: with animations disabled the destination is
      // there on the frame the tap produced.
      await tester.pump();

      expect(locationOf(router), PlatformArea.tenants.route);
      expect(find.byType(PlatformTenantsPage), findsOneWidget);
      expect(isSelected(tester, destinationFor(PlatformArea.tenants)), isTrue);

      // The destination is a real screen since Point 6, so its repository read
      // is in flight. Drained here so the test does not end on a pending
      // timer — the assertions above are about the frame the tap produced and
      // are unaffected.
      await settlePlatform(tester);
    });
  });
}
