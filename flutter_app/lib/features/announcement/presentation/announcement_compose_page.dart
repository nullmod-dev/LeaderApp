import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_date.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../l10n/strings.dart';
import '../../detachment/domain/detachment_models.dart';
import '../../home/data/home_providers.dart';
import '../data/announcement_providers.dart';
import '../domain/announcement_models.dart';
import '../domain/announcement_selectors.dart';
import 'announcement_copy.dart';

/// Write one announcement and publish it.
///
/// One screen, five controls, no wizard: the notice, who it goes to, where it
/// shows, how long it lasts, publish. That order is the order a person thinks
/// in, and every step after the first has a working default — one detachment is
/// already selected, the Notifications Center is already ticked, a day is
/// already chosen — so the shortest possible publish is *type the text and
/// press the button*.
///
/// What the screen deliberately does **not** ask for: a shift, a member, a
/// stock item, a category, a tag, an image, an attachment. An administrator
/// writing «بخصوص شفت ٤–١٠…» has said everything a second form would have
/// collected, at a fraction of the cost.
class AnnouncementComposePage extends ConsumerStatefulWidget {
  const AnnouncementComposePage({super.key});

  /// A root route: a full-screen form, so it covers the bottom nav like every
  /// other create form in this app.
  static const routePath = '/announcements/new';

  @override
  ConsumerState<AnnouncementComposePage> createState() => _S();
}

class _S extends ConsumerState<AnnouncementComposePage> {
  final _text = TextEditingController();

  /// The chosen detachments, in the order they were added. One by default —
  /// never all of them, and never a wildcard.
  final List<String> _targets = [];

  /// True once the default target has been seeded, so a rebuild (a refresh, a
  /// grant change) never silently re-adds a detachment the author removed.
  bool _seeded = false;

  bool _onHome = false;
  bool _onDetachment = false;

  AnnouncementDuration _duration = AnnouncementDuration.day;
  DateTime? _customExpiry;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The expiry the current choices resolve to, measured from one reading of
  /// the clock so the preset and the validation cannot disagree.
  DateTime _expiryFrom(DateTime now) {
    final span = _duration.span;
    if (span != null) return now.add(span);
    return _customExpiry ?? now.add(const Duration(days: 1));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.announcementCompose)),
      body: SafeArea(
        top: false,
        child: AsyncResultView<List<Detachment>>(
          value: ref.watch(publishableDetachmentsProvider),
          onRetry: () => ref.invalidate(publishableDetachmentsProvider),
          builder: (context, available, stale) {
            // A session that may publish, but has no active detachment to
            // publish into, is a real state and a designed one — not an empty
            // form whose button silently refuses.
            if (available.isEmpty) {
              return const EmptyState(
                key: Key('announcement-no-targets'),
                icon: Icons.flag_outlined,
                title: S.announcementNoTargetsTitle,
                body: S.announcementNoTargetsBody,
              );
            }
            _seedDefaultTarget(available);
            // A grant can narrow while this screen is open. Selections that are
            // no longer publishable are dropped from the list the author sees
            // rather than left there to be refused at submit — and the
            // controller revalidates again anyway, because a form that looks
            // right is not a permission check.
            _dropUnavailable(available);
            return _form(available);
          },
        ),
      ),
    );
  }

  /// One detachment, chosen for the author: the one the dashboard is already
  /// showing when that is publishable, otherwise the first available.
  void _seedDefaultTarget(List<Detachment> available) {
    if (_seeded || available.isEmpty) return;
    _seeded = true;
    final active = ref.read(activeDetachmentProvider).valueOrNull?.when(
          success: (Detachment? data, {bool stale = false}) => data,
          failure: (_, __) => null,
          offline: (cached) => cached,
        );
    final preferred = active != null && available.any((d) => d.id == active.id)
        ? active.id
        : available.first.id;
    _targets.add(preferred);
  }

  void _dropUnavailable(List<Detachment> available) {
    final ids = {for (final d in available) d.id};
    _targets.removeWhere((id) => !ids.contains(id));
  }

  Widget _form(List<Detachment> available) {
    final c = context.c;
    final busy = ref.watch(announcementControllerProvider).publishing;
    final now = ref.watch(clockProvider)();
    final unchosen = [
      for (final d in available)
        if (!_targets.contains(d.id)) d,
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // 1. The notice.
        const _Label(S.announcementText),
        const SizedBox(height: 6),
        TextField(
          key: const Key('announcement-text-field'),
          controller: _text,
          maxLines: 6,
          minLines: 4,
          maxLength: announcementTextMax,
          textInputAction: TextInputAction.newline,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(hintText: S.announcementTextHint),
        ),

        // 2. Who it goes to.
        const SizedBox(height: AppSpacing.md),
        const _Label(S.announcementTargets),
        const SizedBox(height: 6),
        _TargetChips(
          targets: _targets,
          available: available,
          // The last target cannot be removed: at least one is always
          // required, and offering a control that would leave the form invalid
          // is the dead affordance the house rule forbids.
          onRemove: _targets.length <= 1
              ? null
              : (id) => setState(() => _targets.remove(id)),
        ),
        if (unchosen.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('announcement-add-target'),
              onPressed: busy ? null : () => _pickTarget(unchosen),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(S.announcementAddTarget),
            ),
          ),
        ],

        // 3. Where it shows.
        const SizedBox(height: AppSpacing.md),
        const _Label(S.announcementPlacements),
        const SizedBox(height: 6),
        const _PlacementRow(
          key: Key('announcement-placement-notifications'),
          label: S.announcementPlacementNotifications,
          help: S.announcementPlacementNotificationsHelp,
          value: true,
          // Always on, and shown rather than hidden: the author should see that
          // the notice will be findable later, not have to know it.
          onChanged: null,
        ),
        _PlacementRow(
          key: const Key('announcement-placement-home'),
          label: S.announcementPlacementHome,
          help: S.announcementPlacementHomeHelp,
          value: _onHome,
          onChanged: busy ? null : (v) => setState(() => _onHome = v),
        ),
        _PlacementRow(
          key: const Key('announcement-placement-detachment'),
          label: S.announcementPlacementDetachment,
          help: S.announcementPlacementDetachmentHelp,
          value: _onDetachment,
          onChanged: busy ? null : (v) => setState(() => _onDetachment = v),
        ),

        // 4. How long it lasts. Always finite.
        const SizedBox(height: AppSpacing.md),
        const _Label(S.announcementDuration),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in AnnouncementDuration.values)
              ChoiceChip(
                key: Key('announcement-duration-${option.name}'),
                label: Text(announcementDurationLabel(option)),
                selected: _duration == option,
                onSelected: busy ? null : (_) => _pickDuration(option, now),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          announcementEndsLabelFor(_expiryFrom(now)),
          key: const Key('announcement-expiry-preview'),
          style: TextStyle(color: c.ink3, fontSize: 12),
        ),

        // 5. Publish.
        const SizedBox(height: AppSpacing.xxl),
        FilledButton(
          key: const Key('announcement-publish'),
          onPressed: busy ? null : _publish,
          child: const Text(S.announcementPublish),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: busy ? null : () => context.pop(),
          child: const Text(S.cancel),
        ),
      ],
    );
  }

  Future<void> _pickTarget(List<Detachment> unchosen) async {
    final chosen = await showAppSheet<String>(
      context: context,
      title: S.announcementPickTarget,
      // A Builder so the rows pop the *sheet* rather than this page — the same
      // trap the dashboard's detachment switcher documents.
      child: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in unchosen)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: Key('announcement-target-option-${d.id}'),
                  onTap: () => Navigator.of(sheetContext).pop(d.id),
                  leading: Icon(Icons.flag_outlined,
                      size: 20, color: sheetContext.c.ink3),
                  title: Text(d.name),
                  subtitle: Text(d.region),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    // Guarded rather than trusted: the sheet only offers unchosen rows, but a
    // duplicate target is the one thing this list must never hold.
    if (_targets.contains(chosen)) return;
    setState(() => _targets.add(chosen));
  }

  Future<void> _pickDuration(AnnouncementDuration option, DateTime now) async {
    if (option != AnnouncementDuration.custom) {
      setState(() {
        _duration = option;
        _customExpiry = null;
      });
      return;
    }

    final day = await showDatePicker(
      context: context,
      initialDate: _customExpiry ?? now.add(const Duration(days: 1)),
      // Today is the earliest a custom expiry can be, and the time picker
      // below still has to land in the future — the controller refuses an
      // expiry that is not, whatever the pickers allowed.
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (!mounted) return;
    final at = DateTime(
      day.year,
      day.month,
      day.day,
      time?.hour ?? now.hour,
      time?.minute ?? now.minute,
    );
    setState(() {
      _duration = AnnouncementDuration.custom;
      _customExpiry = at;
    });
  }

  Future<void> _publish() async {
    final now = ref.read(clockProvider)();
    final outcome =
        await ref.read(announcementControllerProvider.notifier).publish(
              text: _text.text,
              detachmentIds: _targets,
              placements: resolvePlacements(
                onHome: _onHome,
                onDetachment: _onDetachment,
              ),
              expiresAt: _expiryFrom(now),
            );
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case AnnouncementSaved():
        messenger.showSnackBar(
          const SnackBar(content: Text(S.announcementPublished)),
        );
        context.pop();
      case AnnouncementRefusedOutcome(:final reason):
        // Everything the author typed stays exactly where it is. A refused
        // publish that also emptied the form would be the second failure.
        messenger.showSnackBar(
          SnackBar(content: Text(announcementRefusalMessage(reason))),
        );
      case AnnouncementFailed(:final message):
        messenger.showSnackBar(SnackBar(content: Text(message)));
      case AnnouncementOffline():
        messenger.showSnackBar(
          const SnackBar(content: Text(S.announcementNeedsConnection)),
        );
      case AnnouncementIgnored():
        // A second tap while the first is in flight. Nothing was sent and
        // nothing is said — the button is already showing it is busy.
        break;
    }
  }
}

/// The expiry line under the duration chips, from a resolved instant.
String announcementEndsLabelFor(DateTime expiresAt) =>
    S.announcementEndsAt.replaceFirst('%s', AppDate.dayMonthTime(expiresAt));

class _TargetChips extends StatelessWidget {
  const _TargetChips({
    required this.targets,
    required this.available,
    required this.onRemove,
  });

  final List<String> targets;
  final List<Detachment> available;
  final void Function(String id)? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final id in targets)
          InputChip(
            key: Key('announcement-target-$id'),
            label: Text(_nameOf(id)),
            avatar: Icon(Icons.flag_outlined, size: 16, color: c.ink3),
            onDeleted: onRemove == null ? null : () => onRemove!(id),
            deleteButtonTooltipMessage: S.announcementRemoveTarget,
          ),
      ],
    );
  }

  String _nameOf(String id) {
    for (final d in available) {
      if (d.id == id) return d.name;
    }
    return id;
  }
}

/// One placement, with the sentence that says what choosing it actually does.
///
/// The help line is not decoration: "الرئيسية" alone does not tell a beginner
/// that the promotion lasts an hour, and an administrator who expected a notice
/// to sit on the dashboard all day would think the app had lost it.
class _PlacementRow extends StatelessWidget {
  const _PlacementRow({
    super.key,
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String help;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: c.ink, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(help,
                      style:
                          TextStyle(color: c.ink3, fontSize: 12, height: 1.45)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(color: context.c.ink2, fontSize: 13),
      );
}
