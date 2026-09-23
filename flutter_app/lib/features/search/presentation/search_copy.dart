import 'package:flutter/material.dart';

import '../../../core/access/admin_experience.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../l10n/strings.dart';

/// The words and icons Global Search shows for a category.
///
/// Separated from the screen for the reason `notification_copy.dart` is: the
/// models stay copy-free so a test asserts on categories and counts rather
/// than on translated text, and every string still comes from `S`.

IconData searchCategoryIcon(AdminDataCategory category) => switch (category) {
      AdminDataCategory.members => Icons.person_outline_rounded,
      AdminDataCategory.detachments => Icons.flag_outlined,
      AdminDataCategory.shifts => Icons.schedule_rounded,
      AdminDataCategory.inventory => Icons.inventory_2_outlined,
      // Neither is searchable; the switch is total so adding a category to
      // `AdminDataCategory` fails to compile here rather than silently
      // rendering a blank tile.
      AdminDataCategory.statistics => Icons.insights_rounded,
      AdminDataCategory.workshops => Icons.school_rounded,
    };

/// The group heading and the chip label — the plural form.
String searchCategoryLabel(AdminDataCategory category) => switch (category) {
      AdminDataCategory.members => S.searchGroupMembers,
      AdminDataCategory.detachments => S.searchGroupDetachments,
      AdminDataCategory.shifts => S.searchGroupShifts,
      AdminDataCategory.inventory => S.searchGroupInventory,
      AdminDataCategory.statistics => S.detachmentStats,
      AdminDataCategory.workshops => S.navWorkshop,
    };

/// The singular noun the empty prompt is built from.
String searchCategoryNoun(AdminDataCategory category) => switch (category) {
      AdminDataCategory.members => S.searchNounMember,
      AdminDataCategory.detachments => S.searchNounDetachment,
      AdminDataCategory.shifts => S.searchNounShift,
      AdminDataCategory.inventory => S.searchNounItem,
      AdminDataCategory.statistics => S.detachmentStats,
      AdminDataCategory.workshops => S.navWorkshop,
    };

/// "ابدأ بالبحث عن عضو، مفرزة، شفت أو صنف..." — naming only the categories
/// this session may actually search, so the prompt never advertises a group
/// that would come back empty for a reason the user cannot see.
String searchPromptBody(List<AdminDataCategory> allowed) {
  final nouns = [for (final category in allowed) searchCategoryNoun(category)];
  return S.globalSearchPromptBody.replaceFirst('%s', _list(nouns));
}

/// "تعذّر تحميل: الأعضاء، المخزن" — only the sources that actually failed.
String searchDegradedLabel(List<AdminDataCategory> degraded) =>
    S.globalSearchDegraded.replaceFirst(
      '%s',
      [for (final category in degraded) searchCategoryLabel(category)]
          .join('، '),
    );

/// "نتيجة واحدة" / "٧ نتائج".
String searchResultsLabel(int total) => total == 1
    ? S.globalSearchResultsOne
    : S.globalSearchResultsMany
        .replaceFirst('%d', toArabicIndic(total.toString()));

/// "و٥ نتيجة أخرى" — the tail of a group that hit its cap.
String searchHiddenLabel(int hidden) => S.globalSearchMoreResults
    .replaceFirst('%d', toArabicIndic(hidden.toString()));

/// Arabic list separator: commas between all but the last pair, "أو" before
/// the final item.
String _list(List<String> parts) {
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  return '${parts.sublist(0, parts.length - 1).join('، ')} أو ${parts.last}';
}
