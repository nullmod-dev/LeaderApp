import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/app_version/data/app_version_providers.dart';
import '../../features/auth/data/auth_providers.dart';
import '../../features/auth/data/device_id_store.dart';
import '../../features/auth/data/http_auth_repository.dart';
import 'api_client.dart';
import 'token_vault.dart';

/// The one [ApiClient] of a backend build.
///
/// Read only when `LEADER_API_BASE_URL` is set: nothing in a mock build (the
/// test suite included) ever constructs it, because only the overrides in
/// `backend_overrides.dart` watch it.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    vault: TokenVault(ref.watch(authStateStoreProvider)),
  )..deviceId = ref.watch(deviceIdStoreProvider).read;

  // Any 426 sends the forced-upgrade gate back to the server once; repeated
  // 426s while that check runs do not queue more checks.
  var checking = false;
  client.onUpgradeRequired = () {
    if (checking) return;
    checking = true;
    ref
        .read(appVersionProvider.notifier)
        .check()
        .whenComplete(() => checking = false);
  };

  // A full session that could not be refreshed: the credentials are already
  // cleared; re-read the session so the router lands on `/session-expired`.
  client.onSessionEnded = () {
    final repository = ref.read(authRepositoryProvider);
    if (repository is HttpAuthRepository) repository.markSessionExpired();
    ref.invalidate(currentUserResultProvider);
  };
  return client;
});
