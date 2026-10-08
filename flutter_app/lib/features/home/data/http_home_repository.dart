import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/home_models.dart';
import '../domain/home_repository.dart';

/// `GET /home/summary?detachmentId=` (`docs/api/home-notifications-search.md`
/// §1) — the dashboard snapshot, joined on the server in one round trip.
class HttpHomeRepository implements HomeRepository {
  HttpHomeRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<HomeSummary>> summary(String detachmentId) => _api.send(
        'GET',
        '/home/summary',
        query: {'detachmentId': detachmentId},
        parse: (json) => HomeSummary.fromJson(json as Map<String, dynamic>),
      );
}
