import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guards for the shared UI foundation.
///
/// Every rule below was a real defect before Phase 1 of the UI quality
/// programme, and every one is the kind that comes back the next time
/// somebody writes a screen in a hurry: a `chevron_left` that looks forward
/// until Arabic mirrors it, a sixth private `_Filter`, a bare `AlertDialog`
/// where a destructive confirmation belongs. A widget test cannot catch a
/// *new* file doing the wrong thing; reading the source can.
///
/// These name the offender and the rule, and each one has an escape hatch
/// stated in the failure message — none of them is a law of nature.

final _libDir = Directory('lib');

Iterable<File> _dartFiles() => _libDir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

/// Path → the lines in it matching [pattern], as `path:line  text`.
List<String> _hits(
  Pattern pattern, {
  bool Function(String path)? skipFile,
  bool Function(String line)? skipLine,
}) {
  final out = <String>[];
  for (final file in _dartFiles()) {
    final path = file.path;
    if (skipFile != null && skipFile(path)) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Never flag a doc comment or a plain comment: the rules below are
      // explained in prose that necessarily names the thing it forbids.
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//')) continue;
      if (skipLine != null && skipLine(line)) continue;
      if (line.contains(pattern)) out.add('$path:${i + 1}  ${line.trim()}');
    }
  }
  out.sort();
  return out;
}

/// Returns one balanced constructor call beginning at [openParen]. Dart UI
/// constructors routinely contain callbacks and nested widgets, so a fixed
/// number of lines is not enough to decide whether a named argument exists.
String _balancedCall(String source, int openParen) {
  var depth = 0;
  String? quote;
  var escaped = false;
  for (var i = openParen; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
    } else if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return source.substring(openParen, i + 1);
    }
  }
  return source.substring(openParen);
}

void main() {
  group('forward navigation', () {
    test('no screen picks a directional chevron by hand', () {
      final hits = _hits(
        RegExp(r'Icons\.chevron_(left|right)_rounded'),
        skipFile: (p) =>
            // The one file allowed to name the glyphs: it is where the rule
            // is stated.
            p.endsWith('core/widgets/forward_chevron.dart'),
      );
      expect(
        hits,
        isEmpty,
        reason: 'Forward disclosure is `ForwardChevron`; a week/period arrow '
            'is `DirectionalArrows.earlier` / `.later`. Both rounded chevrons '
            'mirror under RTL, so picking one at a call site is how an arrow '
            'ends up pointing backwards in Arabic (UI audit P1-1). If a new '
            'case genuinely needs a different glyph, add it to '
            '`core/widgets/forward_chevron.dart` with the reasoning.\n'
            '${hits.join('\n')}',
      );
    });

    test('nothing mirrors an icon a second time by hand', () {
      final hits = _hits(RegExp(r'Transform\s*\.\s*flip'));
      expect(
        hits,
        isEmpty,
        reason: 'Flutter already mirrors a `matchTextDirection` glyph under '
            'RTL. Flipping it again cancels that out and the icon renders '
            'identically in both directions.\n${hits.join('\n')}',
      );
    });
  });

  group('one section header', () {
    test('no feature re-spells the eyebrow style', () {
      // `ink3 / 12 / w600 / 0.6` is `AppTypography.eyebrow`, which
      // `SectionHeader` paints. Five files used to spell it out.
      final offenders = <String>[];
      for (final file in _dartFiles()) {
        if (file.path.endsWith('core/theme/app_typography.dart')) continue;
        final source = file.readAsStringSync();
        final matches = RegExp(
          r'fontSize:\s*12\s*,\s*\n?\s*(//[^\n]*\n\s*)?'
          r'fontWeight:\s*FontWeight\.w600\s*,\s*\n?\s*'
          r'letterSpacing:\s*0\.6',
        ).allMatches(source);
        if (matches.isNotEmpty) offenders.add(file.path);
      }
      expect(
        offenders,
        isEmpty,
        reason: 'This is the section-eyebrow token. Use `SectionHeader` (or '
            '`SectionLabel` inside the settings hub), or '
            '`AppTypography.eyebrow` where a heading is not what is being '
            'drawn.\n${offenders.join('\n')}',
      );
    });
  });

  group('one filter control', () {
    test('no feature grows another private filter pill', () {
      final hits = _hits(
        RegExp(r'class _(Filter|FilterChip|Chip|Chips|Pill)\b'),
        skipFile: (p) =>
            // `_Pill` on the dashboard is a `StatusChip` alias, not a filter,
            // and `_Chip` there is likewise a status affordance. The two
            // exceptions are listed by path so a *new* one still fails.
            p.endsWith(
                'features/home/presentation/widgets/dashboard_cards.dart'),
      );
      expect(
        hits,
        isEmpty,
        reason: 'Dataset filtering is `AppFilterChip` inside an '
            '`AppFilterBar`. The audit counted ten private implementations of '
            'this one control, two of them byte-identical copies, and two '
            'that disagreed about what «selected» looks like (P1-4). A '
            'form value or a status action is not a filter — use a '
            '`ChoiceChip` or a button and name it for what it does.\n'
            '${hits.join('\n')}',
      );
    });
  });

  group('one confirmation', () {
    test('no new bare AlertDialog outside the files that still hold one', () {
      // Phase 1 migrated four representative destructive flows. The rest are
      // listed, so the list can only get shorter: a new file that hand-rolls
      // an `AlertDialog` fails here.
      const known = <String>{
        // Non-confirmation dialogs: a picker, a sign-out prompt, a session
        // notice, an onboarding explainer, an error report.
        'lib/features/shift/presentation/shift_manage_sheet.dart',
        'lib/features/detachment_group/presentation/detachment_group_edit_page.dart',
        'lib/features/settings/presentation/security_page.dart',
        'lib/features/workshop/presentation/widgets/workshop_people.dart',
        'lib/features/conflict/presentation/conflict_resolution_page.dart',
        'lib/features/demo/presentation/demo_trial_bar.dart',
        'lib/features/notification/presentation/notifications_center_page.dart',
        'lib/features/auth/presentation/status_pages.dart',
        'lib/features/auth/presentation/google_sign_in_button.dart',
        'lib/features/auth/presentation/onboarding_ui.dart',
        'lib/features/auth/presentation/sign_out_action.dart',
        'lib/features/detachment/presentation/detachment_edit_page.dart',
        'lib/features/announcement/presentation/announcements_page.dart',
        // The shared implementation itself.
        'lib/core/widgets/confirmation_dialog.dart',
        // Platform dialogs that are not plain confirmations: they carry a
        // reason field, a typed name, a capability picker or the two-step
        // tenant deletion. Each is a form in a dialog, not a yes/no.
        'lib/features/platform/presentation/widgets/platform_confirmation_dialog.dart',
        'lib/features/platform/presentation/platform_break_glass_actions.dart',
        'lib/features/platform/presentation/platform_main_admin_page.dart',
        'lib/features/platform/presentation/platform_main_admin_replace_page.dart',
        'lib/features/platform/presentation/tenant_lifecycle_management_section.dart',
      };
      final hits = _hits(
        'AlertDialog(',
        skipFile: known.contains,
      );
      expect(
        hits,
        isEmpty,
        reason: 'A consequential confirmation is `showAppConfirmation` — it '
            'states the record, what changes and what does not, and puts the '
            'severity on a filled button instead of a coloured `TextButton` '
            'label sitting at the same weight as «إلغاء» (UI audit P1-3). '
            'The allowlist above is the set Phase 1 did not migrate; it is '
            'meant to shrink.\n${hits.join('\n')}',
      );
    });
  });

  group('one measure scale', () {
    test('no screen invents its own content max width', () {
      const known = <String>{
        // The measures themselves.
        'lib/core/widgets/reading_column.dart',
        // Three pre-existing one-off caps the audit did not flag: the
        // floating nav bar's own width (a control, not content), the
        // session-state screens' 520 and the update screen's 420. The last
        // two are `kReadingMaxWidth` and `kDialogMaxWidth` by value and can
        // adopt the tokens whenever those screens are next touched.
        'lib/core/widgets/glass_bottom_nav.dart',
        'lib/core/widgets/status_screen.dart',
        'lib/features/app_version/presentation/upgrade_required_page.dart',
      };
      final hits = _hits(
        RegExp(r'maxWidth:\s*\d'),
        skipFile: known.contains,
      );
      expect(
        hits,
        isEmpty,
        reason: 'Content width comes from the measure scale in '
            '`core/widgets/reading_column.dart`: `kFormMaxWidth` (440) for a '
            'form, `kReadingMaxWidth` (520) for a page of label↔value rows, '
            '`kContentMaxWidth` (720) for a working column. A new literal is '
            'a fourth measure nobody else can match.\n${hits.join('\n')}',
      );
    });
  });

  group('labelled icon actions', () {
    test('every IconButton exposes a tooltip', () {
      final offenders = <String>[];
      final constructor = RegExp(r'\bIconButton(?:\.[A-Za-z]+)?\s*\(');
      for (final file in _dartFiles()) {
        final source = file.readAsStringSync();
        for (final match in constructor.allMatches(source)) {
          final lineStart = source.lastIndexOf('\n', match.start) + 1;
          final line = source.substring(lineStart, match.start).trimLeft();
          if (line.startsWith('//')) continue;
          final call = _balancedCall(source, match.end - 1);
          if (RegExp(r'\btooltip\s*:').hasMatch(call)) continue;
          final lineNumber =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('${file.path}:$lineNumber');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Every icon-only action needs an Arabic tooltip. Flutter '
            'uses it as the accessible name and as the discoverable hover/'
            'long-press label; an icon alone is not a name.\n'
            '${offenders.join('\n')}',
      );
    });
  });

  group('calendar dates', () {
    test('the schedule never moves a date by an absolute Duration', () {
      // `Duration(days: n)` is 24n hours; a local calendar day is 23 or 25
      // across a daylight-saving change, and a shift date that stops being
      // local midnight silently stops matching `s.date == day`.
      final offenders = <String>[];
      for (final file in _dartFiles()) {
        final path = file.path;
        final inSchedule = path.contains('/shift/') ||
            path.contains('/detachment/') ||
            path.endsWith('core/format/app_date.dart');
        if (!inSchedule) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          // `Duration(days: 1)` added to a *timestamp* is legitimate — the
          // overnight check-out normalisation does exactly that — so only a
          // date-shaped receiver is flagged.
          final match = RegExp(
            r'\b(date|day|weekStart|from|to|start|end|firstDay|today)\b'
            r'\s*\.\s*(add|subtract)\s*\(\s*(const\s+)?Duration\(days:',
          ).firstMatch(line);
          if (match != null) offenders.add('$path:${i + 1}  ${line.trim()}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Use `addDays(value, n)` from `core/time/calendar_day.dart`, '
            'and `calendarDaysBetween` to count. See the `copyWeek` bug: two '
            'source days collapsed onto one target day in a week containing a '
            'spring-forward.\n${offenders.join('\n')}',
      );
    });

    test('no screen abbreviates an Arabic weekday by cutting its name', () {
      // Every weekday in `AppDate._weekdays` begins «ال», so a prefix of one
      // is the definite article and nothing else: the schedule's day strip
      // and the repeat picker both drew «ال» in all seven columns until the
      // Phase 3C render review. `AppDate.weekdayInitial` is the distinct
      // one-letter form.
      final hits = _hits(RegExp(r'weekday(Of|Name)\s*\([^)]*\)\s*\.\s*substring'));
      expect(
        hits,
        isEmpty,
        reason: 'Use `AppDate.weekdayInitialOf(day)` — a cut weekday name is '
            '«ال» for all seven days.\n${hits.join('\n')}',
      );
    });
  });
}
