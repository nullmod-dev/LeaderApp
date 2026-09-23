import '../../detachment/domain/detachment_models.dart';
import '../../detachment_group/domain/detachment_group_models.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../shift/domain/shift_models.dart';
import '../../team/domain/team_models.dart';
import '../../workshop/domain/workshop_models.dart';

/// The sample data the Customer Demo workspace is built from.
///
/// Deliberately small: **exactly two detachments and exactly two workshops**,
/// one shared roster of ten people, and enough stock, schedule and register
/// for every tenant screen to have something real to show. A demo that seeded
/// twenty of everything would demonstrate the seed, not the product.
///
/// Every id carries a `demo`/`dm` prefix, so a demo record is recognisable on
/// sight and can never be mistaken for — or collide with — a tenant record.
/// Nothing here is a `SaasTenant`, a Team Code or a membership.
abstract final class DemoSeed {
  static const groupId = 'g_demo';
  static const cityDetachment = 'd_demo_city';
  static const fieldDetachment = 'd_demo_field';

  /// The two detachments, in the order the demo shows them.
  static const detachmentIds = [cityDetachment, fieldDetachment];

  static List<DetachmentGroup> groups() => [
        DetachmentGroup(
          id: groupId,
          name: 'فرق التجربة',
          createdAt: DateTime.now().subtract(const Duration(days: 210)),
          notes: 'مجموعة نموذجية لعرض التطبيق.',
        ),
      ];

  static List<Detachment> detachments() => const [
        Detachment(
          id: cityDetachment,
          detachmentGroupId: groupId,
          name: 'مفرزة المدينة',
          region: 'المدينة',
          mainCenter: 'المركز الرئيسي',
          memberCount: 6,
          weeklyShiftCount: 6,
          coveragePercent: 88,
          status: DetachmentStatus.active,
          notes: 'تغطية جيدة خلال الأسبوعين الماضيين.',
        ),
        Detachment(
          id: fieldDetachment,
          detachmentGroupId: groupId,
          name: 'مفرزة الميدان',
          region: 'الريف',
          mainCenter: 'نقطة الميدان',
          memberCount: 4,
          weeklyShiftCount: 4,
          coveragePercent: 71,
          status: DetachmentStatus.active,
          notes: 'نقص متكرر في الوردية المسائية.',
        ),
      ];

  /// One roster, shared by the whole workspace: the workshops register from
  /// it, the shifts assign from it, and the statistics count it.
  static List<TeamMember> members() => [
        _member('dm1', 'سامر الحاج', 'الإسعاف', '101', TeamRole.shiftSupervisor,
            cityDetachment, AttendanceState.checkedIn),
        _member('dm2', 'لينا الخوري', 'الإسعاف', '102', TeamRole.administrator,
            cityDetachment, AttendanceState.checkedIn),
        _member('dm3', 'كرم الدين', 'اللوجستيات', '103', TeamRole.member,
            cityDetachment, AttendanceState.checkedIn),
        _member('dm4', 'هدى مرعي', 'الإسعاف', '104', TeamRole.followUp,
            cityDetachment, AttendanceState.notCheckedIn),
        _member('dm5', 'باسل نعمة', 'اللوجستيات', '105', TeamRole.member,
            cityDetachment, AttendanceState.notCheckedIn),
        _member('dm6', 'رهام سعد', 'الإسعاف', '106', TeamRole.administrator,
            cityDetachment, AttendanceState.checkedIn),
        _member('dm7', 'وائل حمدان', 'الإسعاف', '201',
            TeamRole.shiftSupervisor, fieldDetachment, AttendanceState.checkedIn),
        _member('dm8', 'ديما عقيل', 'الإسعاف', '202', TeamRole.member,
            fieldDetachment, AttendanceState.notCheckedIn),
        _member('dm9', 'زياد الأسمر', 'اللوجستيات', '203', TeamRole.member,
            fieldDetachment, AttendanceState.checkedIn),
        _member('dm10', 'نغم قاسم', 'الإسعاف', '204', TeamRole.followUp,
            fieldDetachment, AttendanceState.notCheckedIn),
      ];

  static TeamMember _member(
    String id,
    String name,
    String department,
    String number,
    TeamRole role,
    String detachmentId,
    AttendanceState attendance,
  ) =>
      TeamMember(
        id: id,
        name: name,
        initials: TeamMember.initialsOf(name),
        department: department,
        personalNumber: number,
        role: role,
        detachmentId: detachmentId,
        attendance: attendance,
        phoneMasked: '+963 9xx xx xx ${number.substring(1)}',
      );

  /// A small week per detachment: enough to open the schedule, see who is
  /// assigned, and assign somebody else.
  static const shiftPlan = <String,
      List<
          (
            int weekday,
            ShiftPeriod period,
            String center,
            int needed,
            List<String> members
          )>>{
    cityDetachment: [
      (DateTime.saturday, ShiftPeriod.morning, 'المركز الرئيسي', 4, [
        'dm1',
        'dm2',
        'dm3'
      ]),
      (DateTime.sunday, ShiftPeriod.evening, 'المركز الرئيسي', 3, ['dm4']),
      (DateTime.tuesday, ShiftPeriod.morning, 'نقطة السوق', 3, ['dm1', 'dm6']),
    ],
    fieldDetachment: [
      (DateTime.saturday, ShiftPeriod.evening, 'نقطة الميدان', 3, [
        'dm7',
        'dm8'
      ]),
      (DateTime.wednesday, ShiftPeriod.morning, 'نقطة الميدان', 3, ['dm9']),
    ],
  };

  /// Six stock lines, including one low and one expiring, so the Storage tab
  /// and its warnings both have something to say.
  static List<InventoryItem> inventory() => [
        InventoryItem(
          id: 'di1',
          detachmentId: cityDetachment,
          name: 'ضمادات معقمة',
          unit: 'عبوة',
          currentStock: 8,
          minimum: 20,
          expiresOn: DateTime.now().add(const Duration(days: 180)),
          level: StockLevel.low,
        ),
        InventoryItem(
          id: 'di2',
          detachmentId: cityDetachment,
          name: 'محلول ملحي ٥٠٠ مل',
          unit: 'كيس',
          currentStock: 40,
          minimum: 15,
          expiresOn: DateTime.now().add(const Duration(days: 26)),
          level: StockLevel.ok,
        ),
        InventoryItem(
          id: 'di3',
          detachmentId: cityDetachment,
          name: 'قفازات فحص',
          unit: 'علبة',
          currentStock: 22,
          minimum: 10,
          expiresOn: DateTime.now().add(const Duration(days: 300)),
          level: StockLevel.ok,
        ),
        InventoryItem(
          id: 'di4',
          detachmentId: fieldDetachment,
          name: 'شاش طبي',
          unit: 'لفة',
          currentStock: 5,
          minimum: 12,
          expiresOn: DateTime.now().add(const Duration(days: 150)),
          level: StockLevel.low,
        ),
        InventoryItem(
          id: 'di5',
          detachmentId: fieldDetachment,
          name: 'كمامات جراحية',
          unit: 'علبة',
          currentStock: 18,
          minimum: 8,
          expiresOn: DateTime.now().add(const Duration(days: 420)),
          level: StockLevel.ok,
        ),
        InventoryItem(
          id: 'di6',
          detachmentId: fieldDetachment,
          name: 'مسكّن ألم ٥٠٠ ملغ',
          unit: 'وحدة',
          currentStock: 60,
          minimum: 30,
          expiresOn: DateTime.now().add(const Duration(days: 40)),
          level: StockLevel.ok,
          unitsPerStrip: 10,
          stripsPerCarton: 10,
          preferredUnit: PackagingUnit.strip,
        ),
      ];

  static List<InventoryMovement> movements() => [
        InventoryMovement(
          id: 'dmv1',
          itemId: 'di1',
          direction: MovementDirection.outflow,
          quantity: 4,
          reason: 'استهلاك في وردية السبت',
          at: DateTime.now().subtract(const Duration(days: 2)),
          performedBy: 'dm1',
          performedByName: 'سامر الحاج',
        ),
        InventoryMovement(
          id: 'dmv2',
          itemId: 'di2',
          direction: MovementDirection.inflow,
          quantity: 20,
          reason: 'توريد شهري',
          at: DateTime.now().subtract(const Duration(days: 6)),
          performedBy: 'dm2',
          performedByName: 'لينا الخوري',
        ),
        InventoryMovement(
          id: 'dmv3',
          itemId: 'di4',
          direction: MovementDirection.outflow,
          quantity: 3,
          reason: 'استهلاك ميداني',
          at: DateTime.now().subtract(const Duration(days: 1)),
          performedBy: 'dm7',
          performedByName: 'وائل حمدان',
        ),
      ];

  /// **Exactly two** workshops: one ahead, taking registrations, and one that
  /// has run, so the statistics tab has a finished record to draw.
  static List<Workshop> workshops() => [
        Workshop(
          id: 'dw1',
          name: 'الإسعاف الأولي للمتطوعين',
          at: DateTime.now().add(const Duration(days: 5, hours: 2)),
          location: 'قاعة المركز الرئيسي',
          capacity: 12,
          registered: 0,
          guests: 0,
          status: WorkshopStatus.scheduled,
          organizingTeam: [members()[0]], // سامر الحاج
          registrationFee: 15000,
        ),
        Workshop(
          id: 'dw2',
          name: 'التعامل مع الإصابات الميدانية',
          at: DateTime.now().subtract(const Duration(days: 6)),
          location: 'نقطة الميدان',
          capacity: 8,
          registered: 0,
          guests: 0,
          status: WorkshopStatus.done,
          organizingTeam: [members()[6]], // وائل حمدان
          registrationFee: 0,
        ),
      ];

  static List<WorkshopParticipant> workshopParticipants() => [
        _participant('dp1', 'dw1', 'dm2', 'لينا الخوري',
            AttendanceState.notCheckedIn, PaymentStatus.paid),
        _participant('dp2', 'dw1', 'dm3', 'كرم الدين',
            AttendanceState.notCheckedIn, null),
        _participant('dp3', 'dw1', 'dm8', 'ديما عقيل',
            AttendanceState.notCheckedIn, PaymentStatus.unpaid),
        const WorkshopParticipant(
          id: 'dp4',
          workshopId: 'dw1',
          name: 'مها العلي',
          initials: 'ما',
          kind: ParticipantKind.guest,
          attendance: AttendanceState.notCheckedIn,
          paymentStatus: PaymentStatus.paid,
        ),
        _participant('dp5', 'dw2', 'dm9', 'زياد الأسمر',
            AttendanceState.checkedIn, PaymentStatus.paid),
        _participant('dp6', 'dw2', 'dm10', 'نغم قاسم', AttendanceState.absent,
            PaymentStatus.unpaid),
        _participant('dp7', 'dw2', 'dm4', 'هدى مرعي', AttendanceState.checkedIn,
            PaymentStatus.paid),
      ];

  static WorkshopParticipant _participant(
    String id,
    String workshopId,
    String memberId,
    String name,
    AttendanceState attendance,
    PaymentStatus? payment,
  ) =>
      WorkshopParticipant(
        id: id,
        workshopId: workshopId,
        memberId: memberId,
        name: name,
        initials: TeamMember.initialsOf(name),
        kind: ParticipantKind.member,
        attendance: attendance,
        paymentStatus: payment,
      );
}
