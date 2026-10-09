import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/notification_history_store.dart';
import '../domain/notification_read_store.dart';

/// Read state and cleared history, kept on the server per account
/// (`docs/api/home-notifications-search.md`):
///
///   GET /notifications/state   → { readIds, clearedIds }
///   PUT /notifications/read    { ids } → { readIds }    (the caller's full set)
///   PUT /notifications/cleared { ids } → { clearedIds }
///
/// So a row read on one phone is read on the administrator's other phone, and
/// a reinstall does not bring every announcement back as unread.
///
/// One object behind both stores: both sets arrive in one `GET /state`, and
/// the two controllers that read them start together, so concurrent reads
/// share one request. Nothing is cached past it — the next account on this
/// phone must never be answered with the previous one's set. A failed read
/// or write throws; the controllers turn that into their own outcome, and an
/// unread row is the safe way to be wrong.
class HttpNotificationStateStore
    implements NotificationReadStore, NotificationHistoryStore {
  HttpNotificationStateStore(this._api);

  final ApiClient _api;

  Future<({Set<String> read, Set<String> cleared})>? _inFlight;

  Future<({Set<String> read, Set<String> cleared})> _state() =>
      _inFlight ??= _fetch().whenComplete(() => _inFlight = null);

  Future<({Set<String> read, Set<String> cleared})> _fetch() async {
    final result = await _api.send(
      'GET',
      '/notifications/state',
      parse: (json) {
        final j = json as Map<String, dynamic>;
        return (read: _ids(j['readIds']), cleared: _ids(j['clearedIds']));
      },
    );
    return switch (result) {
      Success(:final data) => data,
      _ => throw StateError('notification state unavailable'),
    };
  }

  static Set<String> _ids(Object? raw) =>
      raw is List ? {for (final id in raw) if (id is String) id} : <String>{};

  Future<void> _add(String path, Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final result = await _api.send(
      'PUT',
      path,
      body: {'ids': list},
      parse: (_) {},
    );
    if (result is! Success) throw StateError('$path refused');
  }

  @override
  Future<Set<String>> readIds() async => (await _state()).read;

  @override
  Future<void> markRead(Iterable<String> ids) =>
      _add('/notifications/read', ids);

  @override
  Future<Set<String>> clearedIds() async => (await _state()).cleared;

  @override
  Future<void> clear(Iterable<String> ids) =>
      _add('/notifications/cleared', ids);
}
