import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/app_info.dart';
import 'package:mtm/core/brand/brand_mark.dart';
import 'package:mtm/core/display/display_refresh.dart';
import 'package:mtm/core/display/frame_rate.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_controller.dart';
import 'package:mtm/features/settings/data/frame_rate_provider.dart';
import 'package:mtm/features/settings/data/settings_providers.dart';
import 'package:mtm/features/settings/domain/settings_models.dart';
import 'package:mtm/features/settings/domain/settings_repository.dart';
import 'package:mtm/features/settings/presentation/themes_and_performance_page.dart';

/// The Leader mark: **one** of it, fixed, and no longer a setting.
///
/// The product briefly offered three variants of the lockup on
/// `/more/themes`. This file is the record that the selector is gone and that
/// nothing is left behind it: no picker on the appearance screen, no
/// persisted preference, no runtime switch, no alternate artwork in the
/// bundle, and exactly one asset path spelled anywhere in `lib/`.
///
/// The Android launcher icon is deliberately not a preference either and
/// never was — it is fixed to Clean Layer for everyone in
/// `mipmap-anydpi-v26/ic_launcher.xml`, and nothing in the Dart layer may
/// change it. That file is checked here too, because "the icon and the in-app
/// mark are the same object" is now the whole rule.
class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository();

  ThemeState? stored;
  int writes = 0;

  @override
  Future<Result<ThemeState?>> themePrefs() async => Success(stored);

  @override
  Future<Result<ThemeState>> updateThemePrefs(ThemeState prefs) async {
    writes++;
    stored = prefs;
    return Success(prefs);
  }

  @override
  Future<Result<MotionLevel?>> motionLevel() async => const Success(null);
  @override
  Future<Result<MotionLevel>> updateMotionLevel(MotionLevel level) async =>
      Success(level);
  @override
  Future<Result<FrameRatePreference?>> frameRate() async => const Success(null);
  @override
  Future<Result<FrameRatePreference>> updateFrameRate(
          FrameRatePreference p) async =>
      Success(p);
  @override
  Future<Result<NotificationPrefs>> notificationPrefs() async =>
      throw UnimplementedError();
  @override
  Future<Result<NotificationPrefs>> updateNotificationPrefs(
          NotificationPrefs p) async =>
      throw UnimplementedError();
  @override
  Future<Result<OrgInfo>> orgInfo() async => throw UnimplementedError();
}

ProviderContainer _container(_FakeSettingsRepository repo) {
  final c = ProviderContainer(
    overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  required _FakeSettingsRepository repo,
  double width = 320,
}) async {
  tester.view.physicalSize = Size(width * 3, 3000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    settingsRepositoryProvider.overrideWithValue(repo),
    displayCapabilitiesProvider.overrideWith(
      (ref) async => const DisplayCapabilities(
        supportedRates: [60],
        activeRate: 60,
        canSelectMode: false,
        supportsFrameRateHint: false,
      ),
    ),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: ThemesAndPerformancePage(),
        ),
      ),
    ),
  );
  // Not `pumpAndSettle`: the performance pickers keep an indeterminate
  // spinner until their stored preference lands.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return container;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(DisplayRefresh.channelName),
      (call) async => null,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(DisplayRefresh.channelName), null);
  });

  group('one mark, one path', () {
    test('the mark is Clean Layer and it is on disk', () {
      expect(AppInfo.logoAsset, 'assets/brand/leader_logo_clean_layer.png');
      final file = File(AppInfo.logoAsset);
      expect(file.existsSync(), isTrue, reason: AppInfo.logoAsset);
      expect(file.lengthSync(), greaterThan(1024),
          reason: 'not a placeholder');
    });

    test('no alternate in-app mark is bundled any more', () {
      for (final retired in const [
        'assets/brand/leader_logo_elegant_curve.png',
        'assets/brand/leader_logo_depth.png',
      ]) {
        expect(File(retired).existsSync(), isFalse,
            reason: '$retired was only ever reachable through the selector');
      }
    });

    test('`assets/brand/` is spelled exactly once in lib/', () {
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('assets/brand/')) {
            offenders.add('${file.path}:${i + 1}  ${line.trim()}');
          }
        }
      }
      expect(
        offenders, hasLength(1),
        reason: 'the artwork path belongs to `AppInfo.logoAsset` alone; '
            'everything that draws the mark uses `BrandMark`. Found:\n'
            '${offenders.join('\n')}',
      );
      expect(offenders.single, startsWith('lib/core/app_info.dart:'));
    });

    test('the launcher icon is fixed, and is the same mark', () {
      final icon = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      );
      expect(icon.existsSync(), isTrue);
      final xml = icon.readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      expect(xml, contains('@mipmap/ic_launcher_foreground'));
      expect(xml, contains('@color/ic_launcher_background'));
      // Every density ships the foreground the adaptive icon composes.
      for (final density in const [
        'mdpi',
        'hdpi',
        'xhdpi',
        'xxhdpi',
        'xxxhdpi'
      ]) {
        expect(
          File('android/app/src/main/res/mipmap-$density/'
                  'ic_launcher_foreground.png')
              .existsSync(),
          isTrue,
          reason: density,
        );
      }
    });

    testWidgets('BrandMark draws that asset, and announces nothing',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(child: BrandMark(size: 72)),
        ),
      ));

      final image = tester.widget<Image>(find.byKey(BrandMark.widgetKey));
      expect((image.image as AssetImage).assetName, AppInfo.logoAsset);
      expect(image.excludeFromSemantics, isTrue,
          reason: 'every screen that draws the mark also says the name');
      expect(tester.getSize(find.byKey(BrandMark.widgetKey)),
          const Size(72, 72));
    });
  });

  group('the appearance screen', () {
    testWidgets('offers no mark to pick', (tester) async {
      await _pumpSettings(tester, repo: _FakeSettingsRepository());

      // The retired section, its rows and its copy.
      expect(find.textContaining('شعار'), findsNothing);
      for (final retired in const [
        'الطبقة النظيفة',
        'المنحنى الأنيق',
        'العمق',
      ]) {
        expect(find.text(retired), findsNothing, reason: retired);
      }
      // No artwork is drawn on the settings screen at all any more.
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('still offers everything it is supposed to', (tester) async {
      // The removal must not have taken a neighbour with it.
      await _pumpSettings(tester, repo: _FakeSettingsRepository());
      expect(find.byKey(const Key('themes-eye-protection')), findsOneWidget);
      expect(find.byKey(const Key('themes-appearance')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('nothing is persisted about it', () {
    test('the stored theme carries no logo key', () async {
      const state = ThemeState(
        palette: PaletteId.teal,
        mode: ThemeMode.dark,
        eyeProtect: true,
      );
      final json = state.toJson();
      expect(json.keys, unorderedEquals(['palette', 'mode', 'eyeProtect']));
      expect(
        ThemeState.fromJson(
            jsonDecode(jsonEncode(json)) as Map<String, dynamic>),
        state,
      );
    });

    test('a value written by the old build is dropped, and costs nothing else',
        () {
      final restored = ThemeState.fromJson(const {
        'palette': 'indigo',
        'mode': 'dark',
        'eyeProtect': true,
        'logo': 'elegantCurve',
      });
      expect(restored.palette, PaletteId.indigo);
      expect(restored.mode, ThemeMode.dark);
      expect(restored.eyeProtect, isTrue);
      expect(restored.toJson().containsKey('logo'), isFalse);
    });

    test('opening the appearance screen writes nothing', () async {
      final repo = _FakeSettingsRepository();
      final container = _container(repo);

      await container.read(themeControllerProvider.future);

      expect(repo.writes, 0, reason: 'reading a default is not a change');
      expect(repo.stored, isNull);
    });
  });
}
