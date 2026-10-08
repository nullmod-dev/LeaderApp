import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/detachment_models.dart';
import '../domain/detachment_repository.dart';

/// `/detachments/**` (`docs/api/detachments.md` §§4–6). Lists arrive already
/// narrowed to the detachments the session may see.
class HttpDetachmentRepository implements DetachmentRepository {
  HttpDetachmentRepository(this._api);

  final ApiClient _api;

  static Detachment _one(Object? json) =>
      Detachment.fromJson(json as Map<String, dynamic>);

  static String _path(String id) => '/detachments/${Uri.encodeComponent(id)}';

  @override
  Future<Result<List<Detachment>>> list({
    String? detachmentGroupId,
    DetachmentStatus? filter,
    String? query,
  }) =>
      _api.send(
        'GET',
        '/detachments',
        query: {
          if (detachmentGroupId != null) 'detachmentGroupId': detachmentGroupId,
          if (filter != null) 'filter': filter.name,
          if (query != null && query.trim().isNotEmpty) 'query': query,
        },
        parse: (json) => [for (final row in json as List) _one(row)],
      );

  @override
  Future<Result<Detachment>> byId(String id) =>
      _api.send('GET', _path(id), parse: _one);

  @override
  Future<Result<Detachment>> create({
    required String detachmentGroupId,
    required String name,
    required String region,
    required String mainCenter,
    String? notes,
  }) =>
      _api.send(
        'POST',
        '/detachments',
        body: {
          'detachmentGroupId': detachmentGroupId,
          'name': name,
          'region': region,
          'mainCenter': mainCenter,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes,
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _one,
      );

  @override
  Future<Result<Detachment>> update(Detachment d) =>
      _api.send('PUT', _path(d.id), body: d.toJson(), parse: _one);

  @override
  Future<Result<void>> delete(String id) =>
      _api.send('DELETE', _path(id), parse: (_) {});

  /// The server cascades a group delete itself (`DELETE /detachment-groups/:id`);
  /// this per-detachment form is kept for the interface and deletes what the
  /// group currently holds, archived included.
  @override
  Future<Result<int>> deleteAllInGroup(String detachmentGroupId) async {
    final listed = await _api.send(
      'GET',
      '/detachments',
      query: {'detachmentGroupId': detachmentGroupId, 'filter': 'all'},
      parse: (json) => [for (final row in json as List) _one(row).id],
    );
    switch (listed) {
      case Success(:final data):
        var removed = 0;
        for (final id in data) {
          final r = await delete(id);
          if (r case Failure(:final message, :final code)) {
            return Failure(message, code: code);
          }
          if (r is Offline) return const Offline();
          removed++;
        }
        return Success(removed);
      case Failure(:final message, :final code):
        return Failure(message, code: code);
      case Offline():
        return const Offline();
    }
  }

  @override
  Future<Result<DetachmentStats>> stats(String id) => _api.send(
        'GET',
        '${_path(id)}/stats',
        query: const {'days': '7'},
        parse: (json) => DetachmentStats.fromJson(json as Map<String, dynamic>),
      );
}
