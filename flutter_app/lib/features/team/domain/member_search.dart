import '../../../core/text/search_key.dart';
import 'team_models.dart';

/// Client-side roster search and filtering.
///
/// Pure functions over a list the roster provider already loaded — the roster
/// of one detachment is tens of records, not thousands, so filtering it in
/// memory is both correct and instant, and it keeps typing off the network.
///
/// Kept apart from [memberNameKey], which answers a different question.
/// `memberNameKey` decides *identity* ("is this the same person already on the
/// roster") and must therefore stay strict — folding أ into ا there would let
/// two genuinely different records collide. Search is a lookup aid, so it
/// folds the forms a user is likely to type past.

/// The comparison form used by [filterMembers] on both sides of a match.
///
/// Delegates to the app-wide [searchKey] in `core/text/search_key.dart`. The
/// normalization used to live here; it moved down when the platform
/// subscriber list needed the same behaviour, and this name is kept because
/// the roster is where it is read from and because a second spelling of the
/// rule is the thing worth avoiding.
String memberSearchKey(String value) => searchKey(value);

/// The roster narrowed by a free-text query and the chosen facets.
///
/// A member matches the query when it appears anywhere in their name, their
/// section, or their personal number — the three things someone actually has
/// in mind when they go looking for a person. An empty query matches
/// everyone; an empty facet set means "not filtering on this facet" rather
/// than "match nothing", so a filter the user has not touched can never hide
/// the roster.
///
/// Input order is preserved: the roster's own order is meaningful and search
/// is not a ranking.
List<TeamMember> filterMembers(
  List<TeamMember> members, {
  String query = '',
  Set<TeamRole> roles = const {},
  Set<String> departments = const {},
}) {
  final needle = memberSearchKey(query);
  final departmentKeys = {for (final d in departments) memberSearchKey(d)};

  return [
    for (final member in members)
      if (_matches(member, needle, roles, departmentKeys)) member,
  ];
}

bool _matches(
  TeamMember member,
  String needle,
  Set<TeamRole> roles,
  Set<String> departmentKeys,
) {
  if (roles.isNotEmpty && !roles.contains(member.role)) return false;
  if (departmentKeys.isNotEmpty &&
      !departmentKeys.contains(memberSearchKey(member.department))) {
    return false;
  }
  if (needle.isEmpty) return true;
  return memberSearchKey(member.name).contains(needle) ||
      memberSearchKey(member.department).contains(needle) ||
      memberSearchKey(member.personalNumber).contains(needle);
}

/// The sections actually present on this roster, in first-seen order.
///
/// The department field is free text by design (the set differs per
/// detachment), so the filter offers what the data contains rather than a
/// fixed list that would go stale — and offers nothing when the roster
/// carries no sections at all.
List<String> departmentsOf(List<TeamMember> members) {
  final seen = <String>{};
  final out = <String>[];
  for (final member in members) {
    final value = member.department.trim();
    if (value.isEmpty) continue;
    if (seen.add(memberSearchKey(value))) out.add(value);
  }
  return out;
}

/// The roles actually present on this roster, in the enum's own order.
List<TeamRole> rolesOf(List<TeamMember> members) {
  final present = {for (final member in members) member.role};
  return [
    for (final role in TeamRole.values)
      if (present.contains(role)) role,
  ];
}
