/// Production Google identity acquisition for Point 17C.
///
/// The SDK returns one short-lived OpenID Connect ID token. Flutter neither
/// decodes its claims nor derives an MTM role, tenant or capability from it;
/// it is exchanged once through `OnboardingRepository`, whose backend answer
/// remains canonical. The token is never persisted or logged.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/env/build_mode.dart';
import '../domain/onboarding_models.dart' show GoogleIdentityAssertion;
import 'auth_providers.dart' show demoAccountsEnabledProvider;

/// Android needs the OAuth web/server client id so the SDK can mint an ID
/// token for the MTM backend audience. No identifier is committed here.
const String googleServerClientId =
    String.fromEnvironment('MTM_GOOGLE_SERVER_CLIENT_ID');

sealed class GoogleSignInAttempt {
  const GoogleSignInAttempt();
}

final class GoogleSignInObtained extends GoogleSignInAttempt {
  const GoogleSignInObtained(this.assertion);
  final GoogleIdentityAssertion assertion;
}

/// User dismissal is intentionally silent in the UI.
final class GoogleSignInCancelled extends GoogleSignInAttempt {
  const GoogleSignInCancelled();
}

/// Missing/misconfigured provider or a platform that cannot show the picker.
final class GoogleSignInUnavailable extends GoogleSignInAttempt {
  const GoogleSignInUnavailable();
}

/// Provider transport failure. The UI uses its offline/retry treatment and
/// never sees the SDK's platform code or description.
final class GoogleSignInNetworkFailure extends GoogleSignInAttempt {
  const GoogleSignInNetworkFailure();
}

/// Interrupted or unknown provider failure; generic and retryable.
final class GoogleSignInFailed extends GoogleSignInAttempt {
  const GoogleSignInFailed();
}

abstract class GoogleIdentityGateway {
  Future<GoogleSignInAttempt> signIn();
}

enum GoogleTokenClientFailure { cancelled, unavailable, network, failed }

class GoogleTokenClientException implements Exception {
  const GoogleTokenClientException(this.failure);

  final GoogleTokenClientFailure failure;

  @override
  String toString() => 'GoogleTokenClientException(${failure.name})';
}

/// Small injectable boundary around the Flutter plugin. Tests exercise the
/// gateway without asking a host platform to render account UI.
abstract class GoogleIdentityTokenClient {
  bool get configured;

  Future<String> obtainIdToken();
}

class GoogleSdkIdentityTokenClient implements GoogleIdentityTokenClient {
  GoogleSdkIdentityTokenClient({required this.serverClientId});

  final String serverClientId;

  static Future<void>? _initialization;
  static String? _initializedFor;

  @override
  bool get configured => serverClientId.trim().isNotEmpty;

  @override
  Future<String> obtainIdToken() async {
    if (!configured) {
      throw const GoogleTokenClientException(
          GoogleTokenClientFailure.unavailable);
    }
    final signIn = GoogleSignIn.instance;
    try {
      final initializedFor = _initializedFor;
      if (initializedFor != null && initializedFor != serverClientId) {
        throw const GoogleTokenClientException(
            GoogleTokenClientFailure.unavailable);
      }
      _initializedFor = serverClientId;
      final initialization =
          _initialization ??= signIn.initialize(serverClientId: serverClientId);
      try {
        await initialization;
      } catch (_) {
        // A failed initialization must not be memoized: the next tap retries
        // it instead of reporting "unavailable" until the process restarts.
        if (identical(_initialization, initialization)) {
          _initialization = null;
          _initializedFor = null;
        }
        rethrow;
      }
      if (!signIn.supportsAuthenticate()) {
        throw const GoogleTokenClientException(
            GoogleTokenClientFailure.unavailable);
      }
      // Drop this app's own cached Google session before asking for a new
      // one, so the press reliably reaches the account chooser.
      //
      // `authenticate()` is already the button flow — on Android it issues a
      // `GetSignInWithGoogleOption` credential request, which is the branded
      // system chooser listing the device's Google accounts, with no
      // authorized-account filter and no auto-select. What this adds is the
      // plugin's own documented precondition: a client "should not call
      // [authenticate] to obtain a new account until after a call to
      // [signOut]". Someone who pressed the Google button *on purpose* is
      // asking to choose, possibly a different account than last time.
      //
      // It clears nothing outside this app: not the device's Google
      // accounts, not Android's own sign-in, and not any authorization grant
      // (that is `disconnect()`, which is deliberately never called here). A
      // failure to sign out is swallowed — it must never be the reason a
      // sign-in cannot start.
      try {
        await signIn.signOut();
      } catch (_) {
        // Nothing to clear, or the platform does not support it.
      }
      final account = await signIn.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.trim().isEmpty) {
        throw const GoogleTokenClientException(GoogleTokenClientFailure.failed);
      }
      return token;
    } on GoogleSignInException catch (error) {
      throw GoogleTokenClientException(switch (error.code) {
        GoogleSignInExceptionCode.canceled =>
          GoogleTokenClientFailure.cancelled,
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError ||
        GoogleSignInExceptionCode.uiUnavailable =>
          GoogleTokenClientFailure.unavailable,
        GoogleSignInExceptionCode.interrupted ||
        GoogleSignInExceptionCode.userMismatch ||
        GoogleSignInExceptionCode.unknownError =>
          GoogleTokenClientFailure.failed,
      });
    } on PlatformException catch (error) {
      // Plugin implementations do not expose one cross-platform network enum.
      // Recognise only the established transport spellings; every other code
      // is deliberately collapsed to a generic provider failure.
      final code = error.code.toLowerCase();
      final network = code == 'network_error' ||
          code == 'networkerror' ||
          code == '7'; // Android CommonStatusCodes.NETWORK_ERROR.
      throw GoogleTokenClientException(network
          ? GoogleTokenClientFailure.network
          : GoogleTokenClientFailure.failed);
    } on MissingPluginException {
      throw const GoogleTokenClientException(
          GoogleTokenClientFailure.unavailable);
    } on UnsupportedError {
      throw const GoogleTokenClientException(
          GoogleTokenClientFailure.unavailable);
    }
  }
}

class GoogleSdkIdentityGateway implements GoogleIdentityGateway {
  const GoogleSdkIdentityGateway(this._client);

  final GoogleIdentityTokenClient _client;

  @override
  Future<GoogleSignInAttempt> signIn() async {
    if (!_client.configured) return const GoogleSignInUnavailable();
    try {
      final token = await _client.obtainIdToken();
      return GoogleSignInObtained(GoogleIdentityAssertion(token));
    } on GoogleTokenClientException catch (error) {
      return switch (error.failure) {
        GoogleTokenClientFailure.cancelled => const GoogleSignInCancelled(),
        GoogleTokenClientFailure.unavailable => const GoogleSignInUnavailable(),
        GoogleTokenClientFailure.network => const GoogleSignInNetworkFailure(),
        GoogleTokenClientFailure.failed => const GoogleSignInFailed(),
      };
    } catch (_) {
      // No exception text or provider code crosses this boundary.
      return const GoogleSignInFailed();
    }
  }
}

final googleIdentityGatewayProvider = Provider<GoogleIdentityGateway>((ref) {
  return GoogleSdkIdentityGateway(
    GoogleSdkIdentityTokenClient(serverClientId: googleServerClientId),
  );
});

/// Whether a build running on [platform] may stand in for Google's own
/// account chooser with the in-app development dialog.
///
/// **Never on a phone.** Android and iOS both have a real, system-owned
/// Google account chooser, and on those platforms an app that put up its own
/// «type your Google address» field would be doing the one thing a sign-in
/// flow must never do: imitating the identity provider's UI. That dialog
/// exists so the repository's Google paths — verified, unverified,
/// method-link-required — are reachable on a desktop debug run and in this
/// repository's tests, where no native chooser exists to open. It is a
/// development *fixture*, not a fallback, so it is refused wherever the real
/// thing is available and the honest outcome of a misconfigured build is
/// [GoogleSignInUnavailable].
///
/// [demoAccountsAllowed] still gates it on top of this, so a release artefact
/// does not contain the dialog at all.
bool developmentGoogleChooserSupported({
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    demoAccountsAllowed &&
    !isWeb &&
    platform != TargetPlatform.android &&
    platform != TargetPlatform.iOS;

/// Whether the Google button opens the development chooser instead of the
/// SDK. A provider so a test can ask for either path explicitly.
final googleDevelopmentChooserProvider = Provider<bool>((ref) {
  return ref.watch(demoAccountsEnabledProvider) &&
      developmentGoogleChooserSupported(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      );
});
