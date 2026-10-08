import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/detachment_group_models.dart';
import '../domain/detachment_group_repository.dart';

/// `/detachment-groups/**` (`docs/api/detachments.md` §3). The roll-ups arrive
/// computed by the server; a delete cascades there, in one transaction.
class HttpDetachmentGroupRepository implements DetachmentGroupRepository {
  HttpDetachmentGroupRepository(this._api);

  final ApiClient _api;

  static DetachmentGroup _one(Object? json) =>
      DetachmentGroup.fromJson(json as Map<String, dynamic>);

  @override
  Future<Result<List<DetachmentGroup>>> list({String? query}) => _api.send(
        'GET',
        '/detachment-groups',
        query: {if (query != null && query.trim().isNotEmpty) 'query': query},
        parse: (json) => [for (final row in json as List) _one(row)],
      );

  @override
  Future<Result<DetachmentGroup>> byId(String id) => _api.send(
        'GET',
        '/detachment-groups/${Uri.encodeComponent(id)}',
        parse: _one,
      );

  @override
  Future<Result<DetachmentGroup>> create({
    required String name,
    String? notes,
  }) =>
      _api.send(
        'POST',
        '/detachment-groups',
        body: {
          'name': name,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes,
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _one,
      );

  @override
  Future<Result<DetachmentGroup>> update(DetachmentGroup group) => _api.send(
        'PUT',
        '/detachment-groups/${Uri.encodeComponent(group.id)}',
        body: group.toJson(),
        parse: _one,
      );

  @override
  Future<Result<void>> delete(String id) => _api.send(
        'DELETE',
        '/detachment-groups/${Uri.encodeComponent(id)}',
        parse: (_) {},
      );
}
