import '../../../core/result/result.dart';
import '../domain/announcement_models.dart';
import '../domain/announcement_repository.dart';

/// In-memory announcements, seeded so every surface this feature adds can be
/// opened and looked at in a development build.
///
/// **Seeded, not derived** — and that is the opposite of what
/// `MockNotificationRepository` does, on purpose. A notification is a
/// projection of a record that exists elsewhere, so seeding one would put a row
/// on screen pointing at nothing. An announcement *is* the record: it is
/// written by a person and stored, and there is nothing else in the app to
/// derive it from. So the mock holds real announcement records, and the
/// notification feed derives its rows from them exactly as a backend-fed client
/// would.
///
/// **Lifetime of this object only.** The same gap the theme preference, the
/// active-detachment choice and notification read state have (`HANDOFF.md`):
/// there is no durable local store in this build, so a relaunch re-seeds. The
/// seam is complete — a repository writing `Announcement.toJson()` to local
/// storage or to a real endpoint drops in without touching a caller.
///
/// **The clock is injected and pinned once**, in the constructor. Fixtures are
/// positioned relative to that single instant rather than to `DateTime.now()`
/// per read, so "published fifteen minutes ago" does not drift into "published
/// an hour ago" while the app is open, and a test that pins the clock gets
/// exactly the seven records described below.
class MockAnnouncementRepository implements AnnouncementRepository {
  MockAnnouncementRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _seed(_clock());
  }

  final DateTime Function() _clock;
  final List<Announcement> _items = [];

  /// Monotonic suffix for ids minted by [publish]. Deterministic, unlike a
  /// timestamp: two announcements published inside the same millisecond must
  /// not collide on one id.
  int _nextId = 0;

  static Future<void> _latency() =>
      Future<void>.delayed(const Duration(milliseconds: 180));

  /// Seven records, each one there to make a specific state visible.
  ///
  /// Together they cover: one active single-target announcement, one addressed
  /// to several detachments, one inside its first hour on Home, one past that
  /// hour but still in history, one fully expired, one withdrawn, and one
  /// addressed to a detachment a narrowly scoped session cannot see.
  void _seed(DateTime now) {
    _items.addAll([
      // 1. Active, one detachment, on the detachment surface. The plain case.
      Announcement(
        id: 'a_seed_1',
        text: 'تنبيه بخصوص شفت ٤:٠٠–١٠:٠٠ اليوم، يرجى الحضور قبل بداية '
            'الشفت بـ١٥ دقيقة.',
        detachmentIds: const ['d_dam_central'],
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.detachment,
        },
        publishedAt: now.subtract(const Duration(hours: 3)),
        expiresAt: now.add(const Duration(hours: 21)),
        authorName: 'أحمد عبد الكريم',
      ),

      // 2. Several detachments at once — the multi-target case the target
      //    picker builds.
      Announcement(
        id: 'a_seed_2',
        text: 'اجتماع المسؤولين يوم الخميس الساعة ٧ مساءً في المركز الرئيسي. '
            'الحضور مطلوب من مسؤول كل مفرزة.',
        detachmentIds: const ['d_dam_central', 'd_dam_rural', 'd_homs'],
        placements: const {AnnouncementPlacement.notifications},
        publishedAt: now.subtract(const Duration(minutes: 40)),
        expiresAt: now.add(const Duration(hours: 12)),
        authorName: 'أحمد عبد الكريم',
      ),

      // 3. Inside its first hour on Home — the promoted card.
      Announcement(
        id: 'a_seed_3',
        text: 'انقطاع الماء عن مركز الشعلان اليوم. أحضروا معكم ماء الشرب.',
        detachmentIds: const ['d_dam_central'],
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.home,
          AnnouncementPlacement.detachment,
        },
        publishedAt: now.subtract(const Duration(minutes: 12)),
        expiresAt: now.add(const Duration(hours: 24)),
        authorName: 'أحمد عبد الكريم',
      ),

      // 4. Home placement chosen, but published four hours ago: gone from the
      //    dashboard, still in the Notifications Center. The rule that the
      //    one-hour promotion is not the announcement's lifetime.
      Announcement(
        id: 'a_seed_4',
        text: 'تم تحديث أرقام الطوارئ. راجعوا اللوحة في غرفة المناوبة.',
        detachmentIds: const ['d_dam_central'],
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.home,
        },
        publishedAt: now.subtract(const Duration(hours: 4)),
        expiresAt: now.add(const Duration(hours: 20)),
        authorName: 'أحمد عبد الكريم',
      ),

      // 5. Expired two days ago. No active placement anywhere; the history row
      //    remains until notifications are cleared deliberately.
      Announcement(
        id: 'a_seed_5',
        text: 'تدريب الإنعاش القلبي الرئوي أُجّل إلى الأسبوع القادم.',
        detachmentIds: const ['d_dam_central'],
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.home,
          AnnouncementPlacement.detachment,
        },
        publishedAt: now.subtract(const Duration(days: 3)),
        expiresAt: now.subtract(const Duration(days: 2)),
        authorName: 'أحمد عبد الكريم',
      ),

      // 6. Withdrawn while still inside its lifetime — the management screen's
      //    "stopped" state, and a history row that says so.
      Announcement(
        id: 'a_seed_6',
        text: 'طلب متطوعين إضافيين لشفت الليل — تم تأمين العدد، شكرا لكم.',
        detachmentIds: const ['d_homs'],
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.detachment,
        },
        publishedAt: now.subtract(const Duration(hours: 6)),
        expiresAt: now.add(const Duration(hours: 18)),
        status: AnnouncementStatus.withdrawn,
        authorName: 'أحمد عبد الكريم',
      ),

      // 7. Addressed to the coast only. A session scoped to Damascus must
      //    never see this one — the fixture the scope tests rest on.
      Announcement(
        id: 'a_seed_7',
        text: 'توزيع المستلزمات الجديدة على مراكز الساحل غدا صباحا.',
        detachmentIds: const ['d_coast'],
        placements: const {
          AnnouncementPlacement.notifications,
          AnnouncementPlacement.home,
        },
        publishedAt: now.subtract(const Duration(minutes: 30)),
        expiresAt: now.add(const Duration(hours: 10)),
        authorName: 'أحمد عبد الكريم',
      ),
    ]);
  }

  @override
  Future<Result<List<Announcement>>> list() async {
    await _latency();
    return Success(List<Announcement>.unmodifiable(_items));
  }

  @override
  Future<Result<Announcement>> byId(String id) async {
    await _latency();
    final i = _items.indexWhere((a) => a.id == id);
    if (i < 0) {
      return const Failure('لم يعد هذا الإعلان متاحا.', code: 'not_found');
    }
    return Success(_items[i]);
  }

  @override
  Future<Result<Announcement>> publish({
    required String text,
    required List<String> detachmentIds,
    required Set<AnnouncementPlacement> placements,
    required DateTime publishedAt,
    required DateTime expiresAt,
    String? authorName,
  }) async {
    await _latency();
    // The domain already refused these; the repository refuses them again
    // because a repository that trusts its caller is a repository that stores
    // an announcement addressed to nobody the first time a caller is added.
    final trimmed = text.trim();
    if (trimmed.length < announcementTextMin ||
        trimmed.length > announcementTextMax) {
      return const Failure('نص الإعلان غير صالح.', code: 'validation');
    }
    if (detachmentIds.isEmpty) {
      return const Failure('اختر مفرزة واحدة على الأقل.', code: 'validation');
    }
    if (!expiresAt.isAfter(publishedAt)) {
      return const Failure('مدة الإعلان غير صالحة.', code: 'validation');
    }

    final record = Announcement(
      id: 'a_${++_nextId}_${publishedAt.millisecondsSinceEpoch}',
      text: trimmed,
      detachmentIds: List<String>.unmodifiable(detachmentIds),
      placements: {
        AnnouncementPlacement.notifications,
        ...placements,
      },
      publishedAt: publishedAt,
      expiresAt: expiresAt,
      authorName: authorName,
    );
    _items.add(record);
    return Success(record);
  }

  @override
  Future<Result<Announcement>> withdraw(String id) async {
    await _latency();
    final i = _items.indexWhere((a) => a.id == id);
    if (i < 0) {
      return const Failure('لم يعد هذا الإعلان متاحا.', code: 'not_found');
    }
    // Idempotent: withdrawing twice is not an error, it is the same outcome.
    final stopped = _items[i].copyWith(status: AnnouncementStatus.withdrawn);
    _items[i] = stopped;
    return Success(stopped);
  }
}
