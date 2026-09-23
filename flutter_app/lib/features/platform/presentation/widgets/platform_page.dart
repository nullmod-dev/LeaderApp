import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/reading_column.dart';
import '../../../../core/widgets/refresh_indicator.dart';
import '../../../../core/widgets/shell_insets.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import '../../domain/platform_area.dart';

/// The layout every platform page shares: one header, one constrained reading
/// column, one scroll.
///
/// **Why a primitive and not four hand-built Scaffolds.** The platform surface
/// has four top-level areas and will gain more detail in later Points. What must not
/// drift between them is the part a user navigates by — where the title sits,
/// how wide the content runs on a tablet, how much room the shell's navigation
/// gets, and the fact that the header never grows a counter nobody can act on.
/// Stating it once is how that holds.

/// How wide the reading column is allowed to run.
///
/// A control plane read on a tablet should not become a line of text 900 px
/// long, and the answer to a wide window is to *reflow*, never to stretch a
/// phone card across it (`§12`, `§14`). 720 is the width at which the app's
/// body size still gives a comfortable measure.
///
/// The number now lives in `core/widgets/reading_column.dart` as one stop on
/// the app's measure scale — the tenant surface gained the same idea in
/// Phase 1 of the UI quality programme, and one number is how the two
/// surfaces stay one product. This name is kept because the platform code
/// reads by it.
const double kPlatformContentMaxWidth = kContentMaxWidth;

/// The one platform header.
///
/// A concise title and one action: the account. There is deliberately no
/// search field and no alerts bell — neither has a destination on this surface
/// in this build, and a header icon that opens nothing is the exact defect
/// `§22` names. Both slots are trivially added once a Point gives them
/// somewhere to go.
class PlatformAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const PlatformAppBar({super.key, required this.title, this.actions});

  final String title;

  /// A page's own contextual action, before the account entry. Empty today.
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      title: Text(
        title,
        // `titleMedium`, not the app-bar default. A calmer header is the point
        // (`§21` — no hero typography on a working surface), and at 16 sp the
        // longest platform title still fits beside the account action on a
        // 320 dp phone at a 1.6 text scale without being abbreviated.
        style: Theme.of(context).textTheme.titleMedium,
      ),
      actions: [
        ...?actions,
        IconButton(
          tooltip: S.platformAccountAction,
          // A glyph, not initials: an avatar with a letter in it would have to
          // resist the text scale to stay circular, and the account's real
          // identity is one tap away on the screen this opens.
          icon: const Icon(Icons.account_circle_outlined),
          // `go`, not `push`: the account lives in the More branch, so this
          // moves the shell there rather than stacking a copy of it on top of
          // whichever branch the operator happened to be in.
          onPressed: () => context.go('${PlatformArea.more.route}/profile'),
        ),
      ],
    );
  }
}

/// A platform page: header, constrained column, scrolling body.
///
/// [children] are the column's slivers-free children, in reading order. The
/// page owns the scroll so a section never nests one inside another.
class PlatformPage extends StatelessWidget {
  const PlatformPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.onRefresh,
    this.floatingActionButton,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;

  /// A page's one primary action, docked above the shell's navigation.
  ///
  /// Offered because a *working* platform screen has one — the subscriber list
  /// has to make "register a customer" unmissable — and a scrolling button
  /// would be missable on the one screen where the operator arrives to do
  /// exactly that. Still at most one per page: this is not a place for a
  /// second, and no page that has nothing to do passes one.
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: PlatformAppBar(title: title, actions: actions),
      floatingActionButton: floatingActionButton,
      // The shared measure primitive, at the platform stop: top-aligned so a
      // short page sits under its header, centred so a wide window gains
      // margins instead of a stretched card.
      body: ReadingColumn(
        maxWidth: kPlatformContentMaxWidth,
        // The shell says how much room its navigation needs — 0 for the
        // docked bar, which `Scaffold` has already made room for.
        child: FloatingNavPadding(
          child: Builder(builder: (context) {
            final list = ListView(
              physics: onRefresh == null
                  ? null
                  : const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: children,
            );
            return onRefresh == null
                ? list
                : AppRefreshIndicator(onRefresh: onRefresh!, child: list);
          }),
        ),
      ),
    );
  }
}

/// The one line a platform page opens with.
///
/// **Not a hero, and not the title again.** This used to be a 52 dp tinted
/// tile, the page's heading and a lead paragraph — roughly 270 px of chrome on
/// top of an app bar that had already named the page, so on a 390 × 844 phone
/// the Overview's «يحتاج إلى انتباه» landed at the fold and the operator
/// scrolled to reach the reason they opened the screen (UI audit P1-6, and
/// the "page title stated twice" P2 that ran across the whole surface).
///
/// The app bar states the page. The body states what the page is *for*, in one
/// sentence, and then gets out of the way. A working control plane earns its
/// first viewport for data.
class PlatformPageIntro extends StatelessWidget {
  const PlatformPageIntro({super.key, required this.lead, this.badge});

  /// One sentence. If it needs two, the second one belongs in the section it
  /// describes.
  final String lead;

  /// A short state word for an area whose module is not complete — «قيد
  /// الإعداد». Never a number: a count in a page header is a fact nobody can
  /// act on from there.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = Text(
      lead,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: c.ink3, height: 1.55),
    );
    if (badge == null) return text;
    // The badge above the lead rather than beside it: at a 1.6 text scale a
    // chip sharing the line squeezes the sentence into a column two words
    // wide.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip(kind: StatusKind.muted, label: badge!),
        const SizedBox(height: AppSpacing.sm),
        text,
      ],
    );
  }
}

/// A grouped block of related lines on a platform page.
///
/// The same grouped-card idiom the settings hub uses, so the two surfaces a
/// Super Admin moves between do not have two ideas of what a group looks like.
/// [title] is the small label above it; the card itself carries no icon per
/// row and no chevron, because nothing inside one of these is navigable.
class PlatformNoteCard extends StatelessWidget {
  const PlatformNoteCard({
    super.key,
    required this.title,
    required this.body,
    this.lines = const [],
    this.linesLabel,
  });

  final String title;
  final String body;

  /// Plain, non-interactive items — what an area *will* hold. Rendered as text
  /// with a dot, never as rows that look tappable: a row shaped like a control
  /// that does nothing is worse than a sentence (`§25`).
  final List<String> lines;

  final String? linesLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: t.bodySmall?.copyWith(color: c.ink3, height: 1.6),
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            if (linesLabel != null) ...[
              Text(
                linesLabel!,
                style: AppTypography.eyebrow(c),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      // Nudged down to sit on the first line's baseline at any
                      // text scale rather than at the top of a wrapped block.
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: c.ink3,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(
                          color: c.ink2,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
