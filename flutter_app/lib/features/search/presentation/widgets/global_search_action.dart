import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/strings.dart';
import '../../data/search_providers.dart';
import '../global_search_page.dart';

/// The app's single entry point into Global Search: the magnifier in the
/// dashboard's app bar, beside the notifications bell.
///
/// One entry point on purpose. Each module keeps the search field that filters
/// its own list — the roster, the store, the detachment list — because
/// narrowing a list you are already looking at is a different act from finding
/// a record you cannot see. A second global magnifier on every screen would
/// only make it ambiguous which of the two a tap means.
///
/// It renders nothing for a session with no searchable category. That is
/// decluttering, not authorization: the route is deliberately open, and every
/// destination behind it carries its own guard.
class GlobalSearchAction extends ConsumerWidget {
  const GlobalSearchAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(searchableCategoriesProvider).isEmpty) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const Key('global-search-action'),
      tooltip: S.globalSearchOpen,
      onPressed: () => context.push(GlobalSearchPage.routePath),
      icon: const Icon(Icons.search_rounded),
    );
  }
}
