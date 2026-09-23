import '../../../core/access/admin_experience.dart';
import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../l10n/strings.dart';
import '../../detachment/domain/detachment_models.dart';
import '../../inventory/domain/inventory_format.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../shift/domain/shift_models.dart';
import '../../team/domain/team_models.dart';
import '../domain/search_models.dart';

/// Turns a record into the two lines a search row draws.
///
/// One file, four functions, and nothing else: these decide what is
/// *searchable* about each record and what a person reads when it comes back.
/// They are pure so a test can assert on ranking and context without a widget
/// tree, and they take the detachment name as an argument rather than looking
/// it up, so no row costs a second lookup (`§21`, no N+1).
///
/// [detachmentName] is null when the session can see exactly one detachment —
/// repeating its name on every row of a single-detachment session is noise,
/// and the context line exists to tell records *apart*.

/// A member: name, then their section — the two things someone has in mind
/// when they go looking for a person. The personal number is searchable but
/// only shown when there is no section, because a number is an answer to
/// "which one", not an introduction.
SearchResult memberEntry(
  TeamMember member, {
  required int order,
  String? detachmentName,
}) {
  final section = member.department.trim();
  final number = member.personalNumber.trim();
  return SearchResult(
    category: AdminDataCategory.members,
    id: member.id,
    title: member.name,
    subtitle: _line([
      if (section.isNotEmpty)
        section
      else if (number.isNotEmpty)
        '${S.memberNumber} ${toArabicIndic(number)}',
      detachmentName,
    ]),
    secondary: [section, number],
    order: order,
    destination: MemberDestination(
      detachmentId: member.detachmentId,
      memberId: member.id,
    ),
  );
}

/// A detachment: its name, then where it is. Region and main centre are the
/// two fields the detachment repository's own query already searches, so the
/// same words find the same records here.
SearchResult detachmentEntry(Detachment detachment, {required int order}) =>
    SearchResult(
      category: AdminDataCategory.detachments,
      id: detachment.id,
      title: detachment.name,
      subtitle: _line([detachment.region, detachment.mainCenter]),
      secondary: [detachment.region, detachment.mainCenter],
      order: order,
      destination: DetachmentDestination(detachmentId: detachment.id),
    );

/// A shift: the centre it runs at, then the day and the hours — never its id.
///
/// The supervisor is derived from the attendee list (`Shift.manager`), so a
/// shift is findable by the person answerable for it without search inventing
/// a field the domain does not have. The day, the month and the clock are all
/// searchable because a person looking for "the Saturday shift" or "the eight
/// o'clock one" is describing exactly those.
SearchResult shiftEntry(
  Shift shift, {
  required int order,
  String? detachmentName,
}) {
  final day =
      '${AppDate.weekdayOf(shift.date)} ${AppDate.dayMonth(shift.date)}';
  final hours = AppDate.minuteRange(shift.startMinutes, shift.endMinutes);
  final manager = shift.manager?.name;
  return SearchResult(
    category: AdminDataCategory.shifts,
    id: shift.id,
    title: shift.centerName,
    subtitle: _line([
      // No mark between the day and the hours: both end and begin in
      // Arabic-Indic numerals and a ` · ` between them is read as «٠»
      // (UI audit P1-11). `_line` keeps the dot only between prose parts.
      '$day $hours',
      if (manager != null)
        S.searchShiftSupervisedBy.replaceFirst('%s', manager),
      detachmentName,
    ]),
    secondary: [day, hours, if (manager != null) manager],
    order: order,
    destination: ShiftDestination(
      detachmentId: shift.detachmentId,
      shiftId: shift.id,
    ),
  );
}

/// A stock item: its name, then how much of it there is.
///
/// The unit ("أمبولة", "علبة") is searchable because it is the only other
/// human-readable field the item carries — there is no category and no code in
/// the domain, so search does not pretend there is one.
SearchResult inventoryEntry(
  InventoryItem item, {
  required int order,
  String? detachmentName,
}) =>
    SearchResult(
      category: AdminDataCategory.inventory,
      id: item.id,
      title: item.name,
      subtitle: _line([stockBreakdownLabel(item), detachmentName]),
      secondary: [item.unit],
      order: order,
      destination: InventoryDestination(
        detachmentId: item.detachmentId,
        itemId: item.id,
      ),
    );

/// Joins the parts of a context line, dropping the ones that are not there.
String _line(List<String?> parts) => [
      for (final part in parts)
        if (part != null && part.trim().isNotEmpty) part.trim(),
    ].join(' · ');
