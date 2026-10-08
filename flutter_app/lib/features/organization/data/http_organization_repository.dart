import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/organization_models.dart';
import '../domain/organization_repository.dart';

/// `GET /tenant/organization` (`docs/api/tenant-administration.md` §3). The
/// tenant comes from the bearer; usage figures arrive only with `org.edit`.
///
/// Keeps the last successful read so an offline revisit shows it (stale)
/// rather than an empty screen, like the mock adapter it replaces.
class HttpOrganizationRepository implements OrganizationRepository {
  HttpOrganizationRepository(this._api);

  final ApiClient _api;
  OrganizationSnapshot? _last;

  @override
  Future<Result<OrganizationSnapshot>> readCurrent() async {
    final result = await _api.send(
      'GET',
      '/tenant/organization',
      parse: (json) =>
          OrganizationSnapshot.fromJson(json as Map<String, dynamic>),
    );
    return switch (result) {
      Success(:final data) => Success(_last = data),
      Offline() => Offline(cached: _last),
      Failure() => result,
    };
  }
}
