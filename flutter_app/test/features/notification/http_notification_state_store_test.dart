import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/notification/data/http_notification_state_store.dart';

/// Read state and cleared history on the server, per account.
http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  late List<http.Request> sent;
  late http.Response Function(http.Request) server;

  HttpNotificationStateStore store() => HttpNotificationStateStore(ApiClient(
        vault: TokenVault(SecureAuthStateStore(InMemorySecureStore())),
        origin: 'http://leader.test',
        client: MockClient((request) async {
          sent.add(request);
          return server(request);
        }),
      ));

  setUp(() => sent = []);

  test('both sets arrive in one read when asked together', () async {
    server = (_) => _json(200, {
          'readIds': ['shiftUnderstaffed:s_1'],
          'clearedIds': ['announcement:a_1'],
        });
    final s = store();
    final both = await Future.wait([s.readIds(), s.clearedIds()]);
    expect(both[0], {'shiftUnderstaffed:s_1'});
    expect(both[1], {'announcement:a_1'});
    expect(sent, hasLength(1));
    expect(sent.single.url.path, endsWith('/notifications/state'));
  });

  test('nothing is cached past the read', () async {
    server = (_) => _json(200, {'readIds': <String>[], 'clearedIds': <String>[]});
    final s = store();
    await s.readIds();
    await s.readIds();
    expect(sent, hasLength(2),
        reason: 'the next account must never see the last one\'s set');
  });

  test('marking read and clearing are PUTs of the ids', () async {
    server = (_) => _json(200, {'readIds': <String>[]});
    await store().markRead({'a', 'b'});
    expect(sent.single.method, 'PUT');
    expect(sent.single.url.path, endsWith('/notifications/read'));
    expect((jsonDecode(sent.single.body) as Map)['ids'], unorderedEquals(['a', 'b']));

    sent.clear();
    server = (_) => _json(200, {'clearedIds': <String>[]});
    await store().clear({'announcement:a_1'});
    expect(sent.single.url.path, endsWith('/notifications/cleared'));
  });

  test('a refused write throws, so the controller reports it', () async {
    server = (_) => _json(503, {
          'error': {'code': 'server'}
        });
    await expectLater(store().markRead({'a'}), throwsStateError);
    await expectLater(store().readIds(), throwsStateError);
  });

  test('an empty change sends nothing', () async {
    server = (_) => _json(200, {});
    await store().markRead(const {});
    expect(sent, isEmpty);
  });
}
