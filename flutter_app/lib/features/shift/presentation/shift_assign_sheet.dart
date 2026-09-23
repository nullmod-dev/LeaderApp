import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/format/app_number.dart';
import '../../../core/format/app_time.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/lock_window.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/domain/auth_models.dart';
import '../../team/data/team_providers.dart';
import '../../team/domain/team_models.dart';
import '../data/shift_providers.dart';
import '../domain/attendance_correction.dart';
import '../domain/attendance_policy.dart';
import '../domain/shift_models.dart';

/// Who to put on a shift.
///
/// Members already working an overlapping shift are **shown, not hidden**,
/// greyed with the shift they clash with. Hiding them makes the list look
/// broken to whoever is looking for a name they know is on the roster; naming
/// the clash answers the question the omission would raise.
Future<void> showAssignSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Shift shift,
}) async {
  await showAppSheet<void>(
    context: context,
    title: '${S.assignSheetTitle}، ${AppTime.minuteRange(
      shift.startMinutes,
      shift.endMinutes,
    )}',
    expanded: true,
    child: _AssignBody(shift: shift),
  );
}

class _AssignBody extends ConsumerStatefulWidget {
  const _AssignBody({required this.shift});

  final Shift shift;

  @override
  ConsumerState<_AssignBody> createState() => _AssignBodyState();
}

class _AssignBodyState extends ConsumerState<_AssignBody> {
  final _search = TextEditingController();
  final _manualName = TextEditingController();
  late final Set<String> _selectedIds;
  late final Map<String, TeamMember> _selectedMembers;
  final Set<String> _busyIds = {};
  bool _manualBusy = false;
  String? _message;
  String? _duplicateId;

  Shift get shift => widget.shift;

  @override
  void initState() {
    super.initState();
    _selectedIds = shift.attendees.map((member) => member.id).toSet();
    _selectedMembers = {
      for (final member in shift.attendees) member.id: member
    };
    _search.addListener(_refresh);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_refresh)
      ..dispose();
    _manualName.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AsyncResultView<List<ShiftCandidate>>(
      value: ref.watch(shiftCandidatesProvider(shift.id)),
      onRetry: () => ref.invalidate(shiftCandidatesProvider),
      loading: const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      builder: (context, candidates, stale) {
        final free = candidates.where((x) => !x.busy).length;
        final query = memberNameKey(_search.text);
        final filtered = candidates
            .where((candidate) =>
                query.isEmpty ||
                memberNameKey(candidate.member.name).contains(query))
            .toList()
          ..sort((a, b) {
            if (a.member.id == _duplicateId) return -1;
            if (b.member.id == _duplicateId) return 1;
            if (a.busy != b.busy) return a.busy ? 1 : -1;
            return a.member.name.compareTo(b.member.name);
          });
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(children: [
                TextField(
                  key: const Key('member-search-field'),
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: S.searchMembers,
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  Expanded(
                    child: TextField(
                      key: const Key('manual-member-name'),
                      controller: _manualName,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _createAndAssign(context, ref),
                      decoration: const InputDecoration(
                        hintText: S.manualMemberName,
                        prefixIcon: Icon(Icons.person_add_alt_1_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 120,
                    child: FilledButton(
                      key: const Key('manual-member-add'),
                      onPressed: _manualBusy
                          ? null
                          : () => _createAndAssign(context, ref),
                      child: _manualBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(S.addAndAssign),
                    ),
                  ),
                ]),
                if (_message != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _message!,
                      key: const Key('member-assignment-message'),
                      style: TextStyle(
                        color: _duplicateId == null ? c.ok : c.warn,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ]),
            ),
            DragTarget<ShiftCandidate>(
              onWillAcceptWithDetails: (details) => !details.data.busy,
              onAcceptWithDetails: (details) =>
                  _assign(context, ref, details.data),
              builder: (context, incoming, rejected) => Container(
                key: const Key('selected-member-drop-zone'),
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: incoming.isNotEmpty ? c.primaryTint : c.surface2,
                  border: Border.all(
                    color: incoming.isNotEmpty ? c.primary : c.line,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.group_rounded, size: 17, color: c.primary),
                      const SizedBox(width: 6),
                      Text(
                        '${S.selectedMembers} '
                        '${AppNumber.count(_selectedIds.length)}',
                        style: TextStyle(
                          color: c.ink2,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.sm),
                    if (_selectedMembers.isEmpty)
                      Text(
                        S.dragMembersHere,
                        style: TextStyle(color: c.ink3, fontSize: 12),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final member in _selectedMembers.values)
                            Chip(
                              avatar: const Icon(Icons.check_rounded, size: 16),
                              label: Text(member.name),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(children: [
                Text(S.unselectedMembers,
                    style: TextStyle(color: c.ink2, fontSize: 12)),
                const Spacer(),
                Text('${S.availableNow} ${AppNumber.count(free)}',
                    style: TextStyle(color: c.ink3, fontSize: 12)),
              ]),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: filtered.isEmpty ? 1 : filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        candidates.isEmpty
                            ? S.allMembersAssigned
                            : S.noMatchingMembers,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final candidate = filtered[i];
                  final row = _CandidateRow(
                    candidate: candidate,
                    busy: _busyIds.contains(candidate.member.id),
                    onPick: () => _assign(context, ref, candidate),
                  );
                  if (candidate.busy) return row;
                  return LongPressDraggable<ShiftCandidate>(
                    data: candidate,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(width: 320, child: row),
                    ),
                    childWhenDragging: Opacity(opacity: .35, child: row),
                    child: row,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _assign(
      BuildContext context, WidgetRef ref, ShiftCandidate candidate) async {
    if (candidate.busy || _busyIds.contains(candidate.member.id)) return;
    setState(() {
      _busyIds.add(candidate.member.id);
      _message = null;
    });
    final result = await ref
        .read(shiftRepositoryProvider)
        .assignVolunteer(shift.id, candidate.member.id);
    if (!context.mounted) return;
    result.when(
      // The sheet stays open on success: staffing a shift means adding
      // several people, and closing after each one turns one task into four.
      success: (_, {stale = false}) => setState(() {
        _selectedIds.add(candidate.member.id);
        _selectedMembers[candidate.member.id] = candidate.member;
        _message = S.memberAssigned;
        _duplicateId = null;
      }),
      failure: (message, _) => setState(() => _message = message),
      offline: (_) => setState(() => _message = S.offlineTitle),
    );
    setState(() => _busyIds.remove(candidate.member.id));
    _invalidate(ref);
  }

  Future<void> _createAndAssign(BuildContext context, WidgetRef ref) async {
    if (_manualBusy) return;
    final name = normalizeMemberName(_manualName.text);
    if (name.isEmpty) {
      setState(() => _message = S.required);
      return;
    }
    setState(() {
      _manualBusy = true;
      _message = null;
      _duplicateId = null;
    });
    final directory = ref.read(teamRepositoryProvider);
    final match = await directory.findNameMatch(shift.detachmentId, name);
    if (!mounted) return;
    TeamMember? existing;
    String? lookupError;
    match.when(
      success: (data, {stale = false}) => existing = data,
      failure: (message, _) => lookupError = message,
      offline: (_) => lookupError = S.offlineTitle,
    );
    if (lookupError != null) {
      setState(() {
        _manualBusy = false;
        _message = lookupError;
      });
      return;
    }
    if (existing != null) {
      _search.text = existing!.name;
      setState(() {
        _manualBusy = false;
        _duplicateId = existing!.id;
        _message = S.duplicateMemberName;
      });
      return;
    }

    final created = await directory.createFromShift(
      detachmentId: shift.detachmentId,
      name: name,
    );
    if (!mounted) return;
    TeamMember? member;
    String? createError;
    created.when(
      success: (data, {stale = false}) => member = data,
      failure: (message, _) => createError = message,
      offline: (_) => createError = S.offlineTitle,
    );
    if (member == null) {
      setState(() {
        _manualBusy = false;
        _message = createError;
      });
      return;
    }
    final assigned = await ref
        .read(shiftRepositoryProvider)
        .assignVolunteer(shift.id, member!.id);
    if (!mounted) return;
    assigned.when(
      success: (_, {stale = false}) => setState(() {
        _selectedIds.add(member!.id);
        _selectedMembers[member!.id] = member!;
        _manualName.clear();
        _message = S.memberCreatedAndAssigned;
      }),
      failure: (message, _) => setState(() => _message = message),
      offline: (_) => setState(() => _message = S.offlineTitle),
    );
    setState(() => _manualBusy = false);
    ref.invalidate(teamListProvider(shift.detachmentId));
    _invalidate(ref);
  }

  void _invalidate(WidgetRef ref) {
    ref.invalidate(weekShiftsProvider);
    ref.invalidate(todaysShiftsProvider);
    ref.invalidate(shiftByIdProvider(shift.id));
    ref.invalidate(shiftCandidatesProvider(shift.id));
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.onPick,
    this.busy = false,
  });

  final ShiftCandidate candidate;
  final VoidCallback onPick;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = candidate.member;
    final disabled = candidate.busy || busy;
    return PressScale(
      onTap: onPick,
      enabled: !disabled,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Opacity(
        opacity: disabled ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: c.mutedTint, shape: BoxShape.circle),
              child: Text(m.initials,
                  style: TextStyle(
                      color: c.ink2,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name,
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    candidate.busy
                        ? '${S.busyNow} '
                            '${candidate.busyWith == null ? '' : AppTime.minuteRange(candidate.busyWith!.startMinutes, candidate.busyWith!.endMinutes)}'
                        : _roleLabel(m.role),
                    style: TextStyle(
                      color: candidate.busy ? c.warn : c.ink3,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(candidate.busy ? Icons.block_rounded : Icons.add_rounded,
                  color: candidate.busy ? c.ink3 : c.primary),
          ]),
        ),
      ),
    );
  }

  static String _roleLabel(TeamRole role) => switch (role) {
        TeamRole.shiftSupervisor => S.roleShiftSupervisor,
        TeamRole.administrator => S.roleAdministrator,
        TeamRole.followUp => S.roleFollowUp,
        TeamRole.member => S.roleMember,
      };
}

/// Attendance for one person on one shift, plus the way off the shift.
Future<void> showAttendanceSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Shift shift,
  required TeamMember member,
  required bool canUnassign,
}) async {
  await showAppSheet<void>(
    context: context,
    title: '${S.attendanceSheetTitle} · ${member.name}',
    child: _AttendanceBody(
      shift: shift,
      member: member,
      canUnassign: canUnassign,
    ),
  );
}

class _AttendanceBody extends ConsumerStatefulWidget {
  const _AttendanceBody({
    required this.shift,
    required this.member,
    required this.canUnassign,
  });

  final Shift shift;
  final TeamMember member;
  final bool canUnassign;

  @override
  ConsumerState<_AttendanceBody> createState() => _AttendanceBodyState();
}

class _AttendanceBodyState extends ConsumerState<_AttendanceBody> {
  late DateTime _checkInAt;
  late DateTime _checkOutAt;
  bool _busy = false;
  String? _error;

  // Correction form state — only used once the ordinary window has closed
  // and the session holds `Cap.shiftAttendanceOverride`.
  bool _correcting = false;
  late AttendanceState _correctionStatus;
  DateTime? _correctionCheckInAt;
  DateTime? _correctionCheckOutAt;
  final _reasonController = TextEditingController();
  bool _correctionBusy = false;
  String? _correctionError;

  // The shift as last returned by a successful correction from this very
  // sheet, so the history list and the current-attendance line update the
  // moment a correction is saved — without watching a provider (and its
  // mock latency) just to redraw two lines this widget already has the data
  // for. Falls back to `widget.shift` until the first correction is saved.
  Shift? _correctedShift;

  Shift get shift => widget.shift;
  TeamMember get member => widget.member;
  Shift get _effectiveShift => _correctedShift ?? widget.shift;
  TeamMember get _effectiveMember => _effectiveShift.attendees.firstWhere(
        (a) => a.id == widget.member.id,
        orElse: () => widget.member,
      );

  static const _options = [
    (AttendanceState.checkedIn, S.checkedIn, Icons.login_rounded),
    (AttendanceState.checkedOut, S.checkedOut, Icons.logout_rounded),
    (AttendanceState.absent, S.absent, Icons.cancel_rounded),
    (AttendanceState.notCheckedIn, S.notCheckedIn, Icons.remove_circle_outline),
  ];

  @override
  void initState() {
    super.initState();
    final defaults = ref.read(attendanceEntryDefaultsProvider(shift.id));
    _checkInAt = member.checkInAt ?? defaults.checkInAt ?? shift.start;
    _checkOutAt = member.checkOutAt ?? defaults.checkOutAt ?? shift.end;
    _correctionStatus = member.attendance;
    _correctionCheckInAt = member.checkInAt;
    _correctionCheckOutAt = member.checkOutAt;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final liveShift = _effectiveShift;
    final liveMember = _effectiveMember;

    final now = DateTime.now();
    final window = AttendanceWindow.of(shift, now: now);
    final caps = ref.watch(capabilitiesProvider);
    final canRecord = caps.canIn(shift.detachmentId, Cap.shiftAttendanceRecord);
    final canOverride =
        caps.canIn(shift.detachmentId, Cap.shiftAttendanceOverride);
    final mode = resolveAttendanceEditMode(
      window: window,
      canRecord: canRecord,
      canOverride: canOverride,
    );
    final corrections = liveShift.correctionsFor(widget.member.id);
    final lockState = switch (mode) {
      AttendanceEditMode.ordinary => LockWindowState.open,
      AttendanceEditMode.correctionOnly => LockWindowState.sealed,
      AttendanceEditMode.readOnly => LockWindowState.restricted,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: LockWindow(
            state: lockState,
            remaining: mode == AttendanceEditMode.ordinary
                ? window.remaining(now)
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (mode != AttendanceEditMode.ordinary) ...[
          Row(children: [
            Text('${S.memberStatusCurrent}: ',
                style: TextStyle(color: c.ink3, fontSize: 12)),
            StatusChip(
              kind: _statusKind(liveMember.attendance),
              label: _statusLabel(liveMember.attendance),
            ),
          ]),
          if (liveMember.checkInAt != null ||
              liveMember.checkOutAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.xs, children: [
              _TimeLabel(
                  label: S.checkInTime, at: liveMember.checkInAt, color: c.ok),
              _TimeLabel(
                  label: S.checkOutTime,
                  at: liveMember.checkOutAt,
                  color: c.info),
            ]),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
        if (mode == AttendanceEditMode.ordinary) ...[
          _DateTimeAction(
            label: member.checkInAt == null ? S.checkInDateTime : S.editCheckIn,
            value: AppTime.dayTime(_checkInAt),
            icon: Icons.login_rounded,
            onTap: _busy ? null : () => _pickDateTime(isCheckIn: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DateTimeAction(
            label:
                member.checkOutAt == null ? S.checkOutDateTime : S.editCheckOut,
            value: AppTime.dayTime(_checkOutAt),
            icon: Icons.logout_rounded,
            onTap: _busy ? null : () => _pickDateTime(isCheckIn: false),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child:
                  Text(_error!, style: TextStyle(color: c.crit, fontSize: 12)),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          for (final (state, label, icon) in _options) ...[
            _Option(
              label: label,
              icon: icon,
              selected: state == member.attendance,
              onTap: _busy ? null : () => _mark(context, ref, state),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.canUnassign) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _unassign(context, ref),
                icon:
                    Icon(Icons.person_remove_outlined, size: 18, color: c.crit),
                label: Text(S.removeFromShift, style: TextStyle(color: c.crit)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.crit.withValues(alpha: 0.5))),
              ),
            ),
          ],
        ] else if (mode == AttendanceEditMode.correctionOnly) ...[
          if (!_correcting)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _correcting = true),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text(S.addCorrection),
              ),
            )
          else
            _CorrectionForm(
              options: _options,
              status: _correctionStatus,
              checkInAt: _correctionCheckInAt ?? shift.start,
              checkOutAt: _correctionCheckOutAt ?? shift.end,
              reasonController: _reasonController,
              busy: _correctionBusy,
              error: _correctionError,
              onStatusChanged: (state) =>
                  setState(() => _correctionStatus = state),
              onPickCheckIn: () => _pickCorrectionDateTime(isCheckIn: true),
              onPickCheckOut: () => _pickCorrectionDateTime(isCheckIn: false),
              onCancel: () => setState(() => _correcting = false),
              onSave: () => _submitCorrection(context, ref),
            ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.mutedTint,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 18, color: c.ink2),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(S.attendanceWindowClosedOrdinary,
                    style: TextStyle(color: c.ink2, fontSize: 12)),
              ),
            ]),
          ),
        ],
        if (corrections.isNotEmpty || mode != AttendanceEditMode.ordinary) ...[
          Padding(
            padding: const EdgeInsets.only(
                top: AppSpacing.md, bottom: AppSpacing.sm),
            child: Row(children: [
              Icon(Icons.fact_check_outlined, size: 16, color: c.ink3),
              const SizedBox(width: 6),
              Text(S.correctionHistoryTitle,
                  style: TextStyle(
                      color: c.ink2,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          if (corrections.isEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(S.noCorrectionsYet,
                  style: TextStyle(color: c.ink3, fontSize: 12)),
            )
          else
            // Newest first — the reason someone opens this section is almost
            // always "what was the last change", not "what was the first".
            for (final correction in corrections.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CorrectionEntry(correction: correction),
              ),
        ],
        const SizedBox(height: AppSpacing.sm),
      ]),
    );
  }

  Future<void> _pickCorrectionDateTime({required bool isCheckIn}) async {
    final current =
        (isCheckIn ? _correctionCheckInAt : _correctionCheckOutAt) ??
            (isCheckIn ? shift.start : shift.end);
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      // Calendar days: a picker's bounds are dates, and a 24-hour Duration
      // lands an hour off across a daylight-saving change.
      firstDate: addDays(shift.date, -1),
      lastDate: addDays(shift.end, 1),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final value =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isCheckIn) {
        _correctionCheckInAt = value;
      } else {
        _correctionCheckOutAt = value;
      }
    });
  }

  Future<void> _submitCorrection(BuildContext context, WidgetRef ref) async {
    if (_correctionBusy) return;
    if (_correctionStatus == AttendanceState.checkedOut &&
        _correctionCheckInAt == null) {
      setState(() => _correctionError = S.checkoutRequiresCheckin);
      return;
    }
    final reason = normalizeCorrectionReason(_reasonController.text);
    if (reason == null) {
      setState(() => _correctionError = S.correctionReasonRequired);
      return;
    }
    setState(() {
      _correctionBusy = true;
      _correctionError = null;
    });
    // Awaited rather than a synchronous `.valueOrNull` read: nothing else in
    // this sheet watches `currentUserProvider`, so on a fast cold start it
    // may still be resolving the first time a correction is saved — this
    // waits for that instead of misreporting it as offline.
    AuthUser? author;
    try {
      author = await ref.read(currentUserProvider.future);
    } catch (_) {
      author = null;
    }
    if (!mounted) return;
    if (author == null) {
      setState(() {
        _correctionBusy = false;
        _correctionError = S.offlineTitle;
      });
      return;
    }

    final clearedStatus = _correctionStatus == AttendanceState.absent ||
        _correctionStatus == AttendanceState.notCheckedIn;
    final result =
        await ref.read(shiftRepositoryProvider).addAttendanceCorrection(
              shiftId: widget.shift.id,
              memberId: widget.member.id,
              status: _correctionStatus,
              checkInAt: clearedStatus ? null : _correctionCheckInAt,
              checkOutAt: _correctionStatus == AttendanceState.checkedOut
                  ? _correctionCheckOutAt
                  : null,
              reason: reason,
              author: AttendanceCorrectionAuthor(
                id: author.id,
                displayName: author.name,
              ),
              correctedAt: DateTime.now(),
            );
    if (!mounted) return;
    Shift? updated;
    result.when(
      success: (s, {stale = false}) => updated = s,
      failure: (message, _) => _correctionError = message,
      offline: (_) => _correctionError = S.offlineTitle,
    );
    // Other screens (the manage sheet, statistics, member history) refresh
    // through these; this sheet already has the fresh shift from `result`
    // above and does not need to re-fetch it.
    ref.invalidate(weekShiftsProvider);
    ref.invalidate(todaysShiftsProvider);
    ref.invalidate(shiftByIdProvider(widget.shift.id));
    ref.invalidate(attendanceStatisticsProvider);
    setState(() {
      _correctionBusy = false;
      if (updated != null) {
        _correctedShift = updated;
        _correcting = false;
        _reasonController.clear();
      }
    });
  }

  Future<void> _pickDateTime({required bool isCheckIn}) async {
    final current = isCheckIn ? _checkInAt : _checkOutAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      // Calendar days: a picker's bounds are dates, and a 24-hour Duration
      // lands an hour off across a daylight-saving change.
      firstDate: addDays(shift.date, -1),
      lastDate: addDays(shift.end, 1),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final value =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isCheckIn) {
        _checkInAt = value;
      } else {
        _checkOutAt = value;
      }
      _error = null;
    });
  }

  Future<void> _mark(
      BuildContext context, WidgetRef ref, AttendanceState state) async {
    if (_busy) return;
    if (state == AttendanceState.checkedOut && member.checkInAt == null) {
      setState(() => _error = S.checkoutRequiresCheckin);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(shiftRepositoryProvider);
    final result = switch (state) {
      AttendanceState.checkedIn =>
        await repository.recordCheckIn(shift.id, member.id, _checkInAt),
      AttendanceState.checkedOut =>
        await repository.recordCheckOut(shift.id, member.id, _checkOutAt),
      AttendanceState.absent =>
        await repository.markAbsent(shift.id, member.id),
      AttendanceState.notCheckedIn =>
        await repository.resetAttendance(shift.id, member.id),
    };
    if (!mounted) return;
    var saved = false;
    result.when(
      success: (_, {stale = false}) {
        saved = true;
        if (state == AttendanceState.checkedIn) {
          ref.read(attendanceEntryDefaultsProvider(shift.id).notifier).state =
              ref
                  .read(attendanceEntryDefaultsProvider(shift.id))
                  .copyWith(checkInAt: _checkInAt);
        } else if (state == AttendanceState.checkedOut) {
          ref.read(attendanceEntryDefaultsProvider(shift.id).notifier).state =
              ref
                  .read(attendanceEntryDefaultsProvider(shift.id))
                  .copyWith(checkOutAt: _checkOutAt);
        }
      },
      failure: (message, _) => _error = message,
      offline: (_) => _error = S.offlineTitle,
    );
    ref.invalidate(weekShiftsProvider);
    ref.invalidate(todaysShiftsProvider);
    ref.invalidate(shiftByIdProvider(shift.id));
    ref.invalidate(attendanceStatisticsProvider);
    if (saved && context.mounted) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _unassign(BuildContext context, WidgetRef ref) async {
    await ref
        .read(shiftRepositoryProvider)
        .unassignVolunteer(shift.id, member.id);
    ref.invalidate(weekShiftsProvider);
    ref.invalidate(todaysShiftsProvider);
    ref.invalidate(shiftCandidatesProvider);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _DateTimeAction extends StatelessWidget {
  const _DateTimeAction({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      enabled: onTap != null,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(children: [
          Icon(icon, color: c.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: c.ink3, fontSize: 11)),
                const SizedBox(height: 2),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child:
                      Text(value, style: TextStyle(color: c.ink, fontSize: 13)),
                ),
              ],
            ),
          ),
          Icon(Icons.edit_calendar_rounded, color: c.ink3, size: 18),
        ]),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      enabled: onTap != null,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : c.surface,
          border: Border.all(color: selected ? c.primary : c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? c.primary : c.ink2),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: selected ? c.primary : c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ),
          if (selected) Icon(Icons.check_rounded, color: c.primary),
        ]),
      ),
    );
  }
}

/// The inline form behind "إضافة تصحيح": pick the corrected state and time,
/// give a reason, save. It never mutates the original entry — see
/// `MockShiftRepository.addAttendanceCorrection` — so there is no destructive
/// confirmation here, only the required-reason guard.
class _CorrectionForm extends StatelessWidget {
  const _CorrectionForm({
    required this.options,
    required this.status,
    required this.checkInAt,
    required this.checkOutAt,
    required this.reasonController,
    required this.busy,
    required this.error,
    required this.onStatusChanged,
    required this.onPickCheckIn,
    required this.onPickCheckOut,
    required this.onCancel,
    required this.onSave,
  });

  final List<(AttendanceState, String, IconData)> options;
  final AttendanceState status;
  final DateTime checkInAt;
  final DateTime checkOutAt;
  final TextEditingController reasonController;
  final bool busy;
  final String? error;
  final ValueChanged<AttendanceState> onStatusChanged;
  final VoidCallback onPickCheckIn;
  final VoidCallback onPickCheckOut;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.addCorrection,
            style: TextStyle(
                color: c.ink, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        for (final (state, label, icon) in options) ...[
          _Option(
            label: label,
            icon: icon,
            selected: state == status,
            onTap: busy ? null : () => onStatusChanged(state),
          ),
          const SizedBox(height: 8),
        ],
        _DateTimeAction(
          label: S.checkInDateTime,
          value: AppTime.dayTime(checkInAt),
          icon: Icons.login_rounded,
          onTap: busy ? null : onPickCheckIn,
        ),
        const SizedBox(height: AppSpacing.sm),
        _DateTimeAction(
          label: S.checkOutDateTime,
          value: AppTime.dayTime(checkOutAt),
          icon: Icons.logout_rounded,
          onTap: busy ? null : onPickCheckOut,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('correction-reason-field'),
          controller: reasonController,
          enabled: !busy,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: S.correctionReasonLabel,
            hintText: S.correctionReasonPlaceholder,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(error!, style: TextStyle(color: c.crit, fontSize: 12)),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : onCancel,
              child: const Text(S.cancelCorrection),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton(
              key: const Key('save-correction-button'),
              onPressed: busy ? null : onSave,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text(S.saveCorrection),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// A label with a time, forced left-to-right the same way
/// `DetachmentMemberStatusPage`'s equivalent pill is. [AppTime] owns the
/// bidirectional isolation, so the clock cannot flip inside Arabic text.
class _TimeLabel extends StatelessWidget {
  const _TimeLabel(
      {required this.label, required this.at, required this.color});

  final String label;
  final DateTime? at;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ', style: TextStyle(color: c.ink3, fontSize: 12)),
      Text(
        at == null ? '—' : AppTime.time(at!),
        textDirection: TextDirection.ltr,
        style: TextStyle(color: color, fontSize: 13),
      ),
    ]);
  }
}

/// One append-only history row: who, when, why, and the before/after
/// attendance it recorded. Never shows [AttendanceCorrectionAuthor.id] —
/// only [AttendanceCorrectionAuthor.displayName] is safe for the UI.
class _CorrectionEntry extends StatelessWidget {
  const _CorrectionEntry({required this.correction});

  final AttendanceCorrection correction;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.history_edu_rounded, size: 16, color: c.ink3),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${S.correctedBy} ${correction.author.displayName}',
              style: TextStyle(
                  color: c.ink, fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            AppTime.dayTime(correction.correctedAt),
            style: TextStyle(color: c.ink3, fontSize: 11),
          ),
        ]),
        const SizedBox(height: 6),
        Text(correction.reason, style: TextStyle(color: c.ink2, fontSize: 12)),
        const SizedBox(height: AppSpacing.sm),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _SnapshotChip(
                label: S.correctionBefore, snapshot: correction.before),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SnapshotChip(
                label: S.correctionAfter, snapshot: correction.after),
          ),
        ]),
      ]),
    );
  }
}

class _SnapshotChip extends StatelessWidget {
  const _SnapshotChip({required this.label, required this.snapshot});

  final String label;
  final AttendanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: c.ink3, fontSize: 10)),
        const SizedBox(height: 2),
        Text(_statusLabel(snapshot.status),
            style: TextStyle(
                color: c.ink, fontSize: 12, fontWeight: FontWeight.w600)),
        if (snapshot.checkInAt != null || snapshot.checkOutAt != null) ...[
          const SizedBox(height: 2),
          Text(
            snapshot.checkInAt != null
                ? AppTime.clockRange(
                    snapshot.checkInAt!,
                    snapshot.checkOutAt,
                  )
                : AppTime.time(snapshot.checkOutAt!),
            style: TextStyle(color: c.ink3, fontSize: 11),
          ),
        ],
      ]),
    );
  }
}

StatusKind _statusKind(AttendanceState s) => switch (s) {
      AttendanceState.checkedIn => StatusKind.ok,
      AttendanceState.checkedOut => StatusKind.info,
      AttendanceState.absent => StatusKind.crit,
      AttendanceState.notCheckedIn => StatusKind.muted,
    };

String _statusLabel(AttendanceState s) => switch (s) {
      AttendanceState.checkedIn => S.checkedIn,
      AttendanceState.checkedOut => S.checkedOut,
      AttendanceState.absent => S.absent,
      AttendanceState.notCheckedIn => S.notCheckedIn,
    };
