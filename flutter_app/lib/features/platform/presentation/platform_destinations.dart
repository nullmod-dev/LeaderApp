import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../domain/platform_area.dart';

/// The presentation half of the platform's destination registry: one entry per
/// [PlatformArea], carrying what a *navigation control* needs and nothing
/// else.
///
/// **One list, four consumers.** The compact bar, the expanded rail, the shell
/// branch order and each page's own title all read [platformDestinations]. The
/// failure this prevents is the ordinary one — a destination renamed in the bar
/// and not in the rail, a fifth area added to the router and not to the bar —
/// and it is prevented by there being nowhere else to state any of it.
///
/// The route, the ordering and the readiness live one layer down in
/// `domain/platform_area.dart`, which is pure Dart. What is here is exactly the
/// part a future web dashboard would *not* reuse: an icon set and a label
/// chosen for a phone.
@immutable
class PlatformDestination {
  const PlatformDestination({
    required this.area,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final PlatformArea area;

  /// The navigation label. Short by rule — the compact bar shows all four at
  /// 320 dp and none of them may be truncated or shrunk to fit.
  final String label;

  /// The resting glyph: outlined, so the selected one below reads as a change
  /// of *state* and not merely of colour (`§32` — no colour-only state).
  final IconData icon;

  /// The selected glyph: the filled pair of [icon].
  final IconData selectedIcon;

  String get route => area.route;

  bool get isReserved => area.readiness == PlatformAreaReadiness.reserved;
}

/// Every platform destination, in branch order.
///
/// Ordered the way an operator reads the control plane: where am I (المنصة),
/// who is on it (الفرق), what is being done to it (العمليات), and my own
/// account (المزيد). `more` is last for the same reason it is last in the
/// tenant app — it is the drawer, not a peer of the work.
const List<PlatformDestination> platformDestinations = [
  PlatformDestination(
    area: PlatformArea.overview,
    label: S.platformNavOverview,
    icon: Icons.dns_outlined,
    selectedIcon: Icons.dns_rounded,
  ),
  PlatformDestination(
    area: PlatformArea.tenants,
    label: S.platformNavTenants,
    icon: Icons.groups_2_outlined,
    selectedIcon: Icons.groups_2_rounded,
  ),
  PlatformDestination(
    area: PlatformArea.operations,
    label: S.platformNavOperations,
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune_rounded,
  ),
  PlatformDestination(
    area: PlatformArea.more,
    label: S.platformNavMore,
    icon: Icons.more_horiz_rounded,
    selectedIcon: Icons.more_horiz_rounded,
  ),
];

/// The destination for [area]. Total by construction — the list above has one
/// entry per enum value, and `platform_navigation_test.dart` holds it to that.
PlatformDestination destinationFor(PlatformArea area) =>
    platformDestinations[area.branchIndex];
