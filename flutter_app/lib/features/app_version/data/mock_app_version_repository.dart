import '../../../core/result/result.dart';
import '../domain/app_version_models.dart';
import '../domain/app_version_repository.dart';

/// What the mock backend should pretend to answer.
///
/// The default is [supported], so a normal build behaves exactly as it did
/// before this feature existed. The other three are development triggers —
/// they are selected with a `--dart-define` at build time or by a test that
/// constructs the repository directly, never by anything the user can reach.
/// There is no hidden gesture and no debug button inside the app.
enum AppVersionScenario {
  /// The backend serves this build. No blocking state.
  supported,

  /// The backend refuses this build — the `426` case.
  upgradeRequired,

  /// The check could not reach anything (`Offline`).
  unreachable,

  /// The check reached something and it went wrong (`Failure`).
  failing;

  /// Reads the scenario chosen at build time:
  ///
  /// ```sh
  /// flutter run --dart-define=MTM_VERSION_SCENARIO=upgradeRequired
  /// ```
  ///
  /// An unset or unrecognised value is [supported] — a typo must not brick
  /// a build.
  static AppVersionScenario fromEnvironment() {
    const name = String.fromEnvironment(envKey);
    return AppVersionScenario.values.firstWhere(
      (s) => s.name == name,
      orElse: () => AppVersionScenario.supported,
    );
  }

  static const String envKey = 'MTM_VERSION_SCENARIO';
}

/// In-memory stand-in for the version-support endpoint.
///
/// MOCK — replace with a network-backed `AppVersionRepository` when the
/// endpoint exists; see `FRONTEND-BACKEND-INTEGRATION.md` §1. Nothing here
/// compares version numbers: deciding whether a build is still supported is
/// the backend's job, and faking that comparison on the client is exactly
/// the coupling this seam exists to avoid.
class MockAppVersionRepository implements AppVersionRepository {
  MockAppVersionRepository({AppVersionScenario? scenario, this.latency})
      : scenario = scenario ?? AppVersionScenario.fromEnvironment();

  final AppVersionScenario scenario;

  /// Test override. Left null in the app: see [_latency].
  final Duration? latency;

  /// The default scenario answers on the next microtask rather than after a
  /// timer, so launch is unchanged and a widget test is never left holding
  /// a pending timer. The development scenarios take long enough for the
  /// `checking` state to be seen when retrying.
  Duration get _latency =>
      latency ??
      (scenario == AppVersionScenario.supported
          ? Duration.zero
          : const Duration(milliseconds: 600));

  /// PLACEHOLDER minimum. The real floor comes from the backend.
  static const String placeholderMinimumVersion = '1.4.0';

  @override
  Future<Result<AppVersionSupport>> checkSupport() async {
    final wait = _latency;
    if (wait > Duration.zero) await Future<void>.delayed(wait);

    return switch (scenario) {
      AppVersionScenario.supported =>
        const Success(AppVersionSupport(supported: true)),
      // No `updateUrl`: the destination is client-owned (`UpdateChannel`),
      // so a real `426` is not expected to carry one either.
      AppVersionScenario.upgradeRequired => const Success(
          AppVersionSupport(
            supported: false,
            minimumVersion: placeholderMinimumVersion,
          ),
        ),
      AppVersionScenario.unreachable => const Offline<AppVersionSupport>(),
      AppVersionScenario.failing => const Failure<AppVersionSupport>(
          'تعذّر التحقق من الإصدار على الخادم.',
        ),
    };
  }
}
