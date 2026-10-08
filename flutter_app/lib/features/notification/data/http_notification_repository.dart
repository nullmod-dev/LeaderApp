import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/notification_models.dart';
import '../domain/notification_repository.dart';

/// `GET /notifications?detachmentId=` (`docs/api/home-notifications-search.md`
/// §3) — the record-derived rows of the Notifications Center.
///
/// Held to this seam's contract: the app merges announcement rows from its
/// own announcement source and applies its own read state, so the server's
/// `announcement` rows are left out and every row arrives unread.
class HttpNotificationRepository implements NotificationRepository {
  HttpNotificationRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<List<AppNotification>>> feed(String detachmentId) => _api.send(
        'GET',
        '/notifications',
        query: {'detachmentId': detachmentId},
        parse: (json) => [
          for (final row in (json as Map<String, dynamic>)['notifications']
              as List)
            if ((row as Map<String, dynamic>)['kind'] != 'announcement')
              AppNotification.fromJson({...row, 'isRead': false}),
        ],
      );
}
