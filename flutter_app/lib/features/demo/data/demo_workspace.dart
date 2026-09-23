import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../announcement/data/mock_announcement_repository.dart';
import '../../announcement/domain/announcement_repository.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/domain/session_access.dart';
import '../../detachment/data/mock_detachment_repository.dart';
import '../../detachment/domain/detachment_repository.dart';
import '../../detachment_group/data/mock_detachment_group_repository.dart';
import '../../detachment_group/domain/detachment_group_repository.dart';
import '../../home/data/mock_home_repository.dart';
import '../../home/domain/home_repository.dart';
import '../../inventory/data/mock_inventory_repository.dart';
import '../../inventory/domain/inventory_repository.dart';
import '../../notification/data/mock_notification_repository.dart';
import '../../notification/domain/notification_repository.dart';
import '../../shift/data/mock_shift_repository.dart';
import '../../shift/domain/shift_repository.dart';
import '../../team/data/mock_team_repository.dart';
import '../../team/domain/team_repository.dart';
import '../../workshop/data/mock_workshop_repository.dart';
import '../../workshop/domain/workshop_repository.dart';
import '../domain/demo_seed.dart';

/// The Customer Demo workspace: one object owning a **complete, isolated set
/// of repositories**, seeded from [DemoSeed].
///
/// This is the isolation boundary, and it is deliberately one object rather
/// than an `if (demo)` in every screen. Each repository provider asks
/// [demoWorkspaceProvider] first and serves the demo instance when there is
/// one; a screen, a controller and a report therefore all read demo data
/// without knowing that they do.
///
/// Everything in it lives in memory for as long as the demo session does.
/// Nothing here writes to a tenant repository, a `SaasTenant`, a Team Code, a
/// membership, the sync outbox or any backend: the demo's repositories *are*
/// the whole world it can reach. When the session ends, the provider rebuilds
/// to `null` and every mutation made inside the demo is gone with it.
class DemoWorkspace {
  DemoWorkspace({DateTime Function()? clock})
      : team = MockTeamRepository(members: DemoSeed.members()),
        detachments =
            MockDetachmentRepository(detachments: DemoSeed.detachments()) {
    shifts = MockShiftRepository(
      team,
      clock: clock,
      plan: DemoSeed.shiftPlan,
      // A demo workspace has no ended detachment, so it seeds no archive.
      history: const {},
    );
    inventory = MockInventoryRepository(
      items: DemoSeed.inventory(),
      movements: DemoSeed.movements(),
    );
    workshops = MockWorkshopRepository(
      team: team,
      workshops: DemoSeed.workshops(),
      participants: DemoSeed.workshopParticipants(),
      clock: clock,
    );
    detachmentGroups = MockDetachmentGroupRepository(
      detachments,
      groups: DemoSeed.groups(),
    );
    announcements = MockAnnouncementRepository(clock: clock);
    home = MockHomeRepository(
      detachments: detachments,
      shifts: shifts,
      inventory: inventory,
      team: team,
    );
    notifications = MockNotificationRepository(
      shifts: shifts,
      inventory: inventory,
      clock: clock,
    );
  }

  final TeamRepository team;
  final DetachmentRepository detachments;
  late final DetachmentGroupRepository detachmentGroups;
  late final ShiftRepository shifts;
  late final InventoryRepository inventory;
  late final WorkshopRepository workshops;
  late final AnnouncementRepository announcements;
  late final HomeRepository home;
  late final NotificationRepository notifications;
}

/// Whether the session in hand is a Customer Demo.
///
/// **Both halves must agree**, exactly as the startup classifier requires: the
/// demo identity *and* the server's demo envelope. A demo role without the
/// envelope (or the reverse) is a malformed session, which the classifier
/// sends to `invalidSession` — so no product surface renders and no
/// repository here is ever built for it.
final isCustomerDemoSessionProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final access = ref.watch(sessionAccessProvider);
  return user?.role == AuthRole.customerDemo && access.demo == DemoMode.active;
});

/// The live demo workspace, or `null` for every real session.
///
/// Rebuilding it is how the demo resets: the moment the session stops being a
/// demo — the trial ends, somebody signs in — this provider answers `null`,
/// every repository provider switches back to the ordinary ones, and the demo
/// workspace (with everything done inside it) is dropped.
final demoWorkspaceProvider = Provider<DemoWorkspace?>((ref) {
  if (!ref.watch(isCustomerDemoSessionProvider)) return null;
  return DemoWorkspace(clock: ref.watch(clockProvider));
});
