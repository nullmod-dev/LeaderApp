import 'package:flutter/material.dart';

import '../../../core/format/app_date.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/platform_audit_models.dart';
import 'platform_audit_copy.dart';

DateTime auditDayStart(DateTime day) =>
    DateTime(day.year, day.month, day.day).toUtc();
DateTime auditDayEndExclusive(DateTime day) =>
    DateTime(day.year, day.month, day.day + 1).toUtc();

int auditFilterCount(PlatformAuditQuery q) => [
      q.from,
      q.before,
      q.actorKind,
      q.actorId,
      q.action,
      q.category,
      q.tenantId,
      q.targetType
    ].where((v) => v != null).length;

Future<PlatformAuditQuery?> showPlatformAuditFilters(
        BuildContext context, PlatformAuditQuery query, DateTime now) =>
    showModalBottomSheet<PlatformAuditQuery>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: AnimationStyle(
          duration: effectiveDuration(context, MotionTokens.medium),
          reverseDuration: effectiveDuration(context, MotionTokens.short)),
      builder: (_) => _Filters(query: query, now: now),
    );

class _Filters extends StatefulWidget {
  const _Filters({required this.query, required this.now});
  final PlatformAuditQuery query;
  final DateTime now;
  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  late PlatformAuditActorKind? actorKind = widget.query.actorKind;
  late PlatformAuditCategory? category = widget.query.category;
  late PlatformAuditAction? action = widget.query.action;
  late PlatformAuditTargetResource? target = widget.query.targetType;
  late DateTime? from = widget.query.from?.toLocal();
  late DateTime? through =
      widget.query.before?.subtract(const Duration(microseconds: 1)).toLocal();
  late final actor = TextEditingController(text: widget.query.actorId);
  late final tenant = TextEditingController(text: widget.query.tenantId);

  @override
  void dispose() {
    actor.dispose();
    tenant.dispose();
    super.dispose();
  }

  Future<void> pick(bool start) async {
    final date = await showDatePicker(
        context: context,
        initialDate: (start ? from : through) ?? widget.now.toLocal(),
        currentDate: widget.now.toLocal(),
        firstDate: DateTime(1970),
        lastDate: DateTime(widget.now.toLocal().year + 10));
    if (date == null || !mounted) return;
    setState(() {
      if (start) {
        from = date;
      } else {
        through = date;
      }
    });
  }

  Widget dropdown<T>(String key, String label, T? value, List<T> values,
          String Function(T) copy, void Function(T?) change) =>
      Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: DropdownButtonFormField<T>(
              key: Key(key),
              initialValue: value,
              isExpanded: true,
              itemHeight: null,
              decoration: InputDecoration(labelText: label),
              items: [
                DropdownMenuItem<T>(value: null, child: const Text('الكل')),
                for (final v in values)
                  DropdownMenuItem(
                      value: v,
                      child: Text(copy(v),
                          maxLines: 2, overflow: TextOverflow.ellipsis))
              ],
              onChanged: (v) => setState(() => change(v))));

  @override
  Widget build(BuildContext context) {
    final invalid = from != null &&
        through != null &&
        auditDayStart(from!).isAfter(auditDayStart(through!));
    return FractionallySizedBox(
        heightFactor: .9,
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('تصفية سجل التدقيق',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.lg),
                  dropdown(
                      'audit-filter-category',
                      'الفئة',
                      category,
                      PlatformAuditCategory.values,
                      AuditCopy.category,
                      (v) => category = v),
                  dropdown(
                      'audit-filter-action',
                      'الإجراء',
                      action,
                      PlatformAuditAction.values,
                      AuditCopy.action,
                      (v) => action = v),
                  dropdown(
                      'audit-filter-actor-kind',
                      'نوع المنفّذ',
                      actorKind,
                      PlatformAuditActorKind.values,
                      (v) => switch (v) {
                            PlatformAuditActorKind.platformAdministrator =>
                              'مسؤول المنصة',
                            PlatformAuditActorKind.system => 'النظام',
                            PlatformAuditActorKind.unknown => 'غير معروف'
                          },
                      (v) => actorKind = v),
                  TextField(
                      key: const Key('audit-filter-actor-id'),
                      controller: actor,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'معرّف المنفّذ (اختياري)')),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                      key: const Key('audit-filter-tenant-id'),
                      controller: tenant,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'معرّف الفريق (اختياري)')),
                  const SizedBox(height: AppSpacing.md),
                  dropdown(
                      'audit-filter-target',
                      'نوع المورد',
                      target,
                      PlatformAuditTargetResource.values,
                      AuditCopy.resource,
                      (v) => target = v),
                  Text('التواريخ حسب التوقيت المحلي',
                      style: Theme.of(context).textTheme.bodySmall),
                  TextButton(
                      key: const Key('audit-filter-from'),
                      onPressed: () => pick(true),
                      child: Text(from == null
                          ? 'من تاريخ (اختياري)'
                          : 'من ${AppDate.dayMonthYear(from!)}')),
                  TextButton(
                      key: const Key('audit-filter-through'),
                      onPressed: () => pick(false),
                      child: Text(through == null
                          ? 'حتى تاريخ (اختياري)'
                          : 'حتى ${AppDate.dayMonthYear(through!)}')),
                  if (from != null || through != null)
                    TextButton(
                        onPressed: () => setState(() {
                              from = null;
                              through = null;
                            }),
                        child: const Text('مسح التواريخ')),
                  if (invalid)
                    const Text(
                        'يجب أن يسبق تاريخ البداية تاريخ النهاية أو يساويه.'),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                      key: const Key('audit-filter-apply'),
                      onPressed: invalid
                          ? null
                          : () {
                              String? optional(String value) =>
                                  value.trim().isEmpty ? null : value.trim();
                              Navigator.pop(
                                  context,
                                  PlatformAuditQuery(
                                      from: from == null
                                          ? null
                                          : auditDayStart(from!),
                                      before: through == null
                                          ? null
                                          : auditDayEndExclusive(through!),
                                      actorKind: actorKind,
                                      actorId: optional(actor.text),
                                      tenantId: optional(tenant.text),
                                      category: category,
                                      action: action,
                                      targetType: target,
                                      search: widget.query.search,
                                      limit: widget.query.limit));
                            },
                      child: const Text('تطبيق التصفية')),
                  TextButton(
                      key: const Key('audit-filter-reset'),
                      onPressed: () => Navigator.pop(
                          context,
                          PlatformAuditQuery(
                              search: widget.query.search,
                              limit: widget.query.limit)),
                      child: const Text('مسح عوامل التصفية')),
                ])));
  }
}
