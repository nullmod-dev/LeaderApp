import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../auth/data/auth_providers.dart' show localStoreProvider;
import '../domain/settings_models.dart';
import '../domain/settings_repository.dart';
import 'mock_settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return MockSettingsRepository(localStore: ref.watch(localStoreProvider));
});

final notificationPrefsProvider =
    FutureProvider<Result<NotificationPrefs>>((ref) async {
  return ref.read(settingsRepositoryProvider).notificationPrefs();
});

final orgInfoProvider = FutureProvider<Result<OrgInfo>>((ref) async {
  return ref.read(settingsRepositoryProvider).orgInfo();
});
