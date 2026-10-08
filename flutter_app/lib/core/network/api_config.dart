/// Where the Leader API lives, and whether this build talks to it at all.
///
/// The origin comes from one compile-time define — the same mechanism the
/// app already uses for `MTM_GOOGLE_SERVER_CLIENT_ID`:
///
/// ```bash
/// flutter build apk --debug --dart-define=LEADER_API_BASE_URL=http://10.0.2.2:4000
/// ```
///
/// **Empty (the default) keeps every repository on its mock**, exactly as the
/// app ran before the backend existed. That is what the test suite runs on,
/// and it is why nothing below is a runtime setting: a build either speaks
/// HTTP to one origin or it does not.
library;

/// The raw define. Read through [apiOrigin]; never parsed anywhere else.
const String leaderApiBaseUrl = String.fromEnvironment('LEADER_API_BASE_URL');

/// Whether this build was given a backend origin.
bool get isBackendConfigured => leaderApiBaseUrl.trim().isNotEmpty;

/// The origin without a trailing slash, e.g. `http://10.0.2.2:4000`.
String get apiOrigin => leaderApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

/// Every JSON endpoint sits under this prefix (`docs/api/*.md`).
const String apiPathPrefix = '/api/v1';
