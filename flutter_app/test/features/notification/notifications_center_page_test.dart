import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/demo/data/demo_workspace.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/detachment/domain/detachment_models.dart';
import 'package:mtm/features/home/data/home_providers.dart';
import 'package:mtm/features/notification/data/notification_providers.dart';
import 'package:mtm/features/notification/domain/notification_models.dart';
import 'package:mtm/features/notification/domain/notification_repository.dart';
import 'package:mtm/features/notification/presentation/notifications_center_page.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/domain/shift_repository.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/l10n/strings.dart';

/// The screen states nobody can produce on a device: a notification whose
/// record was deleted between the load and the tap, a row the app has nowhere
/// to open, and a bar action that must appear and disappear with the unread
/// count. Ordinary layout, scrolling and navigation are not tested here.

const _det = 'd1';
const _operator = Capabilities(scoped: {_det: Cap.scoped});

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

final _now = DateTime.now();

AppNotification _shiftRow() => AppNotification(
      id: 'shiftUnderstaffed:sh_gone',
      kind: NotificationKind.shiftUnderstaffed,
      occurredAt: _now.add(const Duration(hours: 2)),
      count: 2,
      recordLabel: 'مركز الشعلان',
      target: const ShiftTarget(detachmentId: _det, shiftId: 'sh_gone'),
    );

/// A row with no destination — the shape a server-sent announcement would
/// take. Nothing the current domain derives is informational, but the screen
/// has to render one correctly the day one arrives.
AppNotification _informationalRow() => AppNotification(
      id: 'info:1',
      kind: NotificationKind.syncFailed,
      occurredAt: _now,
      recordLabel: 'تغيير غير مزامن',
    );

class _FakeRepository implements NotificationRepository {
  _FakeRepository(this.rows);
  final List<AppNotification> rows;

  @override
  Future<Result<List<AppNotification>>> feed(String detachmentId) async =>
      Success(rows);
}

/// Every shift lookup misses — the record was deleted after the feed was
/// built.
class _MissingShifts extends Fake implements ShiftRepository {
  int lookups = 0;

  @override
  Future<Result<Shift>> byId(String id) async {
    lookups++;
    return const Failure('غير موجود', code: 'not_found');
  }
}

Future<_MissingShifts> _pump(
  WidgetTester tester, {
  required List<AppNotification> rows,
}) async {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final shifts = _MissingShifts();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilitiesProvider.overrideWithValue(_operator),
        // This world holds no Customer Demo session, so the repository
        // providers serve the ordinary repositories and nothing reaches for
        // the authentication mock.
        isCustomerDemoSessionProvider.overrideWith((ref) => false),
        tenantFeatureAvailableProvider.overrideWith((ref, key) => true),
        dashboardDetachmentsProvider
            .overrideWith((ref) async => const Success([_detachment])),
        notificationRepositoryProvider.overrideWithValue(_FakeRepository(rows)),
        shiftRepositoryProvider.overrideWithValue(shifts),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: NotificationsCenterPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shifts;
}

void main() {
  testWidgets('a notification whose record is gone says so instead of crashing',
      (tester) async {
    final shifts = await _pump(tester, rows: [_shiftRow()]);

    await tester
        .tap(find.byKey(const Key('notification-shiftUnderstaffed:sh_gone')));
    await tester.pumpAndSettle();

    expect(shifts.lookups, 1, reason: 'the record is re-read at tap time');
    expect(find.text(S.notificationsTargetGone), findsOneWidget);
    // No sheet opened on a record that is not there.
    expect(find.text(S.manageShiftTitle), findsNothing);
  });

  testWidgets('a row with nowhere to go draws no chevron', (tester) async {
    await _pump(tester, rows: [_informationalRow()]);

    expect(find.byKey(const Key('notification-info:1')), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
  });

  testWidgets('an informational row still stops counting itself unread',
      (tester) async {
    await _pump(tester, rows: [_informationalRow()]);
    expect(find.byKey(const Key('notifications-mark-all')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notification-info:1')));
    await tester.pumpAndSettle();

    // The bar action is rendered only while something is unread, so its
    // disappearance is the badge going to zero.
    expect(find.byKey(const Key('notifications-mark-all')), findsNothing);
  });

  testWidgets('mark all read clears every row and then withdraws itself',
      (tester) async {
    await _pump(tester, rows: [_shiftRow(), _informationalRow()]);

    await tester.tap(find.byKey(const Key('notifications-mark-all')));
    await tester.pumpAndSettle();

    expect(find.text(S.notificationsMarkAllReadDone), findsOneWidget);
    expect(find.byKey(const Key('notifications-mark-all')), findsNothing);
    // The rows stay — read is not dismissed.
    expect(find.byKey(const Key('notification-info:1')), findsOneWidget);
  });

  testWidgets('an empty feed is a designed state, not a blank page',
      (tester) async {
    await _pump(tester, rows: const []);

    expect(find.byKey(const Key('notifications-empty')), findsOneWidget);
    expect(find.text(S.notificationsEmptyTitle), findsOneWidget);
    expect(find.byKey(const Key('notifications-mark-all')), findsNothing);
  });
}
