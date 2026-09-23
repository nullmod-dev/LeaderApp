/// Which of a detachment's tabs one grant opens, and where opening the
/// detachment lands.
///
/// The detail shell, the detachment list and Global Search all answer the
/// same two questions, so they answer them here — once, through
/// `Capabilities.canIn`, the single resolver. When the list asked nothing and
/// always opened the roster, a scoped administrator without `member.view`
/// tapped their own detachment and was bounced to Home by the roster's route
/// guard (Point 16).
///
/// TODO(security): presentation only, like every client-side access
/// decision. The route guards still refuse each tab on their own, and the
/// backend refuses the reads behind them.
///
/// Pure Dart on purpose, like `core/access/`.
library;

import '../../../core/access/capability.dart';

/// Whether the detail shell's tab bar offers [tab] (`team`, `shifts`,
/// `storage` or `stats`) inside [detachmentId].
///
/// The roster is gated on `member.view` exactly as its route is. Statistics
/// are gated on `stats.view`: its route opens on `detachment.view` and keeps a
/// designed denied state for a direct link, but a tab whose every visit ends
/// on that state is not worth offering. The schedule and the store follow
/// membership (`shift.view` / `inventory.view` were dropped for gating
/// nothing), so they open wherever the detachment itself is visible. Feature
/// availability is a separate axis and is applied by the shell, not here.
bool detachmentTabOffered(
  Capabilities caps,
  String detachmentId,
  String tab,
) =>
    switch (tab) {
      'team' => caps.canIn(detachmentId, Cap.memberView),
      'stats' => caps.canIn(detachmentId, Cap.statsView),
      _ => caps.canIn(detachmentId, Cap.detachmentView),
    };

/// Which tab opening [detachmentId] lands on.
///
/// The roster is the useful landing tab, but its route refuses a session
/// without `member.view`; the schedule opens on `detachment.view` alone.
/// Asked at the moment of the tap, so a grant that narrows mid-session cannot
/// leave a row pointing at a tab the router will bounce.
String detachmentTabFor(Capabilities caps, String detachmentId) =>
    detachmentTabOffered(caps, detachmentId, 'team') ? 'team' : 'shifts';
