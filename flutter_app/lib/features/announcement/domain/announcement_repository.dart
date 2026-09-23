import '../../../core/result/result.dart';
import 'announcement_models.dart';

/// The announcement seam.
///
/// **No backend implements this yet.** Re-audited 2026-09-07 and the answer is
/// the same as it was at Point 4: `API_CONTRACT.md` has no announcement
/// endpoint and no server emits one. What ships is this interface, a mock that
/// stores announcements in memory, and the contract the backend is expected to
/// serve — written down in `API_CONTRACT.md` § Announcements rather than
/// invented in code. Nothing in the app pretends a request went anywhere.
///
/// Three methods and no more:
///
/// * [list] — everything the caller may see. Scope narrowing is applied by the
///   caller through `visibleAnnouncements`, exactly as the notification feed
///   narrows its own rows; a real backend must narrow it server-side too.
/// * [publish] — one announcement, once.
/// * [withdraw] — stop delivering one. Deliberately **not** `delete`: the
///   Notifications Center entry is history and is not the creator's to erase.
///
/// There is no `update`. Editing a notice that has already been read by other
/// administrators would rewrite what a detachment was told; withdrawing and
/// publishing again says what actually happened.
abstract class AnnouncementRepository {
  /// Every announcement this client knows about, in no required order.
  Future<Result<List<Announcement>>> list();

  /// One announcement by id, re-read at the moment it is opened — which is
  /// what turns a withdrawn-and-gone notice into a sentence rather than a
  /// stale screen.
  Future<Result<Announcement>> byId(String id);

  /// Publishes one announcement and returns the stored record.
  ///
  /// The caller has already validated ([refuseAnnouncement]) and revalidated
  /// its targets against the live grant. `publishedAt` and `expiresAt` are
  /// passed in rather than computed here so the whole feature reads one clock.
  Future<Result<Announcement>> publish({
    required String text,
    required List<String> detachmentIds,
    required Set<AnnouncementPlacement> placements,
    required DateTime publishedAt,
    required DateTime expiresAt,
    String? authorName,
  });

  /// Stops [id]'s active placements. Idempotent: withdrawing an already
  /// withdrawn announcement succeeds and changes nothing.
  Future<Result<Announcement>> withdraw(String id);
}
