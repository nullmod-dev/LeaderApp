import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/demo/data/demo_workspace.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/core/widgets/offline_banner.dart';
import 'package:mtm/features/detachment/domain/detachment_models.dart';
import 'package:mtm/features/detachment/domain/storage_status.dart';
import 'package:mtm/features/home/data/home_providers.dart';
import 'package:mtm/features/home/domain/home_models.dart';
import 'package:mtm/core/widgets/forward_chevron.dart';
import 'package:mtm/core/widgets/reading_column.dart';
import 'package:mtm/features/home/presentation/home_page.dart';
import 'package:mtm/features/notification/data/notification_providers.dart';
import 'package:mtm/features/notification/domain/notification_models.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/l10n/strings.dart';

/// The dashboard states a person cannot reliably produce by hand: no
/// detachment at all, a day with no shift, a load that failed, an offline
/// device with nothing cached, queued work, a conflict waiting, and a
/// volunteer's restricted view.

const _det = 'd1';

const _detachment = Detachment(
  id: _det,
  detachmentGroupId: 't1',
  name: 'مفرزة دمشق المركزية',
  region: 'دمشق',
  mainCenter: 'مركز الشعلان',
  memberCount: 10,
  weeklyShiftCount: 7,
  coveragePercent: 80,
  status: DetachmentStatus.active,
);

const _second = Detachment(
  id: 'd2',
  detachmentGroupId: 't1',
  name: 'مفرزة ريف دمشق',
  region: 'ريف دمشق',
  mainCenter: 'مركز التل',
  memberCount: 6,
  weeklyShiftCount: 4,
  coveragePercent: 70,
  status: DetachmentStatus.active,
);

const _oneDetachment = Success<List<Detachment>>([_detachment]);

const _operator = Capabilities(scoped: {_det: Cap.scoped});
const _volunteer = Capabilities(
  scoped: {
    _det: {Cap.detachmentView, Cap.memberView}
  },
);

TeamMember _member(String id, AttendanceState state) => TeamMember(
      id: id,
      name: 'عضو $id',
      initials: 'ع',
      role: TeamRole.member,
      detachmentId: _det,
      attendance: state,
    );

/// The one instant every one of these tests runs at.
///
/// The fixtures below are built as offsets from it and the dashboard reads it
/// through [clockProvider], so "a shift running now" and "a shift four hours
/// ahead of now" mean the same thing at 03:00 as at 23:00. Before this was
/// pinned the suite failed after roughly 20:00: the "+4 hours" fixture in the
/// two-understaffed-shifts test rolled its start past midnight while its date
/// stayed on the current day, so the shift resolved to a *finished*
/// early-morning slot and its understaffed alert — which the dashboard
/// correctly withholds for a shift that has already ended — was no longer
/// raised.
final _now = DateTime(2026, 9, 6, 10, 0);

/// A shift that is running at [_now].
Shift _runningNow({int needed = 2, List<TeamMember>? attendees}) {
  final now = _now;
  final start = now.subtract(const Duration(hours: 1));
  final end = now.add(const Duration(hours: 2));
  return Shift(
    id: 'sh_now',
    detachmentId: _det,
    date: dateOnly(start),
    centerName: 'مركز الشعلان',
    startMinutes: start.hour * 60 + start.minute,
    endMinutes: end.hour * 60 + end.minute,
    needed: needed,
    attendees: attendees ??
        [
          _member('a', AttendanceState.checkedIn),
          _member('b', AttendanceState.notCheckedIn),
        ],
  );
}

HomeSummary _summary({
  List<Shift> shifts = const [],
  Detachment detachment = _detachment,
}) =>
    HomeSummary(
      detachmentId: detachment.id,
      detachmentName: detachment.name,
      region: detachment.region,
      mainCenter: detachment.mainCenter,
      shifts: shifts,
      rosterCount: 10,
      storageStatus: StorageStatus.healthy,
      lowStockCount: 0,
      expiringSoonCount: 0,
    );

Future<void> _pump(
  WidgetTester tester, {
  Result<List<Detachment>> detachments = const Success([]),
  Result<HomeSummary>? summary,
  Capabilities capabilities = _operator,
  List<PendingOperation> outbox = const [],
  DateTime? now,
  double width = 540,
  double textScale = 1,
}) async {
  // A tall surface so the whole dashboard is laid out: several assertions
  // below are about a tile being *absent*, which only means something when
  // the section it would sit in is on screen.
  tester.view.physicalSize = Size(width * 2, 2400 * textScale);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Pinned, so nothing on this screen depends on the hour the suite
        // happens to run at. Production still reads `DateTime.now`.
        clockProvider.overrideWithValue(() => now ?? _now),
        // This world holds no Customer Demo session, so the repository
        // providers serve the ordinary repositories and nothing reaches for
        // the authentication mock.
        isCustomerDemoSessionProvider.overrideWith((ref) => false),
        capabilitiesProvider.overrideWithValue(capabilities),
        // This isolated dashboard harness intentionally has no auth session.
        // Declare the product entitlement explicitly rather than letting a
        // missing tenant context silently imply legacy defaults.
        tenantFeatureAvailableProvider.overrideWith((ref, key) => true),
        outboxStoreProvider
            .overrideWithValue(InMemoryOutboxStore(seed: outbox)),
        dashboardDetachmentsProvider.overrideWith((ref) async => detachments),
        // The app bar's notification bell reads a feed of its own, composed
        // from the shift and inventory repositories. These tests are about
        // the dashboard, so the feed is stubbed empty rather than left to
        // fetch — the Notifications Center has its own tests.
        notificationSourceProvider.overrideWith(
          (ref, id) async => const Success<List<AppNotification>>([]),
        ),
        // Id-aware on purpose: switching detachment must actually re-point
        // the screen, which a fixed answer would hide.
        homeSummaryProvider.overrideWith(
          (ref, id) async =>
              summary ??
              Success(_summary(
                detachment: id == _second.id ? _second : _detachment,
              )),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: HomePage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a session with no detachment gets a designed state, not an '
      'empty screen or an error', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('dashboard-no-detachment')), findsOneWidget);
    expect(find.text(S.dashboardNoDetachmentTitle), findsOneWidget);
    // Nothing pretends to be operational data.
    expect(find.text(S.activeShift), findsNothing);
  });

  testWidgets(
      'an empty day is one card, one sentence, and a calm confirmation',
      (tester) async {
    await _pump(tester, detachments: _oneDetachment);

    // The audit's quiet-day render had three surfaces for one absence: «لا
    // شفتات اليوم في هذه المفرزة», «لا شفت قادم مجدول», and an all-clear
    // card above them. One card now, and the two absences are one sentence.
    expect(find.byKey(const Key('dashboard-today')), findsOneWidget);
    expect(find.text(S.dashboardNoShiftsAtAll), findsOneWidget);
    expect(find.text(S.dashboardNoShiftsToday), findsNothing);
    expect(find.text(S.dashboardNoNextShift), findsNothing);
    expect(find.byKey(const Key('dashboard-view-schedule')), findsOneWidget);

    // Nothing is wrong, and the screen says that once — inside the card that
    // reports the day, not as a card of its own.
    expect(find.byKey(const Key('dashboard-quiet')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('dashboard-today')),
        matching: find.byKey(const Key('dashboard-quiet')),
      ),
      findsOneWidget,
    );
    // …and the attention section does not exist at all when nothing is
    // raised.
    expect(find.text(S.needsYourDecision), findsNothing);
    expect(find.byKey(const Key('dashboard-alerts')), findsNothing);
  });

  testWidgets('a running shift leads the screen with real counts',
      (tester) async {
    await _pump(
      tester,
      detachments: _oneDetachment,
      summary: Success(_summary(shifts: [_runningNow()])),
    );

    expect(find.text(S.activeShift), findsOneWidget);
    expect(find.text('مركز الشعلان'), findsWidgets);
    // One of two assigned has checked in; the other is still open.
    expect(find.textContaining('١'), findsWidgets);
    expect(
        find.byKey(const Key('dashboard-open-current-shift')), findsOneWidget);
  });

  testWidgets('a summary that fails offers a retry instead of a half screen',
      (tester) async {
    await _pump(
      tester,
      detachments: _oneDetachment,
      summary: const Failure('boom', code: 'server_error'),
    );

    expect(find.text(S.retry), findsOneWidget);
    expect(find.text(S.activeShift), findsNothing);
  });

  testWidgets('offline with nothing cached is a state, not a crash',
      (tester) async {
    await _pump(
      tester,
      detachments: _oneDetachment,
      summary: const Offline(),
    );

    expect(find.text(S.offlineTitle), findsOneWidget);
    expect(find.text(S.retry), findsOneWidget);
  });

  testWidgets('offline with a cached copy still shows the day, marked stale',
      (tester) async {
    await _pump(
      tester,
      detachments: _oneDetachment,
      summary: Offline(cached: _summary(shifts: [_runningNow()])),
    );

    expect(find.text(S.activeShift), findsOneWidget);
    expect(find.byType(StaleBadge), findsOneWidget);
  });

  testWidgets(
      'queued work and a conflict are raised as the user\'s own, '
      'whatever their grants', (tester) async {
    await _pump(
      tester,
      detachments: _oneDetachment,
      capabilities: _volunteer,
      outbox: [
        PendingOperation.create(kind: 'shift.assign', idFactory: () => 'c1')
            .copyWith(state: SyncState.conflict),
        PendingOperation.create(
            kind: 'inventory.movement.add', idFactory: () => 'p1'),
      ],
    );

    expect(
      find.byKey(const Key('dashboard-alert-needsReview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('dashboard-alert-pendingSync')),
      findsOneWidget,
    );
  });

  testWidgets('a volunteer sees no management shortcuts and no shift action',
      (tester) async {
    await _pump(
      tester,
      detachments: _oneDetachment,
      capabilities: _volunteer,
      summary: Success(_summary(shifts: [_runningNow(needed: 5)])),
    );

    // The shift is reported…
    expect(find.text(S.activeShift), findsOneWidget);
    // …but nothing offers an action their grants would not carry.
    expect(
      find.byKey(const Key('dashboard-open-current-shift')),
      findsNothing,
    );
    expect(find.byKey(const Key('dashboard-action-stats')), findsNothing);
    // A gap they cannot staff is not raised at them either.
    expect(
      find.byKey(const Key('dashboard-alert-understaffedShift')),
      findsNothing,
    );
    // The roster is theirs to see, so that shortcut stays.
    expect(find.byKey(const Key('dashboard-action-members')), findsOneWidget);
  });

  testWidgets('two shifts short on the same day both get their own row',
      (tester) async {
    final now = _now;
    Shift short(String id, int hoursAhead) {
      final start = now.add(Duration(hours: hoursAhead));
      final end = start.add(const Duration(hours: 2));
      return Shift(
        id: id,
        detachmentId: _det,
        date: dateOnly(now),
        centerName: 'مركز $id',
        startMinutes: start.hour * 60 + start.minute,
        endMinutes: end.hour * 60 + end.minute,
        needed: 4,
        attendees: [_member('a', AttendanceState.checkedIn)],
      );
    }

    // Both rows are the same *kind*; keyed by kind alone they would collide
    // as siblings and take the screen down.
    await _pump(
      tester,
      detachments: _oneDetachment,
      summary: Success(_summary(shifts: [short('sh1', 1), short('sh2', 4)])),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('dashboard-alert-understaffedShift-sh1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('dashboard-alert-understaffedShift-sh2')),
      findsOneWidget,
    );
  });

  testWidgets('one detachment offers no switcher at all', (tester) async {
    await _pump(tester, detachments: _oneDetachment);
    expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
  });

  testWidgets(
      'switching detachment re-points the dashboard at the one '
      'chosen, and the sheet closes rather than the page', (tester) async {
    await _pump(tester, detachments: const Success([_detachment, _second]));
    expect(find.text(_detachment.name), findsOneWidget);

    await tester.tap(find.byIcon(Icons.unfold_more_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard-detachment-d2')));
    await tester.pumpAndSettle();

    // The dashboard is still on screen and now names the chosen detachment.
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text(_second.name), findsOneWidget);
    expect(find.text(_detachment.name), findsNothing);
  });

  testWidgets('several detachments offer the switcher', (tester) async {
    await _pump(tester, detachments: const Success([_detachment, _second]));
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
  });

  testWidgets('the dashboard reads the injected clock, not the wall clock',
      (tester) async {
    // The guard on every assertion above. The instant below is nowhere near
    // whatever day this suite is run on, and the shift is dated on it: if the
    // screen ever went back to calling `DateTime.now()` the shift would be
    // neither today's nor running, and none of this would be on screen.
    final then = DateTime(2027, 3, 15, 10, 0);
    final shift = Shift(
      id: 'sh_then',
      detachmentId: _det,
      date: DateTime(2027, 3, 15),
      centerName: 'مركز الشعلان',
      startMinutes: 9 * 60,
      endMinutes: 12 * 60,
      needed: 2,
      attendees: [_member('a', AttendanceState.checkedIn)],
    );

    await _pump(
      tester,
      detachments: _oneDetachment,
      summary: Success(_summary(shifts: [shift])),
      now: then,
    );

    expect(find.text(S.activeShift), findsOneWidget);
    // Dated on the pinned day, so it counts as today's schedule too — which
    // is what raises the coverage gap.
    expect(
      find.byKey(const Key('dashboard-alert-understaffedShift-sh_then')),
      findsOneWidget,
    );
  });

  group('attendance summary at narrow widths and large text', () {
    // A busy shift: three-digit counts are the widest the counter row gets.
    Shift busy() => _runningNow(
          needed: 150,
          attendees: [
            for (var i = 0; i < 120; i++)
              _member('m$i',
                  i < 108 ? AttendanceState.checkedIn : AttendanceState.absent),
          ],
        );

    for (final scale in [1.6, 2.0]) {
      testWidgets('320dp at ${scale}x lays out without overflow',
          (tester) async {
        await _pump(
          tester,
          detachments: _oneDetachment,
          summary: Success(_summary(shifts: [busy()])),
          width: 320,
          textScale: scale,
        );

        expect(tester.takeException(), isNull);
        final summary = find.byKey(const Key('dashboard-attendance-summary'));
        expect(summary, findsOneWidget);
        // Every figure is still on screen: the label, present over
        // assigned, and each open count.
        expect(
          find.descendant(
              of: summary, matching: find.text(S.attendanceProgress)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: summary, matching: find.text(' / ١٢٠')),
          findsOneWidget,
        );
        expect(
          find.descendant(
              of: summary, matching: find.textContaining(S.shiftNeeded)),
          findsOneWidget,
        );
      });
    }
  });

  // ------------------------------------------------------------------
  // Phase 3A — what the redesign is accountable for.
  // ------------------------------------------------------------------

  group('the attention state', () {
    testWidgets('a raised condition leads the screen, above the day',
        (tester) async {
      await _pump(
        tester,
        detachments: _oneDetachment,
        summary: Success(_summary(shifts: [_runningNow(needed: 5)])),
      );

      expect(find.byKey(const Key('dashboard-alerts')), findsOneWidget);
      expect(find.text(S.needsYourDecision), findsOneWidget);
      // Above the day's card, in paint order and therefore in reading order.
      final attention =
          tester.getTopLeft(find.byKey(const Key('dashboard-alerts')));
      final today = tester.getTopLeft(find.byKey(const Key('dashboard-today')));
      expect(attention.dy, lessThan(today.dy));
      // And the calm strip is not also on screen contradicting it.
      expect(find.byKey(const Key('dashboard-quiet')), findsNothing);
    });

    testWidgets('severity is carried by a word, not only by a colour',
        (tester) async {
      await _pump(
        tester,
        detachments: _oneDetachment,
        summary: Success(_summary(shifts: [_runningNow(needed: 5)])),
      );
      expect(find.text(S.severityImportant), findsOneWidget);
    });

    testWidgets('an alert opens its surface as a row, not as a filled button',
        (tester) async {
      await _pump(
        tester,
        detachments: _oneDetachment,
        summary: Success(_summary(shifts: [_runningNow(needed: 5)])),
      );

      final row =
          find.byKey(const Key('dashboard-alert-understaffedShift-sh_now'));
      expect(row, findsOneWidget);
      // Buttons change state; rows navigate. Every alert destination is a
      // place, and a brand-filled call to action on a warning row was the
      // audit's finding. (Flutter paints `FilledButton.tonal` from the same
      // `FilledButtonTheme`, so "tonal" here was brand green anyway.)
      expect(
        find.descendant(of: row, matching: find.byType(FilledButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(ForwardChevron)),
        findsOneWidget,
      );
    });

    testWidgets(
        'queued work alone is information, and the heading says so rather '
        'than claiming a decision is needed', (tester) async {
      await _pump(
        tester,
        detachments: _oneDetachment,
        outbox: [
          PendingOperation.create(
              kind: 'inventory.movement.add', idFactory: () => 'p1'),
        ],
      );

      expect(find.byKey(const Key('dashboard-alert-pendingSync')),
          findsOneWidget);
      expect(find.text(S.dashboardForInfo), findsWidgets);
      expect(find.text(S.needsYourDecision), findsNothing);
      // It is still not the quiet state — something *is* listed.
      expect(find.byKey(const Key('dashboard-quiet')), findsNothing);
    });
  });

  group('the quiet state', () {
    testWidgets('there is exactly one statement of absence on screen',
        (tester) async {
      await _pump(tester, detachments: _oneDetachment);

      // The three surfaces the audit counted, reduced to one card carrying
      // one sentence and one confirmation.
      expect(find.byKey(const Key('dashboard-quiet')), findsOneWidget);
      expect(find.text(S.dashboardNoShiftsAtAll), findsOneWidget);
      expect(find.text(S.dashboardNoShiftsToday), findsNothing);
      expect(find.text(S.dashboardNoNextShift), findsNothing);
    });

    testWidgets('a quiet day still carries the standing facts', (tester) async {
      await _pump(tester, detachments: _oneDetachment);

      final glance = find.byKey(const Key('dashboard-glance'));
      expect(glance, findsOneWidget);
      // Read from the summary that is already loaded — `rosterCount` is 10 in
      // this fixture — not fetched for the dashboard and not invented.
      expect(
        find.descendant(
          of: glance,
          matching: find.text(S.dashboardRosterMany.replaceFirst('%d', '١٠')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: glance, matching: find.text(S.dashboardShiftsTodayNone)),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: glance, matching: find.text(S.storageStatusHealthy)),
        findsOneWidget,
      );
    });

    testWidgets('a shift running on an otherwise quiet day keeps the hero',
        (tester) async {
      await _pump(
        tester,
        detachments: _oneDetachment,
        summary: Success(_summary(
          shifts: [
            _runningNow(
              attendees: [
                _member('a', AttendanceState.checkedIn),
                _member('b', AttendanceState.checkedIn),
              ],
            )
          ],
        )),
      );

      expect(find.text(S.activeShift), findsOneWidget);
      expect(find.byKey(const Key('dashboard-quiet')), findsOneWidget);
      // The calm strip sits inside the day's card, never as a fourth surface.
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-today')),
          matching: find.byKey(const Key('dashboard-quiet')),
        ),
        findsOneWidget,
      );
    });
  });

  group('nothing on this screen is invented', () {
    testWidgets(
        'the store fact is withheld from a session that may not read the '
        'store, rather than reported as «لا مخزن»', (tester) async {
      await _pump(
        tester,
        detachments: _oneDetachment,
        capabilities: _volunteer,
      );

      final glance = find.byKey(const Key('dashboard-glance'));
      expect(glance, findsOneWidget);
      for (final label in [
        S.storageStatusHealthy,
        S.storageStatusEmpty,
        S.storageStatusLow,
      ]) {
        expect(
          find.descendant(of: glance, matching: find.text(label)),
          findsNothing,
        );
      }
    });

    testWidgets('the glance quotes the summary, so it cannot drift from it',
        (tester) async {
      await _pump(
        tester,
        detachments: _oneDetachment,
        summary: Success(_summary(shifts: [_runningNow()])),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-glance')),
          matching: find.text(S.dashboardShiftsTodayOne),
        ),
        findsOneWidget,
      );
    });
  });

  group('shortcuts save a step or they are not there', () {
    testWidgets('the two that only re-opened permanent navigation are gone',
        (tester) async {
      await _pump(tester, detachments: const Success([_detachment, _second]));

      // `/detachment` is a bottom-navigation branch and `/more/organization`
      // is two taps inside another one. Neither saved a step (audit §9).
      expect(find.byKey(const Key('dashboard-action-detachments')), findsNothing);
      expect(find.byKey(const Key('dashboard-action-org')), findsNothing);
      // The four that jump straight into this detachment's tabs remain.
      expect(find.byKey(const Key('dashboard-action-shifts')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-action-members')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-action-storage')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-action-stats')), findsOneWidget);
    });

    testWidgets('the organisation fact moved onto the page context',
        (tester) async {
      await _pump(tester, detachments: const Success([_detachment, _second]));
      expect(find.byKey(const Key('dashboard-organisation')), findsNothing);
      expect(
        find.text(S.dashboardAmongDetachments.replaceFirst('%d', '٢')),
        findsOneWidget,
      );
      // …and the switcher says its own name rather than being a bare glyph.
      expect(find.text(S.dashboardSwitchAction), findsOneWidget);
    });
  });

  group('the measure policy', () {
    testWidgets('Home is a working column and does not stretch at 900 dp',
        (tester) async {
      await _pump(
        tester,
        detachments: _oneDetachment,
        summary: Success(_summary(shifts: [_runningNow()])),
        width: 900,
      );

      expect(tester.takeException(), isNull);
      final card = tester.getSize(find.byKey(const Key('dashboard-today')));
      // Class B: capped at `kContentMaxWidth`, minus the list's own padding.
      expect(card.width, lessThanOrEqualTo(kContentMaxWidth));
      expect(card.width, greaterThan(kContentMaxWidth - 2 * AppSpacing.lg - 1));
      // Centred, so a wide window gains margins rather than a stretched row.
      final box = tester.getRect(find.byKey(const Key('dashboard-today')));
      expect(box.left, greaterThan(40));
    });

    testWidgets('a phone still gets the full width', (tester) async {
      await _pump(
        tester,
        detachments: _oneDetachment,
        summary: Success(_summary(shifts: [_runningNow()])),
        width: 390,
      );
      final card = tester.getSize(find.byKey(const Key('dashboard-today')));
      expect(card.width, closeTo(390 - 2 * AppSpacing.lg, 1));
    });

    testWidgets('320 dp at 1.6x lays the whole screen out without overflow',
        (tester) async {
      await _pump(
        tester,
        detachments: const Success([_detachment, _second]),
        summary: Success(_summary(shifts: [_runningNow(needed: 5)])),
        width: 320,
        textScale: 1.6,
      );

      expect(tester.takeException(), isNull);
      // Every block of the new hierarchy is present and laid out.
      expect(find.byKey(const Key('dashboard-alerts')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-today')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-glance')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-action-shifts')), findsOneWidget);
      // The shortcut grid keeps at least two columns rather than collapsing
      // into a stack of full-width rows that read as primary actions.
      final shifts =
          tester.getSize(find.byKey(const Key('dashboard-action-shifts')));
      expect(shifts.width, lessThan(320 - 2 * AppSpacing.lg));
    });
  });
}
