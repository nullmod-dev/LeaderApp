import 'dart:math';

import '../../../core/result/result.dart';
import '../../../core/motion/animated_counter.dart';
import '../../team/data/mock_team_repository.dart';
import '../../team/domain/team_models.dart';
import '../../team/domain/team_repository.dart';
import '../domain/workshop_models.dart';
import '../domain/workshop_repository.dart';

/// In-memory workshops. Workshops are organisation-level — they carry no
/// detachment id (see `CAPABILITIES.md` §0, ruling B/Q2).
///
/// The seed covers all three statuses and both the full and the
/// under-subscribed case, so the list, the detail header, and the stats tab
/// all have something real to render.
///
/// People are resolved through [TeamRepository] — the tenant's roster — so a
/// member id that is not on it cannot be put on a workshop, and a register
/// line keeps the member's id rather than only their name. The seeded
/// `registered` / `guests` figures are overwritten on every read by counts of
/// the register itself.
///
/// [workshops] and [participants] replace the seed; the Customer Demo
/// workspace passes its own, and a test can pass an empty set.
class MockWorkshopRepository implements WorkshopRepository {
  MockWorkshopRepository({
    TeamRepository? team,
    List<Workshop>? workshops,
    List<WorkshopParticipant>? participants,
    DateTime Function()? clock,
  })  : _team = team ?? MockTeamRepository(),
        _clock = clock ?? DateTime.now {
    final now = _clock();
    _workshops = List.of(workshops ?? _seedWorkshops(now));
    _parts = List.of(participants ?? _seedParticipants());
  }

  final TeamRepository _team;
  final DateTime Function() _clock;
  late final List<Workshop> _workshops;
  late final List<WorkshopParticipant> _parts;

  final _rand = Random(51);

  /// Feeds the ids of register lines created at runtime.
  int _nextPart = 1;

  static List<Workshop> _seedWorkshops(DateTime now) => [
        Workshop(
          id: 'w1',
          name: 'الإسعاف الأولي المتقدم',
          at: now.add(const Duration(days: 4, hours: 3)),
          location: 'قاعة الشعلان الكبرى',
          capacity: 20,
          registered: 6,
          guests: 3,
          status: WorkshopStatus.scheduled,
          organizingTeam: const [
            TeamMember(
                id: 'm2',
                name: 'ليلى ياسين',
                initials: 'لي',
                role: TeamRole.shiftSupervisor,
                detachmentId: 'd_dam_central',
                attendance: AttendanceState.checkedIn),
            TeamMember(
                id: 'm8',
                name: 'دانا عمر',
                initials: 'دع',
                role: TeamRole.administrator,
                detachmentId: 'd_dam_central',
                attendance: AttendanceState.checkedIn),
          ],
          registrationFee: 25000,
        ),
        Workshop(
          id: 'w2',
          name: 'إدارة الحوادث الجماعية',
          at: now.add(const Duration(days: 11, hours: 2)),
          location: 'قاعة داريا التدريبية',
          capacity: 30,
          registered: 3,
          guests: 1,
          status: WorkshopStatus.scheduled,
          organizingTeam: const [
            TeamMember(
                id: 'm11',
                name: 'ماجد صالح',
                initials: 'مص',
                role: TeamRole.shiftSupervisor,
                detachmentId: 'd_dam_rural',
                attendance: AttendanceState.checkedIn),
            TeamMember(
                id: 'm12',
                name: 'ريم قاسم',
                initials: 'رق',
                role: TeamRole.administrator,
                detachmentId: 'd_dam_rural',
                attendance: AttendanceState.notCheckedIn),
          ],
          registrationFee: 40000,
        ),
        Workshop(
          id: 'w3',
          name: 'إنعاش قلبي رئوي — تجديد',
          at: now.subtract(const Duration(days: 3)),
          location: 'قاعة الشعلان',
          capacity: 5,
          registered: 5,
          guests: 0,
          status: WorkshopStatus.done,
          organizingTeam: const [
            TeamMember(
                id: 'm1',
                name: 'أحمد كنعان',
                initials: 'أك',
                role: TeamRole.shiftSupervisor,
                detachmentId: 'd_dam_central',
                attendance: AttendanceState.checkedIn),
          ],
          registrationFee: 15000,
        ),
        Workshop(
          id: 'w4',
          name: 'فرز المصابين في الميدان',
          at: now.add(const Duration(days: 2, hours: 5)),
          location: 'مركز الوعر — القاعة الشمالية',
          capacity: 3,
          registered: 3,
          guests: 1,
          status: WorkshopStatus.scheduled,
          organizingTeam: const [
            TeamMember(
                id: 'm14',
                name: 'أمين رياض',
                initials: 'أر',
                role: TeamRole.shiftSupervisor,
                detachmentId: 'd_homs',
                attendance: AttendanceState.checkedIn),
          ],
          registrationFee: 0,
        ),
        Workshop(
          id: 'w5',
          name: 'التعامل مع حالات الاختناق',
          at: now.subtract(const Duration(hours: 1)),
          location: 'مركز اللاذقية',
          capacity: 12,
          registered: 3,
          guests: 1,
          status: WorkshopStatus.ongoing,
          organizingTeam: const [
            TeamMember(
                id: 'm15',
                name: 'كنان عيسى',
                initials: 'كع',
                role: TeamRole.shiftSupervisor,
                detachmentId: 'd_coast',
                attendance: AttendanceState.checkedIn),
            TeamMember(
                id: 'm23',
                name: 'ميساء بدر',
                initials: 'مب',
                role: TeamRole.administrator,
                detachmentId: 'd_coast',
                attendance: AttendanceState.checkedIn),
          ],
          registrationFee: 20000,
        ),
        Workshop(
          id: 'w6',
          name: 'مبادئ الإسعاف للمتطوعين الجدد',
          at: now.subtract(const Duration(days: 25)),
          location: 'قاعة داريا التدريبية',
          capacity: 40,
          registered: 0,
          guests: 0,
          status: WorkshopStatus.done,
          organizingTeam: const [
            TeamMember(
                id: 'm11',
                name: 'ماجد صالح',
                initials: 'مص',
                role: TeamRole.shiftSupervisor,
                detachmentId: 'd_dam_rural',
                attendance: AttendanceState.checkedIn),
          ],
          registrationFee: 10000,
        ),
      ];

  static List<WorkshopParticipant> _seedParticipants() => [
        // ---- w1 ----
        const WorkshopParticipant(
            id: 'p1',
            workshopId: 'w1',
            name: 'أحمد كنعان',
            initials: 'أك',
            kind: ParticipantKind.member,
            memberId: 'm1',
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p2',
            workshopId: 'w1',
            name: 'نور الحسن',
            initials: 'نح',
            kind: ParticipantKind.member,
            memberId: 'm4',
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p3',
            workshopId: 'w1',
            name: 'رنا سعيد',
            initials: 'رس',
            kind: ParticipantKind.member,
            memberId: 'm6',
            attendance: AttendanceState.notCheckedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p4',
            workshopId: 'w1',
            name: 'زيد الحلبي',
            initials: 'زح',
            kind: ParticipantKind.guest,
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p5',
            workshopId: 'w1',
            name: 'ميس شامي',
            initials: 'مش',
            kind: ParticipantKind.guest,
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p6',
            workshopId: 'w1',
            name: 'خالد عساف',
            initials: 'خع',
            kind: ParticipantKind.guest,
            attendance: AttendanceState.notCheckedIn,
            paymentStatus: PaymentStatus.unpaid),

        // ---- w2 ----
        const WorkshopParticipant(
            id: 'p7',
            workshopId: 'w2',
            name: 'حسام عابد',
            initials: 'حع',
            kind: ParticipantKind.member,
            memberId: 'm13',
            attendance: AttendanceState.notCheckedIn),
        const WorkshopParticipant(
            id: 'p8',
            workshopId: 'w2',
            name: 'سلمى نجّار',
            initials: 'سن',
            kind: ParticipantKind.member,
            memberId: 'm16',
            attendance: AttendanceState.notCheckedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p9',
            workshopId: 'w2',
            name: 'عمر الدالاتي',
            initials: 'عد',
            kind: ParticipantKind.guest,
            attendance: AttendanceState.notCheckedIn,
            paymentStatus: PaymentStatus.unpaid),

        // ---- w3 (finished — a full attendance record) ----
        const WorkshopParticipant(
            id: 'p10',
            workshopId: 'w3',
            name: 'ليلى ياسين',
            initials: 'لي',
            kind: ParticipantKind.member,
            memberId: 'm2',
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p11',
            workshopId: 'w3',
            name: 'سامي درويش',
            initials: 'سد',
            kind: ParticipantKind.member,
            memberId: 'm3',
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p12',
            workshopId: 'w3',
            name: 'ياسر البكري',
            initials: 'يب',
            kind: ParticipantKind.member,
            memberId: 'm5',
            attendance: AttendanceState.absent,
            paymentStatus: PaymentStatus.unpaid),
        const WorkshopParticipant(
            id: 'p13',
            workshopId: 'w3',
            name: 'هند شحادة',
            initials: 'هش',
            kind: ParticipantKind.member,
            memberId: 'm10',
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p14',
            workshopId: 'w3',
            name: 'طارق خالد',
            initials: 'طخ',
            kind: ParticipantKind.member,
            memberId: 'm7',
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),

        // ---- w4 ----
        const WorkshopParticipant(
            id: 'p15',
            workshopId: 'w4',
            name: 'غادة الحموي',
            initials: 'غح',
            kind: ParticipantKind.member,
            memberId: 'm19',
            attendance: AttendanceState.notCheckedIn),
        const WorkshopParticipant(
            id: 'p16',
            workshopId: 'w4',
            name: 'وسيم الديب',
            initials: 'ود',
            kind: ParticipantKind.member,
            memberId: 'm20',
            attendance: AttendanceState.notCheckedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p17',
            workshopId: 'w4',
            name: 'ريما خضور',
            initials: 'رخ',
            kind: ParticipantKind.guest,
            attendance: AttendanceState.notCheckedIn,
            paymentStatus: PaymentStatus.unpaid),

        // ---- w5 (running now — attendance is being taken) ----
        const WorkshopParticipant(
            id: 'p18',
            workshopId: 'w5',
            name: 'رامي سلوم',
            initials: 'رس',
            kind: ParticipantKind.member,
            memberId: 'm24',
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p19',
            workshopId: 'w5',
            name: 'جود الحلاق',
            initials: 'جح',
            kind: ParticipantKind.member,
            memberId: 'm25',
            attendance: AttendanceState.checkedIn,
            paymentStatus: PaymentStatus.paid),
        const WorkshopParticipant(
            id: 'p20',
            workshopId: 'w5',
            name: 'نبيل مرعي',
            initials: 'نم',
            kind: ParticipantKind.guest,
            attendance: AttendanceState.absent,
            paymentStatus: PaymentStatus.unpaid),

        // w6 keeps no participant record — an old workshop whose sheet was never
        // digitised. The Members tab must render its empty state for it.
      ];

  Future<void> _latency() => Future<void>.delayed(
        Duration(milliseconds: 260 + _rand.nextInt(320)),
      );

  static const _notFound =
      Failure<Never>('لم يُعثر على الورشة.', code: 'not_found');
  static const _archived =
      Failure<Never>('الورشة مؤرشفة. استعدها أولا لتعديلها.', code: 'archived');

  List<WorkshopParticipant> _registerOf(String workshopId) =>
      _parts.where((p) => p.workshopId == workshopId).toList();

  /// The workshop as it is read: its seat counts taken from the register.
  Workshop _counted(Workshop w) {
    final register = _registerOf(w.id);
    return w.copyWith(
      registered: register.length,
      guests: register.where((p) => p.kind == ParticipantKind.guest).length,
    );
  }

  /// The workshop behind [id] when it may be changed, or the failure to
  /// return instead.
  (int, Failure<Never>?) _writable(String id) {
    final i = _workshops.indexWhere((e) => e.id == id);
    if (i < 0) return (i, _notFound);
    if (_workshops[i].archived) return (i, _archived);
    return (i, null);
  }

  /// Resolves roster members by id, all at once. `null` when any one of them
  /// is not on the roster; the failure to return when the roster itself
  /// could not be read.
  Future<(List<TeamMember>?, Result<Never>?)> _resolve(
      List<String> memberIds) async {
    final reads = await Future.wait(memberIds.map(_team.byId));
    final out = <TeamMember>[];
    for (final read in reads) {
      final Result<Never>? problem = read.when(
        success: (member, {stale = false}) {
          out.add(member);
          return null;
        },
        failure: (_, code) => code == 'not_found'
            ? const Failure<Never>('أحد الأعضاء المختارين لم يعد في الفريق.',
                code: 'not_found')
            : const Failure<Never>('تعذّر قراءة قائمة الفريق.',
                code: 'roster_unavailable'),
        offline: (_) => const Offline<Never>(),
      );
      if (problem != null) return (null, problem);
    }
    return (out, null);
  }

  @override
  Future<Result<List<Workshop>>> list() async {
    await _latency();
    final out = _workshops.map(_counted).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return Success(out);
  }

  @override
  Future<Result<Workshop>> byId(String id) async {
    await _latency();
    final i = _workshops.indexWhere((e) => e.id == id);
    // Never fall back to another workshop's record.
    if (i < 0) return _notFound;
    return Success(_counted(_workshops[i]));
  }

  @override
  Future<Result<Workshop>> create({
    required String name,
    required DateTime at,
    required String location,
    required int capacity,
    double registrationFee = 0,
  }) async {
    await _latency();
    if (name.trim().isEmpty || location.trim().isEmpty) {
      return const Failure('الاسم والمكان مطلوبان.', code: 'validation');
    }
    if (capacity <= 0) {
      return const Failure('السعة يجب أن تكون أكبر من صفر.',
          code: 'validation');
    }
    if (registrationFee < 0) {
      return const Failure('رسم الاشتراك لا يكون سالبا.', code: 'validation');
    }
    final w = Workshop(
      id: 'w_${_clock().microsecondsSinceEpoch}',
      name: name.trim(),
      at: at,
      location: location.trim(),
      capacity: capacity,
      registered: 0,
      guests: 0,
      status: WorkshopStatus.scheduled,
      organizingTeam: const [],
      registrationFee: registrationFee,
    );
    _workshops.add(w);
    return Success(w);
  }

  @override
  Future<Result<Workshop>> update(Workshop w) async {
    await _latency();
    final (i, problem) = _writable(w.id);
    if (problem != null) return problem;
    if (w.name.trim().isEmpty || w.location.trim().isEmpty) {
      return const Failure('الاسم والمكان مطلوبان.', code: 'validation');
    }
    if (w.registrationFee < 0) {
      return const Failure('رسم الاشتراك لا يكون سالبا.', code: 'validation');
    }
    final seated = _registerOf(w.id).length;
    if (w.capacity < seated || w.capacity <= 0) {
      return Failure(
        'السعة لا تكون أقل من عدد المسجّلين '
        '(${toArabicIndic('$seated')}).',
        code: 'capacity_below_registered',
      );
    }
    final saved = _workshops[i].copyWith(
      name: w.name.trim(),
      at: w.at,
      location: w.location.trim(),
      capacity: w.capacity,
      status: w.status,
      registrationFee: w.registrationFee,
    );
    _workshops[i] = saved;
    return Success(_counted(saved));
  }

  @override
  Future<Result<Workshop>> setArchived(
    String id, {
    required bool archived,
  }) async {
    await _latency();
    final i = _workshops.indexWhere((e) => e.id == id);
    if (i < 0) return _notFound;
    _workshops[i] = _workshops[i].copyWith(archived: archived);
    return Success(_counted(_workshops[i]));
  }

  @override
  Future<Result<List<WorkshopParticipant>>> participants(
      String workshopId) async {
    await _latency();
    return Success(_registerOf(workshopId));
  }

  @override
  Future<Result<List<WorkshopParticipant>>> addMemberParticipants(
    String workshopId,
    List<String> memberIds,
  ) async {
    await _latency();
    final ids = memberIds.toSet().toList();
    if (ids.isEmpty) return const Success([]);
    final (members, readProblem) = await _resolve(ids);
    if (readProblem != null) return readProblem;

    // Checked after the roster read, against the register as it is now.
    final (i, problem) = _writable(workshopId);
    if (problem != null) return problem;
    final w = _workshops[i];
    final register = _registerOf(workshopId);
    if (register.any((p) => p.memberId != null && ids.contains(p.memberId))) {
      return const Failure('أحد الأعضاء مسجّل في الورشة مسبقا.',
          code: 'duplicate');
    }
    if (w.organizingTeam.any((m) => ids.contains(m.id))) {
      return const Failure('أحد الأعضاء ضمن الفريق المنظِّم لهذه الورشة.',
          code: 'already_organizer');
    }
    if (register.length + ids.length > w.capacity) {
      return Failure(
        'لا تتسع الورشة لهذا العدد. المقاعد المتبقية: '
        '${w.capacity - register.length}.',
        code: 'workshop_full',
      );
    }
    final added = [
      for (final m in members!)
        WorkshopParticipant(
          id: 'p_${workshopId}_${_nextPart++}',
          workshopId: workshopId,
          memberId: m.id,
          name: m.name,
          initials: m.initials,
          kind: ParticipantKind.member,
          attendance: AttendanceState.notCheckedIn,
        ),
    ];
    _parts.addAll(added);
    return Success(added);
  }

  @override
  Future<Result<WorkshopParticipant>> addGuestParticipant(
    String workshopId,
    String name,
  ) async {
    await _latency();
    final (i, problem) = _writable(workshopId);
    if (problem != null) return problem;
    final normalized = normalizeMemberName(name);
    if (normalized.isEmpty) {
      return const Failure('اكتب اسم الضيف.', code: 'validation');
    }
    final register = _registerOf(workshopId);
    final key = memberNameKey(normalized);
    if (register.any((p) =>
        p.kind == ParticipantKind.guest && memberNameKey(p.name) == key)) {
      return const Failure('يوجد ضيف بهذا الاسم في الورشة.', code: 'duplicate');
    }
    if (register.length >= _workshops[i].capacity) {
      return const Failure('الورشة ممتلئة.', code: 'workshop_full');
    }
    final guest = WorkshopParticipant(
      id: 'p_${workshopId}_${_nextPart++}',
      workshopId: workshopId,
      name: normalized,
      initials: TeamMember.initialsOf(normalized),
      kind: ParticipantKind.guest,
      attendance: AttendanceState.notCheckedIn,
    );
    _parts.add(guest);
    return Success(guest);
  }

  /// The register line behind [participantId] when its workshop may be
  /// changed, or the failure to return instead.
  (int, Failure<Never>?) _writablePart(String participantId) {
    final i = _parts.indexWhere((p) => p.id == participantId);
    if (i < 0) {
      return (i, const Failure('لم يُعثر على المشارك.', code: 'not_found'));
    }
    final (_, problem) = _writable(_parts[i].workshopId);
    return (i, problem);
  }

  @override
  Future<Result<void>> removeParticipant(String participantId) async {
    await _latency();
    final (i, problem) = _writablePart(participantId);
    if (problem != null) return problem;
    _parts.removeAt(i);
    return const Success(null);
  }

  @override
  Future<Result<WorkshopParticipant>> setParticipantAttendance(
      String participantId, AttendanceState state) async {
    await _latency();
    final (i, problem) = _writablePart(participantId);
    if (problem != null) return problem;
    _parts[i] = _parts[i].copyWith(attendance: state);
    return Success(_parts[i]);
  }

  @override
  Future<Result<WorkshopParticipant>> setParticipantPayment(
      String participantId, PaymentStatus? status) async {
    await _latency();
    final (i, problem) = _writablePart(participantId);
    if (problem != null) return problem;
    _parts[i] =
        _parts[i].copyWith(paymentStatus: status, clearPayment: status == null);
    return Success(_parts[i]);
  }

  @override
  Future<Result<Workshop>> addOrganizers(
    String workshopId,
    List<String> memberIds,
  ) async {
    await _latency();
    final ids = memberIds.toSet().toList();
    final (members, readProblem) = await _resolve(ids);
    if (readProblem != null) return readProblem;

    final (i, problem) = _writable(workshopId);
    if (problem != null) return problem;
    final w = _workshops[i];
    if (w.organizingTeam.any((m) => ids.contains(m.id))) {
      return const Failure('أحد الأعضاء ضمن الفريق المنظِّم مسبقا.',
          code: 'duplicate');
    }
    if (_registerOf(workshopId)
        .any((p) => p.memberId != null && ids.contains(p.memberId))) {
      return const Failure('أحد الأعضاء مسجّل مشاركا في هذه الورشة.',
          code: 'already_participant');
    }
    final saved = w.copyWith(organizingTeam: [
      ...w.organizingTeam,
      // The roster record, with the attendance that belongs to this
      // workshop: nobody has been checked in to it yet.
      for (final m in members!)
        m.copyWith(
          attendance: AttendanceState.notCheckedIn,
          clearCheckIn: true,
          clearCheckOut: true,
        ),
    ]);
    _workshops[i] = saved;
    return Success(_counted(saved));
  }

  @override
  Future<Result<Workshop>> removeOrganizer(
      String workshopId, String memberId) async {
    await _latency();
    final (i, problem) = _writable(workshopId);
    if (problem != null) return problem;
    final w = _workshops[i];
    if (!w.organizingTeam.any((m) => m.id == memberId)) {
      return const Failure('العضو ليس ضمن الفريق المنظِّم.', code: 'not_found');
    }
    final saved = w.copyWith(organizingTeam: [
      for (final m in w.organizingTeam)
        if (m.id != memberId) m,
    ]);
    _workshops[i] = saved;
    return Success(_counted(saved));
  }

  @override
  Future<Result<Workshop>> setOrganizerAttendance(
    String workshopId,
    String memberId,
    AttendanceState state,
  ) async {
    await _latency();
    final (i, problem) = _writable(workshopId);
    if (problem != null) return problem;
    final w = _workshops[i];
    if (!w.organizingTeam.any((m) => m.id == memberId)) {
      return const Failure('العضو ليس ضمن الفريق المنظِّم.', code: 'not_found');
    }
    final saved = w.copyWith(organizingTeam: [
      for (final m in w.organizingTeam)
        m.id == memberId ? m.copyWith(attendance: state) : m,
    ]);
    _workshops[i] = saved;
    return Success(_counted(saved));
  }
}
