import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/app_info.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/app_version/data/app_version_providers.dart';
import 'package:mtm/features/app_version/data/mock_app_version_repository.dart';
import 'package:mtm/features/app_version/domain/app_version_gate_store.dart';
import 'package:mtm/features/app_version/domain/app_version_models.dart';
import 'package:mtm/features/app_version/domain/app_version_repository.dart';
import 'package:mtm/features/app_version/domain/update_channel.dart';
import 'package:mtm/features/app_version/presentation/upgrade_required_page.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/l10n/strings.dart';

/// Forced upgrade is a *blocking* state, so these tests are mostly about
/// what must NOT happen: the app must not open a route while the gate is
/// shut, and a check that cannot complete must not be mistaken for
/// permission to pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the gate', () {
    test('an untouched build opens the app exactly as before', () async {
      final repo = _FakeVersionRepo(const Success(_supported));
      final container = _containerWith(repo);

      expect(container.read(appVersionProvider).blocksApp, isFalse);
      await _settle();

      expect(container.read(appVersionProvider).status,
          AppVersionStatus.supported);
      expect(repo.calls, 1, reason: 'one launch check, no extras');
    });

    test('a launch check that reaches nothing still opens the app', () async {
      // The field app is offline-first. Refusing to start because a version
      // check timed out would be a worse bug than running an old build.
      final container = _containerWith(_FakeVersionRepo(const Offline()));
      container.read(appVersionProvider);
      await _settle();

      expect(container.read(appVersionProvider).blocksApp, isFalse);
    });

    test('a launch check that fails still opens the app', () async {
      final container = _containerWith(_FakeVersionRepo(const Failure('boom')));
      container.read(appVersionProvider);
      await _settle();

      expect(container.read(appVersionProvider).blocksApp, isFalse);
    });

    test('an unsupported build shuts the gate', () async {
      final container = _containerWith(_FakeVersionRepo(const Success(
        AppVersionSupport(supported: false, minimumVersion: '1.4.0'),
      )));
      container.read(appVersionProvider);
      await _settle();

      final state = container.read(appVersionProvider);
      expect(state.status, AppVersionStatus.upgradeRequired);
      expect(state.blocksApp, isTrue);
      expect(state.minimumVersion, '1.4.0');
    });

    test('a retry that cannot complete keeps the gate shut', () async {
      final repo = _FakeVersionRepo(const Success(_unsupported));
      final container = _containerWith(repo);
      container.read(appVersionProvider);
      await _settle();

      repo.answer = const Offline();
      await container.read(appVersionProvider.notifier).check();

      final state = container.read(appVersionProvider);
      expect(state.status, AppVersionStatus.checkFailed);
      expect(state.blocksApp, isTrue,
          reason: 'a failed check is not permission to pass');
      // The versions already known survive the failed re-check, so the
      // screen keeps its content.
      expect(state.minimumVersion, '1.4.0');
    });

    test('a retry that succeeds opens the gate', () async {
      final repo = _FakeVersionRepo(const Success(_unsupported));
      final container = _containerWith(repo);
      container.read(appVersionProvider);
      await _settle();
      expect(container.read(appVersionProvider).blocksApp, isTrue);

      repo.answer = const Success(_supported);
      await container.read(appVersionProvider.notifier).check();

      expect(container.read(appVersionProvider).blocksApp, isFalse);
    });
  });

  group('the mock development trigger', () {
    test('defaults to supported, so a normal build is unaffected', () async {
      final r = await MockAppVersionRepository().checkSupport();
      expect(r.isSuccess, isTrue);
      expect((r as Success<AppVersionSupport>).data.supported, isTrue);
    });

    test('the upgradeRequired scenario answers like a 426', () async {
      final r = await MockAppVersionRepository(
        scenario: AppVersionScenario.upgradeRequired,
        latency: Duration.zero,
      ).checkSupport();
      final support = (r as Success<AppVersionSupport>).data;
      expect(support.supported, isFalse);
      expect(support.minimumVersion, isNotNull);
    });

    test('an unrecognised dart-define is ignored, not fatal', () {
      // `String.fromEnvironment` is empty in tests, which is exactly the
      // "not set" case the parser has to survive.
      expect(
          AppVersionScenario.fromEnvironment(), AppVersionScenario.supported);
    });
  });

  group('the screen', () {
    testWidgets('blocks every route while the gate is shut', (tester) async {
      final container = _containerWith(_FakeVersionRepo(
        const Success(_unsupported),
      ));
      final router = container.read(appRouterProvider);
      await tester.pumpWidget(_app(container, router));
      // `Duration.zero` rather than a bare pump: the router now builds an
      // auth gate beside the upgrade gate, and resolving that session — even
      // with no latency — schedules a zero-duration Riverpod task that a
      // pump with no elapsed time would leave pending.
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.byType(UpgradeRequiredPage), findsOneWidget);

      // Every way in is a way back to the same screen.
      for (final location in ['/home', '/detachment/d1/team', '/more']) {
        router.go(location);
        await tester.pump(Duration.zero);
        await tester.pump();
        expect(find.byType(UpgradeRequiredPage), findsOneWidget,
            reason: '$location got past the gate');
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          UpgradeRequiredPage.location,
        );
      }
    });

    testWidgets('offers no skip, no later, no close and no back',
        (tester) async {
      final container = _containerWith(_FakeVersionRepo(
        const Success(_unsupported),
      ));
      await tester
          .pumpWidget(_app(container, container.read(appRouterProvider)));
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
      expect(find.text(S.close), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);

      // The system back gesture is refused.
      final scopes = tester.widgetList<PopScope<dynamic>>(
        find.byType(PopScope<dynamic>),
      );
      expect(scopes.any((s) => !s.canPop), isTrue);
    });

    testWidgets('shows both versions and the two actions', (tester) async {
      final container = _containerWith(_FakeVersionRepo(
        const Success(_unsupported),
      ));
      await tester
          .pumpWidget(_app(container, container.read(appRouterProvider)));
      await tester.pump(Duration.zero);
      await tester.pump();
      // Past the route transition. Since the launch surface became the
      // Leader intro it carries the Arabic wordmark, so an assertion taken
      // mid-cross-fade sees the outgoing screen's copy as well as this one's.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(S.upgradeTitle), findsOneWidget);
      expect(find.text(S.productNameEn), findsOneWidget);
      expect(find.text(S.productNameAr), findsOneWidget);
      expect(find.textContaining('MTM'), findsNothing);
      expect(find.text(S.upgradeCurrentVersion), findsOneWidget);
      expect(find.text(AppInfo.version), findsOneWidget);
      expect(find.text(S.upgradeMinimumVersion), findsOneWidget);
      expect(find.text('1.4.0'), findsOneWidget);
      expect(find.text(S.upgradeAction), findsOneWidget);
      expect(find.text(S.retry), findsOneWidget);
    });

    testWidgets('a failed re-check stays on the screen with a retry',
        (tester) async {
      final repo = _FakeVersionRepo(const Success(_unsupported));
      final container = _containerWith(repo);
      await tester
          .pumpWidget(_app(container, container.read(appRouterProvider)));
      await tester.pump(Duration.zero);
      await tester.pump();

      repo.answer = const Offline();
      await tester.tap(find.text(S.retry));
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.byType(UpgradeRequiredPage), findsOneWidget);
      expect(find.text(S.upgradeCheckFailedTitle), findsOneWidget);
      expect(find.text(S.upgradeCheckFailedBody), findsOneWidget);
      expect(find.text(S.retry), findsOneWidget);
      // The way forward is still one tap away.
      expect(find.text(S.upgradeAction), findsOneWidget);
    });

    testWidgets(
        'renders in dark, and animates nothing at the lowest '
        'performance level', (tester) async {
      final container = _containerWith(_FakeVersionRepo(
        const Success(_unsupported),
      ));
      await tester.pumpWidget(_app(
        container,
        container.read(appRouterProvider),
        mode: ThemeMode.dark,
        level: MotionLevel.performance,
      ));
      await tester.pump(Duration.zero);
      await tester.pump();
      // Point 3: the app boots on `StartupPage` and the gate's verdict lands a
      // microtask later, so the *route change* onto this screen is in flight
      // here. Let it finish before asking what is still animating — a looping
      // animation, which is what this test is about, would outlive it.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(UpgradeRequiredPage), findsOneWidget);
      expect(find.text(S.upgradeTitle), findsOneWidget);
      // No looping ambience: the checking spinner is the only candidate on
      // this screen and it is not built at this level.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Nothing is still in flight — a settled tree with no pending frames.
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('Arabic brand stays joined at 320dp and 1.6x text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final container = _containerWith(_FakeVersionRepo(
        const Success(_unsupported),
      ));
      await tester
          .pumpWidget(_app(container, container.read(appRouterProvider)));
      await tester.pump(Duration.zero);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final arabicBrand = tester.widget<Text>(find.text(S.productNameAr));
      expect(arabicBrand.style?.letterSpacing, 0);
      expect(find.textContaining('MTM'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the persisted gate (offline-first restart)', () {
    test('case 1: a first launch, offline, never refused, still opens',
        () async {
      final store = _FakeGateStore();
      final container =
          _containerWith(_FakeVersionRepo(const Offline()), gate: store);
      container.read(appVersionProvider);
      await _pumpEventLoop();

      expect(container.read(appVersionProvider).blocksApp, isFalse);
      expect(store.reads, 1, reason: 'the gate is consulted at launch');
      expect(store.writes, 0, reason: 'an offline check writes no verdict');
      expect(store.record, isNull);
    });

    test('case 2: a build already refused stays blocked on an offline relaunch',
        () async {
      // Written on a previous run, about the build that is running now.
      final store = _FakeGateStore(
        record: const PersistedUpgradeGate(
          blockedVersion: AppInfo.buildIdentity,
          minimumVersion: '1.4.0',
        ),
      );
      // The network cannot be reached this launch.
      final container =
          _containerWith(_FakeVersionRepo(const Offline()), gate: store);
      container.read(appVersionProvider);
      await _pumpEventLoop();

      final state = container.read(appVersionProvider);
      expect(state.blocksApp, isTrue,
          reason: 'a relaunch must not walk past a 426 it already saw');
      expect(state.status, AppVersionStatus.checkFailed,
          reason: 'restored-then-offline: blocked, with a retry');
      expect(state.minimumVersion, '1.4.0',
          reason: 'the persisted floor still feeds the screen offline');
    });

    test('a 426 persists the verdict, keyed to the installed build identity',
        () async {
      final store = _FakeGateStore();
      final container = _containerWith(
        _FakeVersionRepo(const Success(_unsupported)),
        gate: store,
      );
      container.read(appVersionProvider);
      await _pumpEventLoop();

      expect(container.read(appVersionProvider).blocksApp, isTrue);
      expect(store.writes, 1);
      expect(store.record?.blockedVersion, AppInfo.buildIdentity);
      expect(store.record?.minimumVersion, '1.4.0');
    });

    test('a supported check clears any stored verdict', () async {
      final store = _FakeGateStore(
        record:
            const PersistedUpgradeGate(blockedVersion: AppInfo.buildIdentity),
      );
      final container = _containerWith(
        _FakeVersionRepo(const Success(_supported)),
        gate: store,
      );
      container.read(appVersionProvider);
      await _pumpEventLoop();

      expect(container.read(appVersionProvider).blocksApp, isFalse);
      expect(store.record, isNull, reason: 'the build is supported again');
      expect(store.clears, greaterThanOrEqualTo(1));
    });

    test('a stale verdict about another build is ignored and dropped',
        () async {
      final store = _FakeGateStore(
        record: const PersistedUpgradeGate(blockedVersion: '0.0.1-old'),
      );
      final container =
          _containerWith(_FakeVersionRepo(const Offline()), gate: store);
      container.read(appVersionProvider);
      await _pumpEventLoop();

      expect(container.read(appVersionProvider).blocksApp, isFalse,
          reason: 'installing a newer build must not inherit the old gate');
      expect(store.record, isNull, reason: 'the stale record is cleared');
      expect(store.clears, 1);
    });

    test(
        'a verdict about the same version but a different build number is '
        'not inherited', () async {
      // Same display version, one build number back: a hotfix rebuild that
      // kept the SemVer. It is a different installed binary, so a 426 the
      // old build saw must not block this one.
      const olderBuild = '${AppInfo.version}+0';
      expect(olderBuild, isNot(AppInfo.buildIdentity));
      final store = _FakeGateStore(
        record: const PersistedUpgradeGate(
          blockedVersion: olderBuild,
          minimumVersion: '1.4.0',
        ),
      );
      final container =
          _containerWith(_FakeVersionRepo(const Offline()), gate: store);
      container.read(appVersionProvider);
      await _pumpEventLoop();

      expect(container.read(appVersionProvider).blocksApp, isFalse,
          reason: 'a new build number is a new binary');
      expect(store.record, isNull, reason: 'the stale record is cleared');
    });

    test('a failed re-check does not overwrite the stored verdict', () async {
      final store = _FakeGateStore();
      final repo = _FakeVersionRepo(const Success(_unsupported));
      final container = _containerWith(repo, gate: store);
      container.read(appVersionProvider);
      await _pumpEventLoop();
      expect(store.record?.blockedVersion, AppInfo.buildIdentity);
      final writesAfter426 = store.writes;

      repo.answer = const Offline();
      await container.read(appVersionProvider.notifier).check();

      expect(store.writes, writesAfter426, reason: 'offline writes nothing');
      expect(store.record?.blockedVersion, AppInfo.buildIdentity,
          reason: 'the last real answer survives');
    });

    test('a relaunch over the same store stays blocked with no network',
        () async {
      final store = _FakeGateStore();

      // Run one: a real 426 lands and is persisted.
      final first = _containerWith(
        _FakeVersionRepo(const Success(_unsupported)),
        gate: store,
      );
      first.read(appVersionProvider);
      await _pumpEventLoop();
      expect(first.read(appVersionProvider).blocksApp, isTrue);
      first.dispose();

      // Run two: fresh container, same store, network unreachable.
      final second =
          _containerWith(_FakeVersionRepo(const Offline()), gate: store);
      second.read(appVersionProvider);
      await _pumpEventLoop();

      expect(second.read(appVersionProvider).blocksApp, isTrue);
    });

    test('an unreadable store fails open rather than blocking', () async {
      final store = _FakeGateStore(failReads: true);
      final container =
          _containerWith(_FakeVersionRepo(const Offline()), gate: store);
      container.read(appVersionProvider);
      await _pumpEventLoop();

      expect(container.read(appVersionProvider).blocksApp, isFalse,
          reason: '"we could not read the flag" is not "you are blocked"');
    });
  });

  group('the update destination (client-owned)', () {
    test('resolves from UpdateChannel, needing nothing from the backend', () {
      const dest = UpdateDestination();
      final resolved = dest.resolvedDestination();
      // Never empty, never dependent on a wire value: it is whatever this
      // client was shipped to update from.
      expect(resolved, isNotEmpty);
      expect(resolved, UpdateChannel.forPlatform(defaultTargetPlatform));
    });

    test(
        'an updateUrl on the wire is ignored — the destination stays '
        'client-owned', () {
      // A 426 body that tries to name its own update URL must not be able
      // to redirect the user off-store.
      final support = AppVersionSupport.fromJson(const {
        'supported': false,
        'minimumVersion': '1.4.0',
        'updateUrl': 'https://evil.test/app',
      });
      expect(support.minimumVersion, '1.4.0');
      expect(support.toJson().containsKey('updateUrl'), isFalse);
      expect(
        const UpdateDestination().resolvedDestination(),
        UpdateChannel.forPlatform(defaultTargetPlatform),
      );
    });

    test('open() copies the resolved destination and reports what it did',
        () async {
      final messages = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        messages.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      const dest = UpdateDestination();
      final outcome = await dest.open();

      expect(outcome, UpdateLaunchOutcome.copied);
      final setData =
          messages.firstWhere((m) => m.method == 'Clipboard.setData');
      expect((setData.arguments as Map)['text'], dest.resolvedDestination());
    });

    test('UpdateChannel.forPlatform never returns empty', () {
      for (final p in TargetPlatform.values) {
        expect(UpdateChannel.forPlatform(p), isNotEmpty, reason: '$p');
      }
    });

    test('the controller opens the destination with no backend url', () async {
      final container = _containerWith(_FakeVersionRepo(const Success(
        AppVersionSupport(supported: false, minimumVersion: '1.4.0'),
      )));
      container.read(appVersionProvider);
      await _pumpEventLoop();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final outcome = await container
          .read(appVersionProvider.notifier)
          .openUpdateDestination();
      expect(outcome, UpdateLaunchOutcome.copied);
    });
  });

  test('the version identity does not drift from pubspec', () {
    // The screen shows `AppInfo.version` and the persisted gate is keyed on
    // `AppInfo.buildIdentity`; neither may lie about which build is running.
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final full = line.split(':')[1].trim(); // e.g. 1.0.0+1
    expect(AppInfo.version, full.split('+').first);
    expect(AppInfo.buildIdentity, full);
  });
}

const _supported = AppVersionSupport(supported: true);
const _unsupported = AppVersionSupport(
  supported: false,
  minimumVersion: '1.4.0',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// The launch check now has one more `await` in front of it (the persisted
/// gate read), so launch-path tests drain a few event-loop turns rather than
/// exactly one.
Future<void> _pumpEventLoop() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A minimal signed-in session for the router's auth gate. Nothing in this
/// file asserts anything about it.
const _signedIn = AuthUser(
  id: 'u_1',
  name: 'مشرف',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(),
  orgName: 'MTM',
);

ProviderContainer _containerWith(
  AppVersionRepository repo, {
  AppVersionGateStore? gate,
}) {
  final container = ProviderContainer(
    overrides: [
      appVersionRepositoryProvider.overrideWithValue(repo),
      if (gate != null) appVersionGateStoreProvider.overrideWithValue(gate),
      // The router reads the session too — its auth gate is built alongside
      // the upgrade gate. Answered here without the mock repository's
      // simulated latency, so these tests keep their exact pump counts and
      // leave no timer pending. A signed-in session is the strict case: the
      // upgrade gate must shut the app for an authenticated user as well.
      currentUserResultProvider.overrideWith(
        (ref) async => const Success<AuthUser?>(_signedIn),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Latency-free [AppVersionGateStore] that records what it was asked to do.
/// A second container built over the *same instance* is a relaunch.
class _FakeGateStore implements AppVersionGateStore {
  _FakeGateStore({this.record, this.failReads = false});

  PersistedUpgradeGate? record;
  final bool failReads;
  int reads = 0;
  int writes = 0;
  int clears = 0;

  @override
  Future<PersistedUpgradeGate?> read() async {
    reads++;
    if (failReads) throw Exception('store unreadable');
    return record;
  }

  @override
  Future<void> write(PersistedUpgradeGate gate) async {
    writes++;
    record = gate;
  }

  @override
  Future<void> clear() async {
    clears++;
    record = null;
  }
}

/// The app as `main.dart` assembles it: RTL, one motion level for the whole
/// subtree, the real router.
Widget _app(
  ProviderContainer container,
  GoRouter router, {
  ThemeMode mode = ThemeMode.light,
  MotionLevel level = MotionLevel.balanced,
}) =>
    UncontrolledProviderScope(
      container: container,
      child: MotionScope(
        level: level,
        child: MaterialApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(PaletteId.medical),
          darkTheme: AppTheme.dark(PaletteId.medical),
          themeMode: mode,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

class _FakeVersionRepo implements AppVersionRepository {
  _FakeVersionRepo(this.answer);

  Result<AppVersionSupport> answer;
  int calls = 0;

  @override
  Future<Result<AppVersionSupport>> checkSupport() async {
    calls++;
    return answer;
  }
}
