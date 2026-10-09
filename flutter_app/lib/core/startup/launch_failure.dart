/// Why a session read with no stored copy to fall back on failed.
///
/// Its own file because both sides need it: `launchFailureProvider` (auth
/// data) derives it from the read's result, and the pure startup classifier
/// reads it — and the classifier already imports the auth layer.
///
/// [none] for everything that is not one of the two named failures, and for
/// every caller that builds `StartupInputs` without it.
library;

enum LaunchFailure {
  none,

  /// The server could not be reached: no network, or the request timed out.
  network,

  /// The server answered with a `5xx`.
  server,
}
