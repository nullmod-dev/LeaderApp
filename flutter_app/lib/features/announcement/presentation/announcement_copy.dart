import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../l10n/strings.dart';
import '../domain/announcement_models.dart';
import '../domain/announcement_selectors.dart';

/// Turns an announcement value into the words a screen shows.
///
/// Separated from the widgets so the domain stays copy-free (a test asserts on
/// an [AnnouncementRefusal], never on translated text) and from the selectors
/// so the domain stays free of Flutter — the same split
/// `notification_copy.dart` keeps.

/// Why a publish was refused, in one sentence the author can act on.
String announcementRefusalMessage(AnnouncementRefusal reason) =>
    switch (reason) {
      AnnouncementRefusal.emptyText => S.announcementTextRequired,
      AnnouncementRefusal.textTooShort => S.announcementTextTooShort,
      AnnouncementRefusal.textTooLong => S.announcementTextTooLong,
      AnnouncementRefusal.noTarget => S.announcementTargetRequired,
      AnnouncementRefusal.unauthorizedTarget =>
        S.announcementTargetNotPermitted,
      AnnouncementRefusal.archivedTarget => S.announcementTargetArchived,
      AnnouncementRefusal.expiryNotInFuture => S.announcementExpiryInvalid,
    };

/// The lifetime presets, as the compose screen labels them.
String announcementDurationLabel(AnnouncementDuration d) => switch (d) {
      AnnouncementDuration.hour => S.announcementDurationHour,
      AnnouncementDuration.sixHours => S.announcementDurationSixHours,
      AnnouncementDuration.twelveHours => S.announcementDurationTwelveHours,
      AnnouncementDuration.day => S.announcementDurationDay,
      AnnouncementDuration.twoDays => S.announcementDurationTwoDays,
      AnnouncementDuration.custom => S.announcementDurationCustom,
    };

/// Where an announcement stands right now, in one word.
///
/// Three states and they are not interchangeable: *stopped* is a person's
/// decision, *ended* is the clock's. An administrator looking at the list needs
/// to know which of the two happened.
String announcementStateLabel(Announcement a, DateTime now) {
  if (a.isWithdrawn) return S.announcementStateWithdrawn;
  return isAnnouncementActive(a, now)
      ? S.announcementStateActive
      : S.announcementStateExpired;
}

/// How many detachments an announcement addresses.
String announcementTargetsLabel(int count) => count == 1
    ? S.announcementTargetsCountOne
    : S.announcementTargetsCountMany
        .replaceFirst('%d', toArabicIndic('$count'));

/// When the announcement's active placements stop.
String announcementEndsLabel(Announcement a) =>
    S.announcementEndsAt.replaceFirst('%s', AppDate.dayMonthTime(a.expiresAt));

/// The line under a promoted card when more than one announcement is live on
/// Home. Never a stack of banners — one card, and a count.
String announcementHomeMoreLabel(int others) => others == 1
    ? S.announcementHomeMoreOne
    : S.announcementHomeMore.replaceFirst('%d', toArabicIndic('$others'));
