import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/announcement_models.dart';
import '../domain/announcement_repository.dart';

/// `/announcements/**` (`docs/api/announcements.md`). The list arrives
/// already narrowed to what addresses a detachment the session can view;
/// publish authority is checked by the server in every addressed detachment.
class HttpAnnouncementRepository implements AnnouncementRepository {
  HttpAnnouncementRepository(this._api);

  final ApiClient _api;

  static Announcement _one(Object? json) =>
      Announcement.fromJson(json as Map<String, dynamic>);

  @override
  Future<Result<List<Announcement>>> list() => _api.send(
        'GET',
        '/announcements',
        parse: (json) => [
          for (final row
              in (json as Map<String, dynamic>)['announcements'] as List)
            _one(row),
        ],
      );

  @override
  Future<Result<Announcement>> byId(String id) => _api.send(
        'GET',
        '/announcements/${Uri.encodeComponent(id)}',
        parse: _one,
      );

  /// `publishedAt` is advisory (the server stamps its own time); the author
  /// is the signed-in account, so [authorName] is not sent.
  @override
  Future<Result<Announcement>> publish({
    required String text,
    required List<String> detachmentIds,
    required Set<AnnouncementPlacement> placements,
    required DateTime publishedAt,
    required DateTime expiresAt,
    String? authorName,
  }) =>
      _api.send(
        'POST',
        '/announcements',
        body: {
          'text': text,
          'detachmentIds': detachmentIds,
          'placements': [for (final p in placements) p.name],
          'publishedAt': publishedAt.toUtc().toIso8601String(),
          'expiresAt': expiresAt.toUtc().toIso8601String(),
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _one,
      );

  @override
  Future<Result<Announcement>> withdraw(String id) => _api.send(
        'POST',
        '/announcements/${Uri.encodeComponent(id)}/withdraw',
        parse: _one,
      );
}
