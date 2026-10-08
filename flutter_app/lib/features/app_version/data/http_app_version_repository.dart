import '../../../core/app_info.dart';
import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/app_version_models.dart';
import '../domain/app_version_repository.dart';

/// `GET /app-version/check?version=` — the forced-upgrade check.
///
/// The endpoint answers `200 { supported, minimumVersion }`; the version gate
/// in front of every route answers `426 upgrade_required` with the minimum in
/// the error body. Both mean the same thing here, as the seam documents.
class HttpAppVersionRepository implements AppVersionRepository {
  HttpAppVersionRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<AppVersionSupport>> checkSupport() async {
    final outcome = await _api.exchange(
      'GET',
      '/app-version/check',
      query: {'version': AppInfo.version},
      authenticated: false,
      // The gate's own check must not re-trigger the gate.
      notifyUpgrade: false,
    );
    if (outcome is ApiReply && outcome.status == 426) {
      final minimum = outcome.error['minimumVersion'];
      return Success(AppVersionSupport(
        supported: false,
        minimumVersion: minimum is String ? minimum : null,
      ));
    }
    return ApiClient.resultOf(
      outcome,
      (json) => AppVersionSupport.fromJson(json as Map<String, dynamic>),
    );
  }
}
