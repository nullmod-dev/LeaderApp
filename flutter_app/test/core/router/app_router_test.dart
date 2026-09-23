import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/router/app_router.dart';

/// Every location the app can actually reach, by feature.
///
/// The interesting ones are the two `:id/edit` forms: they render on the root
/// navigator so they cover the bottom nav, which means they must stay siblings
/// of their detail `ShellRoute` rather than children of it. Nesting them
/// inside the shell trips a go_router assert while GoRouter is being built —
/// the app then dies on a red screen before its first frame instead of failing
/// on the edit screen, which is why this is a router test and not a UI one.
const _locations = <String>[
  // The forced-upgrade gate. Reachable as a route; whether it is *shown* is
  // the router's redirect, covered in
  // `test/features/app_version/forced_upgrade_test.dart`.
  '/upgrade-required',
  '/conflicts/c1',
  // The Needs Review inbox — a root route beside the conflict screen it
  // opens, so it covers the bottom nav too.
  '/needs-review',
  // The Notifications Center, a root route for the same reason.
  '/notifications',
  '/feature-disabled',
  '/login',
  '/mfa-setup',
  '/mfa-challenge',
  '/forgot',
  '/otp',
  '/new-password',
  '/session-expired',
  '/new-device',
  '/home',
  // Detachment groups are the container above detachments, so creating a
  // detachment happens inside one and there is no unparented `/detachment/new`.
  '/detachment-groups',
  '/detachment-groups/new',
  '/detachment-groups/t1/edit',
  '/detachment-groups/t1',
  '/detachment-groups/t1/detachment/new',
  '/detachment',
  '/detachment/d1/edit',
  '/detachment/d1/member/new',
  '/detachment/d1/member/m1/edit',
  '/detachment/d1/member/m1/status',
  '/detachment/d1/team',
  '/detachment/d1/shifts',
  '/detachment/d1/storage',
  '/detachment/d1/stats',
  '/detachment/d1/storage/new',
  '/detachment/d1/storage/i1/edit',
  '/detachment/d1/report',
  '/detachment/d1/report/preview',
  '/workshop',
  '/workshop/new',
  '/workshop/w1/edit',
  '/workshop/w1/team',
  '/workshop/w1/members',
  '/workshop/w1/stats',
  '/more',
  '/more/themes',
  '/more/performance',
  '/more/sync',
  '/more/profile',
  '/more/security',
  '/more/notifications',
  '/more/org',
  '/more/organization',
  '/more/plan',
];

/// The pre-rename `/tenant` locations, kept as redirect-only routes so a link
/// handed out before Point 1 still resolves. They must *match* a route here —
/// where they land is `admin_experience_routes_test.dart`, which runs the
/// redirects with a real session behind them.
const _legacyLocations = <String>[
  '/tenant',
  '/tenant/new',
  '/tenant/t1',
  '/tenant/t1/edit',
  '/tenant/t1/detachment/new',
];

GoRouter _buildRouter() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container.read(appRouterProvider);
}

void main() {
  test('the router can be constructed', () {
    expect(_buildRouter(), isA<GoRouter>());
  });

  test('every location resolves to a route', () {
    final router = _buildRouter();
    for (final location in _locations) {
      final match = router.configuration.findMatch(Uri.parse(location));
      expect(match.isError, isFalse, reason: '$location did not match');
      expect(match.uri.toString(), location);
    }
  });

  test('every legacy tenant location still resolves to a route', () {
    final router = _buildRouter();
    for (final location in _legacyLocations) {
      final match = router.configuration.findMatch(Uri.parse(location));
      expect(match.isError, isFalse, reason: '$location did not match');
    }
  });

  test('an unknown location does not match', () {
    final router = _buildRouter();
    expect(
      router.configuration.findMatch(Uri.parse('/detachment/d1/nope')).isError,
      isTrue,
    );
  });
}
