import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/display/display_refresh.dart';
import 'package:mtm/core/display/frame_rate.dart';

/// The frame-rate setting has one rule it must never break: it may ask the
/// *display* for a rate, and it may report what it actually got, but it may
/// never pretend. So the two things worth testing are what gets offered on a
/// given panel and what gets requested for a given choice.

DisplayCapabilities _caps(
  List<double> rates, {
  bool canSelectMode = true,
  bool hint = false,
  double? active,
}) =>
    DisplayCapabilities(
      supportedRates: rates,
      activeRate: active ?? (rates.isEmpty ? null : rates.last),
      canSelectMode: canSelectMode,
      supportsFrameRateHint: hint,
    );

void main() {
  group('what the device is offered', () {
    test('a 60Hz-only panel offers auto and 60, and nothing it cannot do', () {
      expect(
        availableFrameRates(_caps([60])),
        [FrameRatePreference.auto, FrameRatePreference.fps60],
      );
    });

    test('a 120Hz panel offers the modes it really has', () {
      expect(
        availableFrameRates(_caps([60, 120])),
        [
          FrameRatePreference.auto,
          FrameRatePreference.fps60,
          FrameRatePreference.fps120,
        ],
      );
    });

    test('panels report 59.94 and 119.98; both still count', () {
      expect(
        availableFrameRates(_caps([59.94, 119.98])),
        [
          FrameRatePreference.auto,
          FrameRatePreference.fps60,
          FrameRatePreference.fps120,
        ],
      );
    });

    test('a platform that takes hints can reach a rate with no mode', () {
      // 30 has no mode on this panel, but Android's frame-rate hint can ask
      // the compositor for it. 240 stays off the list — above the ceiling.
      expect(
        availableFrameRates(_caps([60, 120], hint: true)),
        [
          FrameRatePreference.auto,
          FrameRatePreference.fps30,
          FrameRatePreference.fps60,
          FrameRatePreference.fps90,
          FrameRatePreference.fps120,
        ],
      );
    });

    test('a platform that can do nothing offers auto alone', () {
      final caps = _caps([60], canSelectMode: false);
      expect(availableFrameRates(caps), [FrameRatePreference.auto]);
      expect(caps.canChoose, isFalse);
    });
  });

  group('what actually gets requested', () {
    test('auto asks for nothing and hands the display back', () {
      expect(
          resolveFrameRate(FrameRatePreference.auto, _caps([60, 120])), isNull);
    });

    test('an exact mode is used as-is', () {
      expect(
        resolveFrameRate(FrameRatePreference.fps120, _caps([60, 120])),
        120,
      );
    });

    test('an unreachable rate resolves to the nearest real mode, not a lie',
        () {
      // 90 is not a mode here. The honest answer is the closest one, and
      // the picker is told to say so.
      expect(
        resolveFrameRate(FrameRatePreference.fps90, _caps([60, 120])),
        anyOf(60.0, 120.0),
      );
      expect(isFrameRateExact(FrameRatePreference.fps90, _caps([60, 120])),
          isFalse);
      expect(isFrameRateExact(FrameRatePreference.fps60, _caps([60, 120])),
          isTrue);
    });

    test('a tie prefers the lower rate — never spend battery unasked', () {
      expect(
        resolveFrameRate(FrameRatePreference.fps90, _caps([80, 100])),
        80,
      );
    });

    test('with no mode list the request passes through untouched', () {
      expect(
        resolveFrameRate(FrameRatePreference.fps60, _caps([])),
        60,
      );
    });
  });

  group('persistence', () {
    test('every preference round-trips, and junk falls back to auto', () {
      for (final p in FrameRatePreference.values) {
        expect(FrameRatePreference.fromJson(p.toJson()), p);
      }
      expect(FrameRatePreference.fromJson('fps240'), FrameRatePreference.auto);
      expect(FrameRatePreference.fromJson(''), FrameRatePreference.auto);
    });
  });

  group('DisplayRefresh talks to the platform', () {
    late List<MethodCall> calls;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls = [];
    });

    void handle(Future<Object?>? Function(MethodCall) fn) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(DisplayRefresh.channelName),
        (call) async {
          calls.add(call);
          return fn(call);
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel(DisplayRefresh.channelName), null);
      });
    }

    test('capabilities are read once and reused', () async {
      handle((call) async => {
            'supportedRates': [60.0, 120.0],
            'activeRate': 120.0,
            'canSelectMode': true,
            'supportsFrameRateHint': false,
          });
      final refresh = DisplayRefresh();
      final first = await refresh.capabilities();
      final second = await refresh.capabilities();
      expect(first.supportedRates, [60.0, 120.0]);
      expect(second, same(first));
      expect(calls.where((c) => c.method == 'capabilities'), hasLength(1));
    });

    test('a choice reaches the platform as a resolved rate', () async {
      handle((call) async {
        if (call.method == 'capabilities') {
          return {
            'supportedRates': [60.0, 120.0],
            'activeRate': 120.0,
            'canSelectMode': true,
            'supportsFrameRateHint': false,
          };
        }
        return call.arguments['hz'];
      });
      final refresh = DisplayRefresh();
      expect(await refresh.apply(FrameRatePreference.fps60), 60.0);
      expect(calls.last.method, 'setFrameRate');
      expect(calls.last.arguments['hz'], 60.0);

      // Auto is sent as a null rate, which is the platform's cue to stop
      // holding a mode.
      expect(await refresh.apply(FrameRatePreference.auto), isNull);
      expect(calls.last.arguments['hz'], isNull);
    });

    test('a platform with no display channel degrades to auto-only', () async {
      // No mock handler registered at all: this is a desktop/web build.
      final refresh = DisplayRefresh();
      final caps = await refresh.capabilities();
      expect(caps.canChoose, isFalse);
      expect(availableFrameRates(caps), [FrameRatePreference.auto]);
      // And applying anything is a no-op rather than an exception.
      expect(await refresh.apply(FrameRatePreference.fps120), isNull);
    });
  });
}
